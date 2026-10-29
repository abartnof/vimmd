#include "libvim_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <regex.h>

struct VimDocumentContext {
    char **lines;
    size_t line_count;
    size_t line_capacity;
    VimEngineMode mode;
    VimBytePos cursor;
    VimBytePos visual_anchor;
    bool visual_is_linewise;
    bool is_dirty;
    bool should_quit;
    VimSystemAction pending_action;
    char last_error[256];
    char cmd_buf[512];
    size_t cmd_len;
    char last_search[256];
    bool is_search_cmd;

    // Multi-key & pending state
    char pending_leader;
    char pending_operator;
    char pending_find;
    char pending_replace;
    char pending_text_object;
    int count_accumulator;

    // Yank register
    char *yank_buffer;
    bool yank_is_linewise;
    VimYankCallback yank_cb;
    void *yank_user_info;

    VimLineDeltaCallback delta_cb;
    void *user_info;

    // Upstream context state simulation
    void *buf_ptr;
    void *win_ptr;
    int mode_state;

    // Undo / Redo history
    struct VimUndoNode *undo_head;
    struct VimUndoNode *undo_tail;
    size_t undo_count;

    struct VimUndoNode *redo_head;
    struct VimUndoNode *redo_tail;
    size_t redo_count;

    bool in_insert_undo_group;
};

#define MAX_UNDO_LEVELS 100

typedef struct VimUndoNode {
    char **lines;
    size_t line_count;
    VimBytePos cursor;
    bool is_dirty;
    struct VimUndoNode *prev;
    struct VimUndoNode *next;
} VimUndoNode;


#define MAX_TRACKED_CONTEXTS 128
static struct VimDocumentContext *g_contexts[MAX_TRACKED_CONTEXTS];
static size_t g_context_count = 0;

static void register_context(struct VimDocumentContext *ctx) {
    if (g_context_count < MAX_TRACKED_CONTEXTS) {
        g_contexts[g_context_count++] = ctx;
    }
}

static void unregister_context(struct VimDocumentContext *ctx) {
    for (size_t i = 0; i < g_context_count; i++) {
        if (g_contexts[i] == ctx) {
            g_contexts[i] = g_contexts[g_context_count - 1];
            g_contexts[g_context_count - 1] = NULL;
            g_context_count--;
            break;
        }
    }
}

static struct VimDocumentContext *g_active_ctx = NULL;
static bool g_engine_initialized = false;

void vim_engine_init(void) {
    if (g_engine_initialized) {
        return;
    }
    g_engine_initialized = true;
}

void vim_activate_context(VimContextRef ctx) {
    if (g_active_ctx == ctx) {
        return;
    }
    if (g_active_ctx) {
        g_active_ctx->mode_state = (int)g_active_ctx->mode;
    }
    g_active_ctx = ctx;
    if (ctx) {
        ctx->mode = (VimEngineMode)ctx->mode_state;
    }
}

static char* duplicate_string(const char *src) {
    if (!src) return NULL;
    size_t len = strlen(src);
    char *copy = (char *)malloc(len + 1);
    if (copy) {
        memcpy(copy, src, len + 1);
    }
    return copy;
}

static void free_lines(char **lines, size_t count) {
    if (!lines) return;
    for (size_t i = 0; i < count; i++) {
        if (lines[i]) {
            free(lines[i]);
            lines[i] = NULL;
        }
    }
    free(lines);
}

static VimUndoNode* create_undo_node(struct VimDocumentContext *ctx) {
    if (!ctx || ctx->line_count == 0) return NULL;
    VimUndoNode *node = (VimUndoNode *)calloc(1, sizeof(VimUndoNode));
    if (!node) return NULL;
    node->line_count = ctx->line_count;
    node->cursor = ctx->cursor;
    node->is_dirty = ctx->is_dirty;
    node->lines = (char **)malloc(node->line_count * sizeof(char *));
    if (!node->lines) {
        free(node);
        return NULL;
    }
    for (size_t i = 0; i < node->line_count; i++) {
        node->lines[i] = duplicate_string(ctx->lines[i]);
    }
    return node;
}

static void free_undo_node(VimUndoNode *node) {
    if (!node) return;
    if (node->lines) {
        for (size_t i = 0; i < node->line_count; i++) {
            if (node->lines[i]) {
                free(node->lines[i]);
                node->lines[i] = NULL;
            }
        }
        free(node->lines);
        node->lines = NULL;
    }
    free(node);
}

static void clear_undo_stack(struct VimDocumentContext *ctx) {
    if (!ctx) return;
    VimUndoNode *curr = ctx->undo_head;
    while (curr) {
        VimUndoNode *next = curr->next;
        free_undo_node(curr);
        curr = next;
    }
    ctx->undo_head = NULL;
    ctx->undo_tail = NULL;
    ctx->undo_count = 0;
}

static void clear_redo_stack(struct VimDocumentContext *ctx) {
    if (!ctx) return;
    VimUndoNode *curr = ctx->redo_head;
    while (curr) {
        VimUndoNode *next = curr->next;
        free_undo_node(curr);
        curr = next;
    }
    ctx->redo_head = NULL;
    ctx->redo_tail = NULL;
    ctx->redo_count = 0;
}

static void push_undo_node(struct VimDocumentContext *ctx, VimUndoNode *node) {
    if (!ctx || !node) return;
    node->next = ctx->undo_head;
    node->prev = NULL;
    if (ctx->undo_head) {
        ctx->undo_head->prev = node;
    } else {
        ctx->undo_tail = node;
    }
    ctx->undo_head = node;
    ctx->undo_count++;

    while (ctx->undo_count > MAX_UNDO_LEVELS && ctx->undo_tail) {
        VimUndoNode *old_tail = ctx->undo_tail;
        ctx->undo_tail = old_tail->prev;
        if (ctx->undo_tail) {
            ctx->undo_tail->next = NULL;
        } else {
            ctx->undo_head = NULL;
        }
        free_undo_node(old_tail);
        ctx->undo_count--;
    }
}

static void push_redo_node(struct VimDocumentContext *ctx, VimUndoNode *node) {
    if (!ctx || !node) return;
    node->next = ctx->redo_head;
    node->prev = NULL;
    if (ctx->redo_head) {
        ctx->redo_head->prev = node;
    } else {
        ctx->redo_tail = node;
    }
    ctx->redo_head = node;
    ctx->redo_count++;

    while (ctx->redo_count > MAX_UNDO_LEVELS && ctx->redo_tail) {
        VimUndoNode *old_tail = ctx->redo_tail;
        ctx->redo_tail = old_tail->prev;
        if (ctx->redo_tail) {
            ctx->redo_tail->next = NULL;
        } else {
            ctx->redo_head = NULL;
        }
        free_undo_node(old_tail);
        ctx->redo_count--;
    }
}

static void snapshot_for_undo(struct VimDocumentContext *ctx) {
    if (!ctx) return;
    clear_redo_stack(ctx);
    VimUndoNode *node = create_undo_node(ctx);
    if (node) {
        push_undo_node(ctx, node);
    }
}


static bool ensure_line_capacity(struct VimDocumentContext *ctx, size_t needed) {
    if (needed <= ctx->line_capacity) return true;
    size_t new_cap = ctx->line_capacity == 0 ? 8 : ctx->line_capacity * 2;
    if (new_cap < needed) new_cap = needed;
    char **new_lines = (char **)realloc(ctx->lines, new_cap * sizeof(char *));
    if (!new_lines) return false;
    ctx->lines = new_lines;
    ctx->line_capacity = new_cap;
    return true;
}

static void clamp_cursor(struct VimDocumentContext *ctx) {
    if (!ctx || ctx->line_count == 0) return;

    if (ctx->cursor.line < 1) ctx->cursor.line = 1;
    if ((size_t)ctx->cursor.line > ctx->line_count) ctx->cursor.line = (int32_t)ctx->line_count;

    size_t line_idx = (size_t)(ctx->cursor.line - 1);
    size_t line_len = ctx->lines[line_idx] ? strlen(ctx->lines[line_idx]) : 0;

    int32_t max_col = (int32_t)line_len;
    if (ctx->mode == VIM_MODE_INSERT) {
        max_col += 1;
    }
    if (max_col < 1) max_col = 1;

    if (ctx->cursor.byteCol < 1) ctx->cursor.byteCol = 1;
    if (ctx->cursor.byteCol > max_col) ctx->cursor.byteCol = max_col;
}

VimContextRef vim_context_create(const char *initial_utf8) {
    struct VimDocumentContext *ctx = (struct VimDocumentContext *)calloc(1, sizeof(struct VimDocumentContext));
    if (!ctx) {
        return NULL;
    }

    ctx->mode = VIM_MODE_NORMAL;
    ctx->mode_state = (int)VIM_MODE_NORMAL;
    ctx->cursor.line = 1;
    ctx->cursor.byteCol = 1;
    ctx->visual_anchor.line = 1;
    ctx->visual_anchor.byteCol = 1;
    ctx->visual_is_linewise = false;
    ctx->is_dirty = false;
    ctx->should_quit = false;
    ctx->pending_action = VIM_ACTION_NONE;
    ctx->last_error[0] = '\0';
    ctx->cmd_buf[0] = '\0';
    ctx->cmd_len = 0;
    ctx->last_search[0] = '\0';
    ctx->is_search_cmd = false;
    ctx->pending_leader = 0;
    ctx->pending_operator = 0;
    ctx->pending_find = 0;
    ctx->pending_replace = 0;
    ctx->pending_text_object = 0;
    ctx->count_accumulator = 0;
    ctx->yank_buffer = NULL;
    ctx->yank_is_linewise = false;
    ctx->yank_cb = NULL;
    ctx->yank_user_info = NULL;

    if (!initial_utf8 || strlen(initial_utf8) == 0) {
        if (!ensure_line_capacity(ctx, 1)) {
            free(ctx);
            return NULL;
        }
        ctx->lines[0] = duplicate_string("");
        ctx->line_count = 1;
    } else {
        const char *p = initial_utf8;
        const char *line_start = p;

        while (*p) {
            if (*p == '\n') {
                size_t len = p - line_start;
                if (len > 0 && line_start[len - 1] == '\r') {
                    len--;
                }
                char *line_buf = (char *)malloc(len + 1);
                if (!line_buf) {
                    free_lines(ctx->lines, ctx->line_count);
                    free(ctx);
                    return NULL;
                }
                memcpy(line_buf, line_start, len);
                line_buf[len] = '\0';

                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) {
                    free(line_buf);
                    free_lines(ctx->lines, ctx->line_count);
                    free(ctx);
                    return NULL;
                }
                ctx->lines[ctx->line_count++] = line_buf;
                line_start = p + 1;
            }
            p++;
        }

        size_t len = p - line_start;
        if (len > 0 && line_start[len - 1] == '\r') {
            len--;
        }
        char *line_buf = (char *)malloc(len + 1);
        if (!line_buf) {
            free_lines(ctx->lines, ctx->line_count);
            free(ctx);
            return NULL;
        }
        memcpy(line_buf, line_start, len);
        line_buf[len] = '\0';

        if (!ensure_line_capacity(ctx, ctx->line_count + 1)) {
            free(line_buf);
            free_lines(ctx->lines, ctx->line_count);
            free(ctx);
            return NULL;
        }
        ctx->lines[ctx->line_count++] = line_buf;
    }

    register_context(ctx);
    vim_activate_context(ctx);
    return ctx;
}

void vim_context_destroy(VimContextRef ctx) {
    if (!ctx) return;
    unregister_context(ctx);
    if (g_active_ctx == ctx) {
        g_active_ctx = NULL;
    }
    if (ctx->yank_buffer) {
        free(ctx->yank_buffer);
        ctx->yank_buffer = NULL;
    }
    clear_undo_stack(ctx);
    clear_redo_stack(ctx);
    free_lines(ctx->lines, ctx->line_count);
    free(ctx);
}

VimEngineMode vim_context_get_mode(VimContextRef ctx) {
    if (!ctx) return VIM_MODE_NORMAL;
    return ctx->mode;
}

const char* vim_context_get_command_buffer(VimContextRef ctx) {
    if (!ctx) return "";
    return ctx->cmd_buf;
}

VimBytePos vim_context_get_cursor(VimContextRef ctx) {
    if (!ctx) {
        VimBytePos def = { .line = 1, .byteCol = 1 };
        return def;
    }
    return ctx->cursor;
}

void vim_context_set_cursor(VimContextRef ctx, int32_t line, int32_t byteCol) {
    if (!ctx) return;
    ctx->cursor.line = line;
    ctx->cursor.byteCol = byteCol;
    clamp_cursor(ctx);
}

VimBytePos vim_context_get_visual_anchor(VimContextRef ctx) {
    if (!ctx) {
        VimBytePos def = { .line = 1, .byteCol = 1 };
        return def;
    }
    return ctx->visual_anchor;
}

void vim_context_set_visual_anchor(VimContextRef ctx, int32_t line, int32_t byteCol) {
    if (!ctx) return;
    ctx->visual_anchor.line = line;
    ctx->visual_anchor.byteCol = byteCol;
}

bool vim_context_is_visual_linewise(VimContextRef ctx) {
    if (!ctx) return false;
    return ctx->visual_is_linewise;
}

const char* vim_context_get_last_search(VimContextRef ctx) {
    if (!ctx || ctx->last_search[0] == '\0') return NULL;
    return ctx->last_search;
}

void vim_context_set_last_search(VimContextRef ctx, const char *pattern) {
    if (!ctx || !pattern) return;
    strncpy(ctx->last_search, pattern, sizeof(ctx->last_search) - 1);
    ctx->last_search[sizeof(ctx->last_search) - 1] = '\0';
}

bool vim_context_is_dirty(VimContextRef ctx) {
    if (!ctx) return false;
    return ctx->is_dirty;
}

void vim_context_clear_dirty(VimContextRef ctx) {
    if (!ctx) return;
    ctx->is_dirty = false;
}

bool vim_context_should_quit(VimContextRef ctx) {
    if (!ctx) return false;
    return ctx->should_quit;
}

VimSystemAction vim_context_get_pending_action(VimContextRef ctx) {
    if (!ctx) return VIM_ACTION_NONE;
    return ctx->pending_action;
}

void vim_context_clear_pending_action(VimContextRef ctx) {
    if (!ctx) return;
    ctx->pending_action = VIM_ACTION_NONE;
}

const char* vim_context_get_last_error(VimContextRef ctx) {
    if (!ctx) return "";
    return ctx->last_error;
}

void vim_context_set_delta_callback(VimContextRef ctx, VimLineDeltaCallback cb, void *userInfo) {
    if (!ctx) return;
    ctx->delta_cb = cb;
    ctx->user_info = userInfo;
}

void vim_context_dispatch_delta(VimContextRef ctx, int32_t startLine, int32_t deletedCount, const char **newLines, int32_t addedCount) {
    if (!ctx || !ctx->delta_cb) return;
    ctx->delta_cb(startLine, deletedCount, newLines, addedCount, ctx->user_info);
}

static void emit_line_delta(struct VimDocumentContext *ctx, int32_t startLine, int32_t deletedCount, int32_t addedCount) {
    if (!ctx || !ctx->delta_cb) return;
    const char **lines_ptr = NULL;
    if (addedCount > 0) {
        lines_ptr = (const char **)malloc(addedCount * sizeof(char *));
        if (lines_ptr) {
            for (int32_t i = 0; i < addedCount; i++) {
                size_t idx = (size_t)(startLine - 1 + i);
                lines_ptr[i] = (idx < ctx->line_count) ? ctx->lines[idx] : "";
            }
        }
    }
    ctx->delta_cb(startLine, deletedCount, lines_ptr, addedCount, ctx->user_info);
    if (lines_ptr) {
        free(lines_ptr);
    }
}

// MARK: - Word Category & Motions
static inline bool is_word_char(char c) {
    return (isalnum((unsigned char)c) || c == '_');
}

static inline int char_category(char c) {
    if (c == ' ' || c == '\t' || c == '\0' || c == '\r' || c == '\n') return 0; // whitespace
    if (is_word_char(c)) return 1; // word
    return 2; // punctuation
}

static void motion_caret(struct VimDocumentContext *ctx) {
    if (ctx->cursor.line < 1 || (size_t)ctx->cursor.line > ctx->line_count) return;
    const char *line = ctx->lines[ctx->cursor.line - 1];
    size_t c = 0;
    while (line[c] == ' ' || line[c] == '\t') c++;
    ctx->cursor.byteCol = (line[c] != '\0') ? (int32_t)(c + 1) : 1;
}

static void motion_dollar(struct VimDocumentContext *ctx) {
    if (ctx->cursor.line < 1 || (size_t)ctx->cursor.line > ctx->line_count) return;
    size_t len = strlen(ctx->lines[ctx->cursor.line - 1]);
    ctx->cursor.byteCol = len > 0 ? (int32_t)len : 1;
}

static void motion_G(struct VimDocumentContext *ctx, int target_line) {
    if (target_line < 1 || (size_t)target_line > ctx->line_count) {
        target_line = (int)ctx->line_count;
    }
    ctx->cursor.line = target_line;
    motion_caret(ctx);
    clamp_cursor(ctx);
}

static void motion_w(struct VimDocumentContext *ctx, int count) {
    for (int rep = 0; rep < count; rep++) {
        if ((size_t)ctx->cursor.line > ctx->line_count) break;
        const char *line = ctx->lines[ctx->cursor.line - 1];
        size_t len = strlen(line);
        size_t idx = (ctx->cursor.byteCol > 0) ? (size_t)(ctx->cursor.byteCol - 1) : 0;

        if (idx >= len) {
            // At or past end of line, advance to next line
            if ((size_t)ctx->cursor.line < ctx->line_count) {
                ctx->cursor.line++;
                line = ctx->lines[ctx->cursor.line - 1];
                len = strlen(line);
                idx = 0;
                while (idx < len && (line[idx] == ' ' || line[idx] == '\t')) idx++;
                ctx->cursor.byteCol = (int32_t)(idx + 1);
            }
            continue;
        }

        int cat = char_category(line[idx]);
        if (cat != 0) {
            while (idx < len && char_category(line[idx]) == cat) idx++;
        }
        while (idx < len && char_category(line[idx]) == 0) idx++;

        if (idx >= len) {
            if ((size_t)ctx->cursor.line < ctx->line_count) {
                ctx->cursor.line++;
                line = ctx->lines[ctx->cursor.line - 1];
                len = strlen(line);
                idx = 0;
                while (idx < len && (line[idx] == ' ' || line[idx] == '\t')) idx++;
                ctx->cursor.byteCol = (int32_t)(idx + 1);
            } else {
                ctx->cursor.byteCol = len > 0 ? (int32_t)len : 1;
            }
        } else {
            ctx->cursor.byteCol = (int32_t)(idx + 1);
        }
    }
    clamp_cursor(ctx);
}

static void motion_b(struct VimDocumentContext *ctx, int count) {
    for (int rep = 0; rep < count; rep++) {
        if (ctx->cursor.line == 1 && ctx->cursor.byteCol <= 1) break;
        size_t line_idx = (size_t)(ctx->cursor.line - 1);
        const char *line = ctx->lines[line_idx];
        size_t idx = (ctx->cursor.byteCol > 1) ? (size_t)(ctx->cursor.byteCol - 2) : 0;

        if (ctx->cursor.byteCol <= 1) {
            if (ctx->cursor.line > 1) {
                ctx->cursor.line--;
                line = ctx->lines[ctx->cursor.line - 1];
                size_t len = strlen(line);
                ctx->cursor.byteCol = len > 0 ? (int32_t)len : 1;
            }
            continue;
        }

        while (idx > 0 && char_category(line[idx]) == 0) idx--;
        int cat = char_category(line[idx]);
        while (idx > 0 && char_category(line[idx - 1]) == cat) idx--;

        ctx->cursor.byteCol = (int32_t)(idx + 1);
    }
    clamp_cursor(ctx);
}

static void motion_e(struct VimDocumentContext *ctx, int count) {
    for (int rep = 0; rep < count; rep++) {
        if ((size_t)ctx->cursor.line > ctx->line_count) break;
        const char *line = ctx->lines[ctx->cursor.line - 1];
        size_t len = strlen(line);
        size_t idx = (size_t)(ctx->cursor.byteCol - 1);

        if (idx + 1 < len) {
            idx++;
        } else if ((size_t)ctx->cursor.line < ctx->line_count) {
            ctx->cursor.line++;
            line = ctx->lines[ctx->cursor.line - 1];
            len = strlen(line);
            idx = 0;
        } else {
            break;
        }

        while (idx < len && char_category(line[idx]) == 0) idx++;
        if (idx < len) {
            int cat = char_category(line[idx]);
            while (idx + 1 < len && char_category(line[idx + 1]) == cat) idx++;
        }
        ctx->cursor.byteCol = (int32_t)(idx + 1);
    }
    clamp_cursor(ctx);
}

static void motion_ge(struct VimDocumentContext *ctx, int count) {
    for (int rep = 0; rep < count; rep++) {
        if (ctx->cursor.line == 1 && ctx->cursor.byteCol <= 1) break;
        if (ctx->cursor.byteCol <= 1) {
            if (ctx->cursor.line > 1) {
                ctx->cursor.line--;
                const char *line = ctx->lines[ctx->cursor.line - 1];
                size_t len = strlen(line);
                ctx->cursor.byteCol = len > 0 ? (int32_t)len : 1;
            }
            continue;
        }

        const char *line = ctx->lines[ctx->cursor.line - 1];
        size_t idx = (size_t)(ctx->cursor.byteCol - 2);

        // If currently in a word, skip to preceding non-word or start
        while (idx > 0 && char_category(line[idx]) != 0) idx--;
        while (idx > 0 && char_category(line[idx]) == 0) idx--;

        ctx->cursor.byteCol = (int32_t)(idx + 1);
    }
    clamp_cursor(ctx);
}

static void motion_find(struct VimDocumentContext *ctx, char target, bool till) {
    if (ctx->cursor.line < 1 || (size_t)ctx->cursor.line > ctx->line_count) return;
    const char *line = ctx->lines[ctx->cursor.line - 1];
    size_t len = strlen(line);
    size_t start = (size_t)ctx->cursor.byteCol; // 0-based index of character after cursor

    for (size_t i = start; i < len; i++) {
        if (line[i] == target) {
            if (till) {
                ctx->cursor.byteCol = (i > 0) ? (int32_t)i : 1;
            } else {
                ctx->cursor.byteCol = (int32_t)(i + 1);
            }
            break;
        }
    }
    clamp_cursor(ctx);
}

// MARK: - Search Engine
static bool search_line_forward(const char *line, const char *pattern, size_t start_col, size_t *out_col) {
    if (!line || !pattern) return false;
    size_t line_len = strlen(line);
    if (start_col >= line_len) return false;

    regex_t re;
    if (regcomp(&re, pattern, REG_EXTENDED) == 0) {
        regmatch_t pmatch;
        size_t cur = start_col;
        bool found = false;
        while (cur < line_len) {
            if (regexec(&re, line + cur, 1, &pmatch, 0) == 0 && pmatch.rm_so != -1) {
                *out_col = cur + pmatch.rm_so;
                found = true;
                break;
            }
            cur++;
        }
        regfree(&re);
        return found;
    } else {
        const char *sub = strstr(line + start_col, pattern);
        if (sub) {
            *out_col = (size_t)(sub - line);
            return true;
        }
    }
    return false;
}

static bool vim_search_forward(struct VimDocumentContext *ctx, const char *pattern, bool advance_first) {
    if (!ctx || !pattern || strlen(pattern) == 0) return false;
    size_t cur_line = (size_t)ctx->cursor.line;
    size_t cur_col = (size_t)(ctx->cursor.byteCol - 1);
    if (advance_first) cur_col++;

    // 1. Search from current line/col to end of buffer
    for (size_t l = cur_line; l <= ctx->line_count; l++) {
        size_t start = (l == cur_line) ? cur_col : 0;
        size_t match_col = 0;
        if (search_line_forward(ctx->lines[l - 1], pattern, start, &match_col)) {
            ctx->cursor.line = (int32_t)l;
            ctx->cursor.byteCol = (int32_t)(match_col + 1);
            clamp_cursor(ctx);
            ctx->last_error[0] = '\0';
            return true;
        }
    }

    // 2. Wrap around from line 1 to cur_line
    for (size_t l = 1; l <= cur_line; l++) {
        size_t match_col = 0;
        if (search_line_forward(ctx->lines[l - 1], pattern, 0, &match_col)) {
            if (l == cur_line && match_col >= cur_col) break; // Don't match past where we started
            ctx->cursor.line = (int32_t)l;
            ctx->cursor.byteCol = (int32_t)(match_col + 1);
            clamp_cursor(ctx);
            ctx->last_error[0] = '\0';
            return true;
        }
    }

    snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", pattern);
    return false;
}

static bool search_line_backward(const char *line, const char *pattern, size_t max_col, size_t *out_col) {
    if (!line || !pattern) return false;
    size_t line_len = strlen(line);
    if (line_len == 0) return false;

    regex_t re;
    bool found = false;
    size_t best = 0;

    if (regcomp(&re, pattern, REG_EXTENDED) == 0) {
        regmatch_t pmatch;
        size_t cur = 0;
        while (cur < line_len) {
            if (regexec(&re, line + cur, 1, &pmatch, 0) == 0 && pmatch.rm_so != -1) {
                size_t m = cur + pmatch.rm_so;
                if (m <= max_col) {
                    best = m;
                    found = true;
                }
                cur = m + 1;
            } else {
                break;
            }
        }
        regfree(&re);
    } else {
        const char *sub = line;
        while ((sub = strstr(sub, pattern)) != NULL) {
            size_t m = (size_t)(sub - line);
            if (m <= max_col) {
                best = m;
                found = true;
            }
            sub += 1;
        }
    }

    if (found) {
        *out_col = best;
        return true;
    }
    return false;
}

static bool vim_search_backward(struct VimDocumentContext *ctx, const char *pattern) {
    if (!ctx || !pattern || strlen(pattern) == 0) return false;
    size_t cur_line = (size_t)ctx->cursor.line;
    size_t cur_col = (ctx->cursor.byteCol > 1) ? (size_t)(ctx->cursor.byteCol - 2) : 0;

    // 1. Search backwards on current line
    if (ctx->cursor.byteCol > 1) {
        size_t match_col = 0;
        if (search_line_backward(ctx->lines[cur_line - 1], pattern, cur_col, &match_col)) {
            ctx->cursor.line = (int32_t)cur_line;
            ctx->cursor.byteCol = (int32_t)(match_col + 1);
            clamp_cursor(ctx);
            ctx->last_error[0] = '\0';
            return true;
        }
    }

    // 2. Search backwards from cur_line - 1 down to 1
    if (cur_line > 1) {
        for (size_t l = cur_line - 1; l >= 1; l--) {
            size_t len = strlen(ctx->lines[l - 1]);
            size_t max_c = len > 0 ? len - 1 : 0;
            size_t match_col = 0;
            if (search_line_backward(ctx->lines[l - 1], pattern, max_c, &match_col)) {
                ctx->cursor.line = (int32_t)l;
                ctx->cursor.byteCol = (int32_t)(match_col + 1);
                clamp_cursor(ctx);
                ctx->last_error[0] = '\0';
                return true;
            }
        }
    }

    // 3. Wrap around from line_count down to cur_line
    for (size_t l = ctx->line_count; l >= cur_line; l--) {
        size_t len = strlen(ctx->lines[l - 1]);
        size_t max_c = len > 0 ? len - 1 : 0;
        if (l == cur_line) {
            if (ctx->cursor.byteCol <= 1) break;
            max_c = cur_col;
        }
        size_t match_col = 0;
        if (search_line_backward(ctx->lines[l - 1], pattern, max_c, &match_col)) {
            ctx->cursor.line = (int32_t)l;
            ctx->cursor.byteCol = (int32_t)(match_col + 1);
            clamp_cursor(ctx);
            ctx->last_error[0] = '\0';
            return true;
        }
    }

    snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", pattern);
    return false;
}

// MARK: - Text Objects
typedef struct {
    bool found;
    bool is_empty;
    int32_t open_line;  // 1-based
    int32_t open_col;   // 1-based
    int32_t close_line; // 1-based
    int32_t close_col;  // 1-based
} InnerTextObjectBounds;

static bool resolve_inner_bounds(struct VimDocumentContext *ctx, char delim, InnerTextObjectBounds *bounds) {
    if (!ctx || !bounds || ctx->cursor.line < 1 || (size_t)ctx->cursor.line > ctx->line_count) return false;
    memset(bounds, 0, sizeof(*bounds));

    if (delim == '\'' || delim == '"') {
        const char *line = ctx->lines[ctx->cursor.line - 1];
        size_t len = strlen(line);
        if (len < 2) return false;

        size_t cur = (size_t)(ctx->cursor.byteCol - 1);
        int open_idx = -1;
        int close_idx = -1;

        int first_q = -1;
        for (size_t i = 0; i < len; i++) {
            if (line[i] == delim) {
                if (first_q == -1) {
                    first_q = (int)i;
                } else {
                    int p_open = first_q;
                    int p_close = (int)i;
                    first_q = -1;

                    if ((int)cur >= p_open && (int)cur <= p_close) {
                        open_idx = p_open;
                        close_idx = p_close;
                        break;
                    }
                    if ((int)cur < p_open && open_idx == -1) {
                        open_idx = p_open;
                        close_idx = p_close;
                        break;
                    }
                }
            }
        }

        if (open_idx != -1 && close_idx != -1) {
            bounds->found = true;
            bounds->open_line = ctx->cursor.line;
            bounds->open_col = open_idx + 1;
            bounds->close_line = ctx->cursor.line;
            bounds->close_col = close_idx + 1;
            bounds->is_empty = (close_idx == open_idx + 1);
            return true;
        }
        return false;
    }

    char open_ch = '(';
    char close_ch = ')';
    if (delim == '[' || delim == ']') {
        open_ch = '['; close_ch = ']';
    } else if (delim == '<' || delim == '>') {
        open_ch = '<'; close_ch = '>';
    } else if (delim == '{' || delim == '}' || delim == 'B') {
        open_ch = '{'; close_ch = '}';
    } else if (delim == '(' || delim == ')' || delim == 'b') {
        open_ch = '('; close_ch = ')';
    } else {
        return false;
    }

    int open_line = -1;
    int open_col = -1;
    int depth = 0;

    for (int l = ctx->cursor.line; l >= 1; l--) {
        const char *line = ctx->lines[l - 1];
        size_t len = strlen(line);
        int start = (l == ctx->cursor.line) ? (ctx->cursor.byteCol - 1) : ((int)len - 1);
        if (l == ctx->cursor.line && start >= 0 && (size_t)start < len && line[start] == close_ch) {
            start--;
        }

        for (int c = start; c >= 0; c--) {
            if (line[c] == close_ch) {
                depth++;
            } else if (line[c] == open_ch) {
                if (depth > 0) {
                    depth--;
                } else {
                    open_line = l;
                    open_col = c + 1;
                    goto found_open;
                }
            }
        }
    }

    {
        const char *line = ctx->lines[ctx->cursor.line - 1];
        size_t len = strlen(line);
        for (size_t c = (size_t)(ctx->cursor.byteCol - 1); c < len; c++) {
            if (line[c] == open_ch) {
                open_line = ctx->cursor.line;
                open_col = (int)(c + 1);
                goto found_open;
            }
        }
    }

found_open:
    if (open_line == -1) return false;

    int close_line = -1;
    int close_col = -1;
    depth = 1;

    for (size_t l = (size_t)open_line; l <= ctx->line_count; l++) {
        const char *line = ctx->lines[l - 1];
        size_t len = strlen(line);
        size_t start = (l == (size_t)open_line) ? (size_t)open_col : 0;

        for (size_t c = start; c < len; c++) {
            if (line[c] == open_ch) {
                depth++;
            } else if (line[c] == close_ch) {
                depth--;
                if (depth == 0) {
                    close_line = (int)l;
                    close_col = (int)(c + 1);
                    goto found_close;
                }
            }
        }
    }

found_close:
    if (close_line == -1) return false;

    bounds->found = true;
    bounds->open_line = open_line;
    bounds->open_col = open_col;
    bounds->close_line = close_line;
    bounds->close_col = close_col;
    bounds->is_empty = (open_line == close_line && close_col == open_col + 1);
    return true;
}

static bool handle_visual_text_object(struct VimDocumentContext *ctx, char delim) {
    if (!ctx) return false;
    InnerTextObjectBounds bounds;
    if (!resolve_inner_bounds(ctx, delim, &bounds)) return false;

    if (bounds.is_empty) {
        ctx->visual_anchor.line = bounds.open_line;
        ctx->visual_anchor.byteCol = bounds.open_col + 1;
        ctx->cursor.line = bounds.open_line;
        ctx->cursor.byteCol = bounds.open_col;
    } else {
        ctx->visual_anchor.line = bounds.open_line;
        ctx->visual_anchor.byteCol = bounds.open_col + 1;
        ctx->cursor.line = bounds.close_line;
        ctx->cursor.byteCol = bounds.close_col - 1;
    }
    clamp_cursor(ctx);
    return true;
}

// MARK: - Operators, Yank & Paste
static void set_yank_buffer(struct VimDocumentContext *ctx, const char *str, bool linewise) {
    if (!ctx) return;
    if (ctx->yank_buffer) {
        free(ctx->yank_buffer);
        ctx->yank_buffer = NULL;
    }
    ctx->yank_buffer = duplicate_string(str ? str : "");
    ctx->yank_is_linewise = linewise;

    if (ctx->yank_cb && ctx->yank_buffer) {
        ctx->yank_cb(ctx->yank_buffer, ctx->yank_is_linewise, ctx->yank_user_info);
    }
}

static char* extract_inner_text(struct VimDocumentContext *ctx, const InnerTextObjectBounds *bounds) {
    if (!ctx || !bounds || !bounds->found || bounds->is_empty) {
        return duplicate_string("");
    }

    if (bounds->open_line == bounds->close_line) {
        size_t l_idx = (size_t)(bounds->open_line - 1);
        const char *line = ctx->lines[l_idx];
        size_t len = strlen(line);
        size_t start = (size_t)bounds->open_col;
        size_t end = (size_t)(bounds->close_col - 1);
        if (start >= end || start >= len) {
            return duplicate_string("");
        }
        if (end > len) end = len;
        size_t inner_len = end - start;
        char *buf = (char *)malloc(inner_len + 1);
        if (buf) {
            memcpy(buf, line + start, inner_len);
            buf[inner_len] = '\0';
        }
        return buf ? buf : duplicate_string("");
    }

    // Multiline extraction
    size_t open_idx = (size_t)(bounds->open_line - 1);
    size_t close_idx = (size_t)(bounds->close_line - 1);
    const char *line1 = ctx->lines[open_idx];
    size_t len1 = strlen(line1);
    size_t start1 = (size_t)bounds->open_col;
    size_t part1_len = (len1 > start1) ? (len1 - start1) : 0;

    const char *line2 = ctx->lines[close_idx];
    size_t len2 = strlen(line2);
    size_t end2 = (size_t)(bounds->close_col - 1);
    size_t part2_len = (end2 < len2) ? end2 : len2;

    size_t total_len = part1_len + 1; // +1 for '\n'
    for (size_t l = open_idx + 1; l < close_idx; l++) {
        total_len += strlen(ctx->lines[l]) + 1;
    }
    total_len += part2_len;

    char *buf = (char *)malloc(total_len + 1);
    if (!buf) return duplicate_string("");

    char *dst = buf;
    if (part1_len > 0) {
        memcpy(dst, line1 + start1, part1_len);
        dst += part1_len;
    }
    *dst++ = '\n';

    for (size_t l = open_idx + 1; l < close_idx; l++) {
        size_t mid_len = strlen(ctx->lines[l]);
        memcpy(dst, ctx->lines[l], mid_len);
        dst += mid_len;
        *dst++ = '\n';
    }

    if (part2_len > 0) {
        memcpy(dst, line2, part2_len);
        dst += part2_len;
    }
    *dst = '\0';
    return buf;
}

static void handle_operator_inner_text_object(struct VimDocumentContext *ctx, char op, char delim) {
    if (!ctx) return;
    InnerTextObjectBounds bounds;
    if (!resolve_inner_bounds(ctx, delim, &bounds)) {
        return;
    }

    char *yanked = extract_inner_text(ctx, &bounds);
    set_yank_buffer(ctx, yanked ? yanked : "", false);
    if (yanked) free(yanked);

    if (op == 'y') {
        // Yank inner: buffer unmodified, cursor returns to starting position
        return;
    }

    // op is 'd' or 'c'
    snapshot_for_undo(ctx);

    if (bounds.is_empty) {
        ctx->cursor.line = bounds.open_line;
        ctx->cursor.byteCol = bounds.open_col + 1;
        if (op == 'c') {
            ctx->in_insert_undo_group = true;
            ctx->mode = VIM_MODE_INSERT;
        } else {
            ctx->mode = VIM_MODE_NORMAL;
            clamp_cursor(ctx);
        }
        return;
    }

    if (bounds.open_line == bounds.close_line) {
        size_t l_idx = (size_t)(bounds.open_line - 1);
        char *line = ctx->lines[l_idx];
        size_t len = strlen(line);
        size_t start = (size_t)bounds.open_col;
        size_t end = (size_t)(bounds.close_col - 1);
        if (end > len) end = len;
        if (start < end) {
            memmove(line + start, line + end, len - end + 1);
        }
        ctx->cursor.line = bounds.open_line;
        ctx->cursor.byteCol = bounds.open_col + 1;
        ctx->is_dirty = true;
        emit_line_delta(ctx, bounds.open_line, 1, 1);
    } else {
        size_t open_idx = (size_t)(bounds.open_line - 1);
        size_t close_idx = (size_t)(bounds.close_line - 1);
        size_t prefix_len = (size_t)bounds.open_col;
        const char *close_line = ctx->lines[close_idx];
        size_t close_char_idx = (size_t)(bounds.close_col - 1);
        size_t suffix_len = (close_char_idx < strlen(close_line)) ? strlen(close_line + close_char_idx) : 0;

        char *new_line = (char *)malloc(prefix_len + suffix_len + 1);
        if (new_line) {
            memcpy(new_line, ctx->lines[open_idx], prefix_len);
            if (suffix_len > 0) {
                memcpy(new_line + prefix_len, close_line + close_char_idx, suffix_len);
            }
            new_line[prefix_len + suffix_len] = '\0';
        }

        for (size_t l = open_idx; l <= close_idx; l++) {
            free(ctx->lines[l]);
        }
        ctx->lines[open_idx] = new_line ? new_line : duplicate_string("");

        size_t deleted_lines = close_idx - open_idx;
        size_t remaining = ctx->line_count - (close_idx + 1);
        if (remaining > 0) {
            memmove(&ctx->lines[open_idx + 1], &ctx->lines[close_idx + 1], remaining * sizeof(char *));
        }
        ctx->line_count -= deleted_lines;

        ctx->cursor.line = bounds.open_line;
        ctx->cursor.byteCol = bounds.open_col + 1;
        ctx->is_dirty = true;
        emit_line_delta(ctx, bounds.open_line, (int32_t)(deleted_lines + 1), 1);
    }

    if (op == 'c') {
        ctx->in_insert_undo_group = true;
        ctx->mode = VIM_MODE_INSERT;
    } else {
        ctx->mode = VIM_MODE_NORMAL;
        clamp_cursor(ctx);
    }
}

void vim_context_set_yank_callback(VimContextRef ctx, VimYankCallback cb, void *userInfo) {
    if (!ctx) return;
    ctx->yank_cb = cb;
    ctx->yank_user_info = userInfo;
}

const char* vim_context_get_yank_buffer(VimContextRef ctx, bool *out_linewise) {
    if (!ctx) return NULL;
    if (out_linewise) {
        *out_linewise = ctx->yank_is_linewise;
    }
    return ctx->yank_buffer;
}

void vim_context_set_yank_buffer(VimContextRef ctx, const char *text, bool linewise) {
    if (!ctx) return;
    if (ctx->yank_buffer) {
        free(ctx->yank_buffer);
        ctx->yank_buffer = NULL;
    }
    ctx->yank_buffer = duplicate_string(text ? text : "");
    ctx->yank_is_linewise = linewise;
}

static void yank_linewise_range(struct VimDocumentContext *ctx, int32_t start_l, int32_t end_l) {
    if (!ctx) return;
    if (start_l < 1) start_l = 1;
    if ((size_t)end_l > ctx->line_count) end_l = (int32_t)ctx->line_count;
    if (start_l > end_l) return;

    size_t total_len = 0;
    for (int32_t l = start_l; l <= end_l; l++) {
        total_len += strlen(ctx->lines[l - 1]) + 1;
    }
    char *buf = (char *)malloc(total_len + 1);
    if (!buf) return;
    char *cur = buf;
    for (int32_t l = start_l; l <= end_l; l++) {
        size_t len = strlen(ctx->lines[l - 1]);
        memcpy(cur, ctx->lines[l - 1], len);
        cur += len;
        *cur++ = '\n';
    }
    *cur = '\0';
    set_yank_buffer(ctx, buf, true);
    free(buf);
}

static char** split_lines(const char *text, size_t *out_count, bool linewise) {
    if (!text) {
        *out_count = 0;
        return NULL;
    }
    size_t len = strlen(text);
    if (len == 0) {
        *out_count = 0;
        return NULL;
    }

    size_t count = 0;
    const char *p = text;
    while (*p) {
        if (*p == '\n') count++;
        p++;
    }
    if (text[len - 1] != '\n') {
        count++;
    }
    if (count == 0 && linewise) {
        count = 1;
    }
    if (count == 0) {
        *out_count = 0;
        return NULL;
    }

    char **lines = (char **)malloc(count * sizeof(char *));
    if (!lines) {
        *out_count = 0;
        return NULL;
    }

    size_t idx = 0;
    const char *start = text;
    p = text;
    while (*p) {
        if (*p == '\n') {
            size_t line_len = p - start;
            if (line_len > 0 && start[line_len - 1] == '\r') {
                line_len--;
            }
            char *s = (char *)malloc(line_len + 1);
            if (s) {
                memcpy(s, start, line_len);
                s[line_len] = '\0';
                lines[idx++] = s;
            }
            start = p + 1;
        }
        p++;
    }
    if (p > start || text[len - 1] != '\n') {
        size_t line_len = p - start;
        if (line_len > 0 && start[line_len - 1] == '\r') {
            line_len--;
        }
        char *s = (char *)malloc(line_len + 1);
        if (s) {
            memcpy(s, start, line_len);
            s[line_len] = '\0';
            lines[idx++] = s;
        }
    }
    *out_count = idx;
    return lines;
}

static void paste_text(struct VimDocumentContext *ctx, bool after) {
    if (!ctx || !ctx->yank_buffer) return;
    snapshot_for_undo(ctx);

    if (ctx->yank_is_linewise) {
        size_t num_lines = 0;
        char **p_lines = split_lines(ctx->yank_buffer, &num_lines, true);
        if (!p_lines || num_lines == 0) {
            if (p_lines) free(p_lines);
            return;
        }

        int32_t insert_line = after ? ctx->cursor.line + 1 : ctx->cursor.line;
        if (!ensure_line_capacity(ctx, ctx->line_count + num_lines)) {
            for (size_t i = 0; i < num_lines; i++) free(p_lines[i]);
            free(p_lines);
            return;
        }

        size_t idx = (size_t)(insert_line - 1);
        if (idx > ctx->line_count) idx = ctx->line_count;

        memmove(&ctx->lines[idx + num_lines], &ctx->lines[idx], (ctx->line_count - idx) * sizeof(char *));
        for (size_t i = 0; i < num_lines; i++) {
            ctx->lines[idx + i] = p_lines[i];
        }
        free(p_lines);
        ctx->line_count += num_lines;

        ctx->cursor.line = insert_line;
        ctx->cursor.byteCol = 1;
        ctx->is_dirty = true;
        emit_line_delta(ctx, insert_line, 0, (int32_t)num_lines);
    } else {
        size_t l_idx = (size_t)(ctx->cursor.line - 1);
        char *line = ctx->lines[l_idx];
        size_t line_len = strlen(line);
        size_t pos = (size_t)(ctx->cursor.byteCol - 1);
        if (after && line_len > 0) pos++;
        if (pos > line_len) pos = line_len;

        if (strchr(ctx->yank_buffer, '\n') == NULL) {
            size_t y_len = strlen(ctx->yank_buffer);
            char *new_line = (char *)malloc(line_len + y_len + 1);
            if (!new_line) return;

            memcpy(new_line, line, pos);
            memcpy(new_line + pos, ctx->yank_buffer, y_len);
            memcpy(new_line + pos + y_len, line + pos, line_len - pos + 1);

            free(line);
            ctx->lines[l_idx] = new_line;
            ctx->cursor.byteCol = (int32_t)(pos + y_len);
            ctx->is_dirty = true;
            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
        } else {
            size_t num_lines = 0;
            char **p_lines = split_lines(ctx->yank_buffer, &num_lines, false);
            if (!p_lines || num_lines == 0) {
                if (p_lines) free(p_lines);
                return;
            }
            if (num_lines == 1) {
                size_t y_len = strlen(p_lines[0]);
                char *new_line = (char *)malloc(line_len + y_len + 1);
                if (new_line) {
                    memcpy(new_line, line, pos);
                    memcpy(new_line + pos, p_lines[0], y_len);
                    memcpy(new_line + pos + y_len, line + pos, line_len - pos + 1);
                    free(line);
                    ctx->lines[l_idx] = new_line;
                    ctx->cursor.byteCol = (int32_t)(pos + y_len);
                    ctx->is_dirty = true;
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                free(p_lines[0]);
                free(p_lines);
            } else {
                if (!ensure_line_capacity(ctx, ctx->line_count + num_lines - 1)) {
                    for (size_t i = 0; i < num_lines; i++) free(p_lines[i]);
                    free(p_lines);
                    return;
                }
                char *line_prefix = (char *)malloc(pos + 1);
                if (line_prefix) {
                    memcpy(line_prefix, line, pos);
                    line_prefix[pos] = '\0';
                }
                char *line_suffix = duplicate_string(line + pos);

                size_t len_first = pos + strlen(p_lines[0]);
                char *first_line = (char *)malloc(len_first + 1);
                if (first_line) {
                    if (line_prefix) memcpy(first_line, line_prefix, pos);
                    memcpy(first_line + pos, p_lines[0], strlen(p_lines[0]) + 1);
                }

                size_t suffix_len = line_suffix ? strlen(line_suffix) : 0;
                size_t last_part_len = strlen(p_lines[num_lines - 1]);
                size_t len_last = last_part_len + suffix_len;
                char *last_line = (char *)malloc(len_last + 1);
                if (last_line) {
                    memcpy(last_line, p_lines[num_lines - 1], last_part_len);
                    if (line_suffix) memcpy(last_line + last_part_len, line_suffix, suffix_len + 1);
                    else last_line[last_part_len] = '\0';
                }

                free(line);
                if (line_prefix) free(line_prefix);
                free(p_lines[0]);
                free(p_lines[num_lines - 1]);

                ctx->lines[l_idx] = first_line ? first_line : duplicate_string("");

                size_t insert_idx = l_idx + 1;
                size_t extra = num_lines - 1;
                memmove(&ctx->lines[insert_idx + extra], &ctx->lines[insert_idx], (ctx->line_count - insert_idx) * sizeof(char *));

                for (size_t i = 1; i < num_lines - 1; i++) {
                    ctx->lines[l_idx + i] = p_lines[i];
                }
                ctx->lines[l_idx + extra] = last_line ? last_line : duplicate_string("");
                free(p_lines);
                ctx->line_count += extra;

                ctx->cursor.line = (int32_t)(l_idx + num_lines);
                ctx->cursor.byteCol = (int32_t)(last_part_len + 1);
                if (line_suffix) free(line_suffix);
                ctx->is_dirty = true;
                emit_line_delta(ctx, (int32_t)(l_idx + 1), 1, (int32_t)num_lines);
            }
        }
    }
    clamp_cursor(ctx);
}

// MARK: - Key Dispatch Loop
void vim_context_feed_keys(VimContextRef ctx, const char *keys) {
    if (!ctx || !keys) return;
    vim_activate_context(ctx);

    const char *p = keys;
    while (*p) {
        if (ctx->mode == VIM_MODE_NORMAL) {
            // 1. Global escape cancels pending leader, operator, find, replace, count
            if (*p == '\x1b') {
                ctx->pending_leader = 0;
                ctx->pending_operator = 0;
                ctx->pending_find = 0;
                ctx->pending_replace = 0;
                ctx->pending_text_object = 0;
                ctx->count_accumulator = 0;
                p++;
                continue;
            }

            // 2. Pending find / till
            if (ctx->pending_find != 0) {
                bool till = (ctx->pending_find == 't');
                motion_find(ctx, *p, till);
                ctx->pending_find = 0;
                ctx->count_accumulator = 0;
                p++;
                continue;
            }

            // 3. Pending replace (r<char>)
            if (ctx->pending_replace != 0) {
                size_t l_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[l_idx];
                size_t len = strlen(line);
                if (len > 0 && (size_t)ctx->cursor.byteCol <= len) {
                    snapshot_for_undo(ctx);
                    line[ctx->cursor.byteCol - 1] = *p;
                    ctx->is_dirty = true;
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                ctx->pending_replace = 0;
                ctx->count_accumulator = 0;
                p++;
                continue;
            }

            // 4. Pending multi-key leader ('g' or 'Z')
            if (ctx->pending_leader != 0) {
                char leader = ctx->pending_leader;
                ctx->pending_leader = 0;
                if (leader == 'g') {
                    if (*p == 'g') {
                        int target = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                        ctx->cursor.line = target;
                        ctx->cursor.byteCol = 1;
                        ctx->count_accumulator = 0;
                        clamp_cursor(ctx);
                        p++;
                        continue;
                    } else if (*p == 'e') {
                        int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                        motion_ge(ctx, count);
                        ctx->count_accumulator = 0;
                        p++;
                        continue;
                    }
                    // Any other key cancelled 'g' leader, fall through to process *p normally
                } else if (leader == 'Z') {
                    if (*p == 'Z') {
                        if (ctx->is_dirty) {
                            ctx->pending_action = VIM_ACTION_SAVE_AND_QUIT;
                        } else {
                            ctx->pending_action = VIM_ACTION_QUIT;
                        }
                        ctx->should_quit = true;
                        p++;
                        continue;
                    } else if (*p == 'Q') {
                        ctx->pending_action = VIM_ACTION_QUIT_FORCE;
                        ctx->should_quit = true;
                        p++;
                        continue;
                    }
                    // Other key cancelled 'Z' leader
                }
            }

            // 5. Pending operator ('d', 'y', 'c')
            if (ctx->pending_operator != 0) {
                if (ctx->pending_text_object == 'i') {
                    char op = ctx->pending_operator;
                    char delim = *p;
                    ctx->pending_operator = 0;
                    ctx->pending_text_object = 0;
                    ctx->count_accumulator = 0;
                    handle_operator_inner_text_object(ctx, op, delim);
                    p++;
                    continue;
                }
                if (*p == 'i') {
                    ctx->pending_text_object = 'i';
                    p++;
                    continue;
                }
                char op = ctx->pending_operator;
                ctx->pending_operator = 0;
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                ctx->count_accumulator = 0;

                if (op == 'd') {
                    if (*p == 'd') { // dd: delete line(s)
                        snapshot_for_undo(ctx);
                        size_t start_idx = (size_t)(ctx->cursor.line - 1);
                        size_t del_count = (size_t)count;
                        if (start_idx + del_count > ctx->line_count) {
                            del_count = ctx->line_count - start_idx;
                        }

                        // Yank deleted lines
                        yank_linewise_range(ctx, (int32_t)(start_idx + 1), (int32_t)(start_idx + del_count));

                        for (size_t i = 0; i < del_count; i++) {
                            free(ctx->lines[start_idx + i]);
                        }
                        memmove(&ctx->lines[start_idx], &ctx->lines[start_idx + del_count], (ctx->line_count - (start_idx + del_count)) * sizeof(char *));
                        ctx->line_count -= del_count;

                        if (ctx->line_count == 0) {
                            ctx->lines[0] = duplicate_string("");
                            ctx->line_count = 1;
                            emit_line_delta(ctx, (int32_t)(start_idx + 1), (int32_t)del_count, 1);
                        } else {
                            emit_line_delta(ctx, (int32_t)(start_idx + 1), (int32_t)del_count, 0);
                        }
                        ctx->is_dirty = true;
                        clamp_cursor(ctx);
                        p++;
                        continue;
                    } else if (*p == 'w') { // dw: delete word
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);

                        // Find end of word motion
                        VimBytePos orig = ctx->cursor;
                        motion_w(ctx, count);
                        size_t end = (ctx->cursor.line == orig.line) ? (size_t)(ctx->cursor.byteCol - 1) : len;
                        ctx->cursor = orig;

                        if (end > start) {
                            snapshot_for_undo(ctx);
                            char *yanked = (char *)malloc(end - start + 1);
                            if (yanked) {
                                memcpy(yanked, line + start, end - start);
                                yanked[end - start] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                            memmove(line + start, line + end, len - end + 1);
                            ctx->is_dirty = true;
                            clamp_cursor(ctx);
                            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        }
                        p++;
                        continue;
                    } else if (*p == '$') { // d$: delete to end of line
                        snapshot_for_undo(ctx);
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);
                        set_yank_buffer(ctx, line + start, false);
                        line[start] = '\0';
                        ctx->is_dirty = true;
                        clamp_cursor(ctx);
                        emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        p++;
                        continue;
                    } else if (*p == '0') { // d0: delete to start of line
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t end = (size_t)(ctx->cursor.byteCol - 1);
                        if (end > 0) {
                            snapshot_for_undo(ctx);
                            char *yanked = (char *)malloc(end + 1);
                            if (yanked) {
                                memcpy(yanked, line, end);
                                yanked[end] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                            memmove(line, line + end, len - end + 1);
                            ctx->cursor.byteCol = 1;
                            ctx->is_dirty = true;
                            clamp_cursor(ctx);
                            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        }
                        p++;
                        continue;
                    }
                } else if (op == 'y') {
                    if (*p == 'y') { // yy: yank line(s)
                        int32_t end_line = ctx->cursor.line + count - 1;
                        if ((size_t)end_line > ctx->line_count) {
                            end_line = (int32_t)ctx->line_count;
                        }
                        yank_linewise_range(ctx, ctx->cursor.line, end_line);
                        p++;
                        continue;
                    } else if (*p == 'w') { // yw: yank word
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        const char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);

                        VimBytePos orig = ctx->cursor;
                        motion_w(ctx, count);
                        size_t end = (ctx->cursor.line == orig.line) ? (size_t)(ctx->cursor.byteCol - 1) : len;
                        ctx->cursor = orig;

                        if (end > start) {
                            char *yanked = (char *)malloc(end - start + 1);
                            if (yanked) {
                                memcpy(yanked, line + start, end - start);
                                yanked[end - start] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                        }
                        p++;
                        continue;
                    } else if (*p == '$') { // y$: yank to end of line
                        const char *line = ctx->lines[ctx->cursor.line - 1];
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);
                        set_yank_buffer(ctx, line + start, false);
                        p++;
                        continue;
                    } else if (*p == '0') { // y0: yank to start of line
                        const char *line = ctx->lines[ctx->cursor.line - 1];
                        size_t end = (size_t)(ctx->cursor.byteCol - 1);
                        if (end > 0) {
                            char *yanked = (char *)malloc(end + 1);
                            if (yanked) {
                                memcpy(yanked, line, end);
                                yanked[end] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                        }
                        p++;
                        continue;
                    }
                } else if (op == 'c') {
                    if (*p == 'c') { // cc: change line
                        snapshot_for_undo(ctx);
                        ctx->in_insert_undo_group = true;
                        yank_linewise_range(ctx, ctx->cursor.line, ctx->cursor.line);
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        free(ctx->lines[l_idx]);
                        ctx->lines[l_idx] = duplicate_string("");
                        ctx->cursor.byteCol = 1;
                        ctx->mode = VIM_MODE_INSERT;
                        ctx->is_dirty = true;
                        emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        p++;
                        continue;
                    } else if (*p == 'w') { // cw: change word
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);

                        VimBytePos orig = ctx->cursor;
                        motion_e(ctx, count);
                        size_t end = (ctx->cursor.line == orig.line) ? (size_t)ctx->cursor.byteCol : len;
                        ctx->cursor = orig;

                        if (end > start) {
                            snapshot_for_undo(ctx);
                            ctx->in_insert_undo_group = true;
                            char *yanked = (char *)malloc(end - start + 1);
                            if (yanked) {
                                memcpy(yanked, line + start, end - start);
                                yanked[end - start] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                            memmove(line + start, line + end, len - end + 1);
                            ctx->mode = VIM_MODE_INSERT;
                            ctx->is_dirty = true;
                            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        }
                        p++;
                        continue;
                    } else if (*p == '$') { // c$: change to end of line
                        snapshot_for_undo(ctx);
                        ctx->in_insert_undo_group = true;
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t start = (size_t)(ctx->cursor.byteCol - 1);
                        set_yank_buffer(ctx, line + start, false);
                        line[start] = '\0';
                        ctx->mode = VIM_MODE_INSERT;
                        ctx->is_dirty = true;
                        clamp_cursor(ctx);
                        emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        p++;
                        continue;
                    } else if (*p == '0') { // c0: change to start of line
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t end = (size_t)(ctx->cursor.byteCol - 1);
                        if (end > 0) {
                            snapshot_for_undo(ctx);
                            ctx->in_insert_undo_group = true;
                            char *yanked = (char *)malloc(end + 1);
                            if (yanked) {
                                memcpy(yanked, line, end);
                                yanked[end] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                            memmove(line, line + end, len - end + 1);
                            ctx->cursor.byteCol = 1;
                            ctx->mode = VIM_MODE_INSERT;
                            ctx->is_dirty = true;
                            clamp_cursor(ctx);
                            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        }
                        p++;
                        continue;
                    }
                }
            }

            // 6. Number count accumulator (1-9 or 0 if count > 0)
            if ((*p >= '1' && *p <= '9') || (ctx->count_accumulator > 0 && *p == '0')) {
                ctx->count_accumulator = ctx->count_accumulator * 10 + (*p - '0');
                p++;
                continue;
            }

            // Resolve effective count for standard motions
            int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;

            // 7. Standard Normal Mode Keystrokes
            if (*p == 'i') {
                ctx->mode = VIM_MODE_INSERT;
                ctx->in_insert_undo_group = false;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'I') {
                ctx->cursor.byteCol = 1;
                ctx->mode = VIM_MODE_INSERT;
                ctx->in_insert_undo_group = false;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'a') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                if (line_len > 0) {
                    ctx->cursor.byteCol++;
                }
                ctx->mode = VIM_MODE_INSERT;
                ctx->in_insert_undo_group = false;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'A') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                ctx->cursor.byteCol = (int32_t)line_len + 1;
                ctx->mode = VIM_MODE_INSERT;
                ctx->in_insert_undo_group = false;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'o') {
                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) { p++; continue; }
                char *new_line = duplicate_string("");
                if (!new_line) { p++; continue; }
                snapshot_for_undo(ctx);
                ctx->in_insert_undo_group = true;
                int32_t orig_line = ctx->cursor.line;
                size_t insert_idx = (size_t)ctx->cursor.line;
                memmove(&ctx->lines[insert_idx + 1], &ctx->lines[insert_idx], (ctx->line_count - insert_idx) * sizeof(char *));
                ctx->lines[insert_idx] = new_line;
                ctx->line_count++;
                ctx->cursor.line++;
                ctx->cursor.byteCol = 1;
                ctx->is_dirty = true;
                ctx->mode = VIM_MODE_INSERT;
                ctx->count_accumulator = 0;
                emit_line_delta(ctx, orig_line, 1, 2);
                p++;
            } else if (*p == 'O') {
                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) { p++; continue; }
                char *new_line = duplicate_string("");
                if (!new_line) { p++; continue; }
                snapshot_for_undo(ctx);
                ctx->in_insert_undo_group = true;
                int32_t orig_line = ctx->cursor.line;
                size_t insert_idx = (size_t)(ctx->cursor.line - 1);
                memmove(&ctx->lines[insert_idx + 1], &ctx->lines[insert_idx], (ctx->line_count - insert_idx) * sizeof(char *));
                ctx->lines[insert_idx] = new_line;
                ctx->line_count++;
                ctx->cursor.byteCol = 1;
                ctx->is_dirty = true;
                ctx->mode = VIM_MODE_INSERT;
                ctx->count_accumulator = 0;
                emit_line_delta(ctx, orig_line, 1, 2);
                p++;
            } else if (*p == 'v') {
                ctx->mode = VIM_MODE_VISUAL;
                ctx->visual_anchor = ctx->cursor;
                ctx->visual_is_linewise = false;
                ctx->pending_text_object = 0;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'V') {
                ctx->mode = VIM_MODE_VISUAL;
                ctx->visual_anchor = ctx->cursor;
                ctx->visual_is_linewise = true;
                ctx->pending_text_object = 0;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == ':') {
                ctx->mode = VIM_MODE_COMMAND;
                ctx->is_search_cmd = false;
                ctx->cmd_buf[0] = ':';
                ctx->cmd_buf[1] = '\0';
                ctx->cmd_len = 1;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == '/') {
                ctx->mode = VIM_MODE_COMMAND;
                ctx->is_search_cmd = true;
                ctx->cmd_buf[0] = '/';
                ctx->cmd_buf[1] = '\0';
                ctx->cmd_len = 1;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'n') {
                if (ctx->last_search[0] == '\0') {
                    snprintf(ctx->last_error, sizeof(ctx->last_error), "E35: No previous regular expression");
                } else {
                    if (vim_search_forward(ctx, ctx->last_search, true)) {
                        ctx->last_error[0] = '\0';
                    } else {
                        snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", ctx->last_search);
                    }
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'N') {
                if (ctx->last_search[0] == '\0') {
                    snprintf(ctx->last_error, sizeof(ctx->last_error), "E35: No previous regular expression");
                } else {
                    if (vim_search_backward(ctx, ctx->last_search)) {
                        ctx->last_error[0] = '\0';
                    } else {
                        snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", ctx->last_search);
                    }
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'h') {
                if (ctx->cursor.byteCol > count) ctx->cursor.byteCol -= count;
                else ctx->cursor.byteCol = 1;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'l') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                ctx->cursor.byteCol += count;
                if ((size_t)ctx->cursor.byteCol > line_len) {
                    ctx->cursor.byteCol = line_len > 0 ? (int32_t)line_len : 1;
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'j') {
                ctx->cursor.line += count;
                clamp_cursor(ctx);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'k') {
                ctx->cursor.line -= count;
                clamp_cursor(ctx);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == '0') {
                ctx->cursor.byteCol = 1;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == '^') {
                motion_caret(ctx);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == '$') {
                motion_dollar(ctx);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'w') {
                motion_w(ctx, count);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'b') {
                motion_b(ctx, count);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'e') {
                motion_e(ctx, count);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'f' || *p == 't') {
                ctx->pending_find = *p;
                p++;
            } else if (*p == 'r') {
                ctx->pending_replace = 'r';
                p++;
            } else if (*p == 'g') {
                ctx->pending_leader = 'g';
                p++;
            } else if (*p == 'G') {
                int target = (ctx->count_accumulator > 0) ? ctx->count_accumulator : (int)ctx->line_count;
                motion_G(ctx, target);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'd') {
                ctx->pending_operator = 'd';
                p++;
            } else if (*p == 'y') {
                ctx->pending_operator = 'y';
                p++;
            } else if (*p == 'c') {
                ctx->pending_operator = 'c';
                p++;
            } else if (*p == 'p') {
                if (ctx->last_search[0] != '\0' && (ctx->yank_buffer == NULL || ctx->yank_buffer[0] == '\0')) {
                    if (vim_search_backward(ctx, ctx->last_search)) {
                        ctx->last_error[0] = '\0';
                    } else {
                        snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", ctx->last_search);
                    }
                } else {
                    paste_text(ctx, true);
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'P') {
                paste_text(ctx, false);
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'x') {
                size_t l_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[l_idx];
                size_t line_len = strlen(line);
                if (line_len > 0 && (size_t)ctx->cursor.byteCol <= line_len) {
                    snapshot_for_undo(ctx);
                    size_t pos = (size_t)(ctx->cursor.byteCol - 1);
                    char yanked[2] = { line[pos], '\0' };
                    set_yank_buffer(ctx, yanked, false);
                    memmove(&line[pos], &line[pos + 1], line_len - pos);
                    ctx->is_dirty = true;
                    clamp_cursor(ctx);
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 's') { // substitute char (delete char and enter insert)
                size_t l_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[l_idx];
                size_t line_len = strlen(line);
                if (line_len > 0 && (size_t)ctx->cursor.byteCol <= line_len) {
                    snapshot_for_undo(ctx);
                    ctx->in_insert_undo_group = true;
                    size_t pos = (size_t)(ctx->cursor.byteCol - 1);
                    char yanked[2] = { line[pos], '\0' };
                    set_yank_buffer(ctx, yanked, false);
                    memmove(&line[pos], &line[pos + 1], line_len - pos);
                    ctx->is_dirty = true;
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                } else {
                    ctx->in_insert_undo_group = false;
                }
                ctx->mode = VIM_MODE_INSERT;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'J') { // join lines
                if ((size_t)ctx->cursor.line < ctx->line_count) {
                    snapshot_for_undo(ctx);
                    size_t idx1 = (size_t)(ctx->cursor.line - 1);
                    size_t idx2 = idx1 + 1;
                    char *line1 = ctx->lines[idx1];
                    char *line2 = ctx->lines[idx2];
                    size_t len1 = strlen(line1);

                    // Skip leading whitespace of line2
                    size_t lead2 = 0;
                    while (line2[lead2] == ' ' || line2[lead2] == '\t') lead2++;
                    size_t len2 = strlen(line2 + lead2);

                    bool need_space = (len1 > 0 && line1[len1 - 1] != ' ');
                    size_t new_len = len1 + (need_space ? 1 : 0) + len2;

                    char *joined = (char *)malloc(new_len + 1);
                    if (joined) {
                        memcpy(joined, line1, len1);
                        if (need_space) joined[len1] = ' ';
                        memcpy(joined + len1 + (need_space ? 1 : 0), line2 + lead2, len2);
                        joined[new_len] = '\0';

                        free(line1);
                        free(line2);
                        ctx->lines[idx1] = joined;
                        memmove(&ctx->lines[idx2], &ctx->lines[idx2 + 1], (ctx->line_count - (idx2 + 1)) * sizeof(char *));
                        ctx->line_count--;

                        ctx->cursor.byteCol = len1 > 0 ? (int32_t)(len1 + (need_space ? 1 : 0)) : 1;
                        ctx->is_dirty = true;
                        clamp_cursor(ctx);
                        emit_line_delta(ctx, ctx->cursor.line, 2, 1);
                    }
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'u') {
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                for (int i = 0; i < count; i++) {
                    vim_context_undo(ctx);
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == '\x12') { // Ctrl+R (redo)
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                for (int i = 0; i < count; i++) {
                    vim_context_redo(ctx);
                }
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'Z') {
                ctx->pending_leader = 'Z';
                p++;
            } else {
                ctx->count_accumulator = 0;
                p++;
            }
        } else if (ctx->mode == VIM_MODE_INSERT) {
            if (*p == '\x1b') {
                ctx->mode = VIM_MODE_NORMAL;
                ctx->in_insert_undo_group = false;
                if (ctx->cursor.byteCol > 1) {
                    ctx->cursor.byteCol--;
                }
                p++;
            } else if (*p == '\x7f' || *p == '\x08') {
                if (!ctx->in_insert_undo_group) {
                    snapshot_for_undo(ctx);
                    ctx->in_insert_undo_group = true;
                }
                size_t line_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[line_idx];
                size_t line_len = strlen(line);
                if (ctx->cursor.byteCol > 1 && line_len > 0) {
                    size_t char_pos = (size_t)(ctx->cursor.byteCol - 2);
                    memmove(&line[char_pos], &line[char_pos + 1], line_len - char_pos);
                    ctx->cursor.byteCol--;
                    ctx->is_dirty = true;
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                p++;
            } else if (*p == '\n' || *p == '\r') {
                if (!ctx->in_insert_undo_group) {
                    snapshot_for_undo(ctx);
                    ctx->in_insert_undo_group = true;
                }
                size_t line_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[line_idx];
                size_t line_len = strlen(line);
                size_t split_pos = (size_t)(ctx->cursor.byteCol - 1);
                if (split_pos > line_len) split_pos = line_len;

                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) {
                    p++;
                    continue;
                }

                char *new_line = duplicate_string(&line[split_pos]);
                if (!new_line) {
                    p++;
                    continue;
                }
                line[split_pos] = '\0';

                memmove(&ctx->lines[line_idx + 2], &ctx->lines[line_idx + 1], (ctx->line_count - (line_idx + 1)) * sizeof(char *));
                ctx->lines[line_idx + 1] = new_line;
                ctx->line_count++;

                ctx->cursor.line++;
                ctx->cursor.byteCol = 1;
                ctx->is_dirty = true;
                emit_line_delta(ctx, ctx->cursor.line - 1, 1, 2);
                p++;
            } else {
                if (!ctx->in_insert_undo_group) {
                    snapshot_for_undo(ctx);
                    ctx->in_insert_undo_group = true;
                }
                size_t line_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[line_idx];
                size_t line_len = strlen(line);
                size_t insert_pos = (size_t)(ctx->cursor.byteCol - 1);
                if (insert_pos > line_len) insert_pos = line_len;

                char *new_line = (char *)malloc(line_len + 2);
                if (new_line) {
                    memcpy(new_line, line, insert_pos);
                    new_line[insert_pos] = *p;
                    memcpy(&new_line[insert_pos + 1], &line[insert_pos], line_len - insert_pos + 1);
                    free(line);
                    ctx->lines[line_idx] = new_line;
                    ctx->cursor.byteCol++;
                    ctx->is_dirty = true;
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                p++;
            }
        } else if (ctx->mode == VIM_MODE_VISUAL) {
            if (*p == '\x1b') {
                ctx->mode = VIM_MODE_NORMAL;
                ctx->pending_text_object = 0;
                ctx->count_accumulator = 0;
                p++;
            } else if (ctx->pending_text_object == 'i') {
                handle_visual_text_object(ctx, *p);
                ctx->pending_text_object = 0;
                ctx->count_accumulator = 0;
                p++;
            } else if (*p == 'i') {
                ctx->pending_text_object = 'i';
                p++;
            } else if ((*p >= '1' && *p <= '9') || (ctx->count_accumulator > 0 && *p == '0')) {
                ctx->count_accumulator = ctx->count_accumulator * 10 + (*p - '0');
                p++;
                continue;
            } else if (*p == 'd' || *p == 'c') { // Visual delete or change
                ctx->count_accumulator = 0;
                bool is_change = (*p == 'c');
                if (ctx->visual_is_linewise) {
                    snapshot_for_undo(ctx);
                    int32_t start_l = ctx->visual_anchor.line < ctx->cursor.line ? ctx->visual_anchor.line : ctx->cursor.line;
                    int32_t end_l = ctx->visual_anchor.line > ctx->cursor.line ? ctx->visual_anchor.line : ctx->cursor.line;
                    size_t start_idx = (size_t)(start_l - 1);
                    size_t del_count = (size_t)(end_l - start_l + 1);

                    yank_linewise_range(ctx, start_l, end_l);
                    for (size_t i = 0; i < del_count; i++) free(ctx->lines[start_idx + i]);
                    memmove(&ctx->lines[start_idx], &ctx->lines[start_idx + del_count], (ctx->line_count - (start_idx + del_count)) * sizeof(char *));
                    ctx->line_count -= del_count;

                    if (ctx->line_count == 0) {
                        ctx->lines[0] = duplicate_string("");
                        ctx->line_count = 1;
                        emit_line_delta(ctx, start_l, (int32_t)del_count, 1);
                    } else {
                        emit_line_delta(ctx, start_l, (int32_t)del_count, 0);
                    }
                    ctx->cursor.line = start_l;
                    ctx->cursor.byteCol = 1;
                } else {
                    if (ctx->visual_anchor.line == ctx->cursor.line) {
                        size_t l_idx = (size_t)(ctx->cursor.line - 1);
                        char *line = ctx->lines[l_idx];
                        size_t len = strlen(line);
                        size_t col1 = (size_t)ctx->visual_anchor.byteCol;
                        size_t col2 = (size_t)ctx->cursor.byteCol;
                        size_t start = (col1 < col2 ? col1 : col2) - 1;
                        size_t end = (col1 > col2 ? col1 : col2);
                        if (end > len) end = len;

                        if (end > start) {
                            snapshot_for_undo(ctx);
                            char *yanked = (char *)malloc(end - start + 1);
                            if (yanked) {
                                memcpy(yanked, line + start, end - start);
                                yanked[end - start] = '\0';
                                set_yank_buffer(ctx, yanked, false);
                                free(yanked);
                            }
                            memmove(line + start, line + end, len - end + 1);
                            ctx->cursor.byteCol = (int32_t)(start + 1);
                            emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                        }
                    }
                }
                ctx->is_dirty = true;
                ctx->in_insert_undo_group = is_change;
                ctx->mode = is_change ? VIM_MODE_INSERT : VIM_MODE_NORMAL;
                clamp_cursor(ctx);
                p++;
            } else if (*p == 'y') { // Visual yank
                ctx->count_accumulator = 0;
                if (ctx->visual_is_linewise) {
                    int32_t start_l = ctx->visual_anchor.line < ctx->cursor.line ? ctx->visual_anchor.line : ctx->cursor.line;
                    int32_t end_l = ctx->visual_anchor.line > ctx->cursor.line ? ctx->visual_anchor.line : ctx->cursor.line;
                    yank_linewise_range(ctx, start_l, end_l);
                } else if (ctx->visual_anchor.line == ctx->cursor.line) {
                    const char *line = ctx->lines[ctx->cursor.line - 1];
                    size_t col1 = (size_t)ctx->visual_anchor.byteCol;
                    size_t col2 = (size_t)ctx->cursor.byteCol;
                    size_t start = (col1 < col2 ? col1 : col2) - 1;
                    size_t end = (col1 > col2 ? col1 : col2);
                    size_t len = strlen(line);
                    if (end > len) end = len;
                    if (end > start) {
                        char *yanked = (char *)malloc(end - start + 1);
                        if (yanked) {
                            memcpy(yanked, line + start, end - start);
                            yanked[end - start] = '\0';
                            set_yank_buffer(ctx, yanked, false);
                            free(yanked);
                        }
                    }
                }
                ctx->mode = VIM_MODE_NORMAL;
                p++;
            } else if (*p == 'h') {
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                ctx->count_accumulator = 0;
                ctx->cursor.byteCol = (ctx->cursor.byteCol > count) ? (ctx->cursor.byteCol - count) : 1;
                p++;
            } else if (*p == 'l') {
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                ctx->count_accumulator = 0;
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                ctx->cursor.byteCol += count;
                if ((size_t)ctx->cursor.byteCol > line_len) {
                    ctx->cursor.byteCol = (int32_t)line_len;
                }
                if (ctx->cursor.byteCol < 1) ctx->cursor.byteCol = 1;
                p++;
            } else if (*p == 'j') {
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                ctx->count_accumulator = 0;
                ctx->cursor.line += count;
                if ((size_t)ctx->cursor.line > ctx->line_count) {
                    ctx->cursor.line = (int32_t)ctx->line_count;
                }
                clamp_cursor(ctx);
                p++;
            } else if (*p == 'k') {
                int count = (ctx->count_accumulator > 0) ? ctx->count_accumulator : 1;
                ctx->count_accumulator = 0;
                ctx->cursor.line = (ctx->cursor.line > count) ? (ctx->cursor.line - count) : 1;
                clamp_cursor(ctx);
                p++;
            } else if (*p == '0') {
                ctx->count_accumulator = 0;
                ctx->cursor.byteCol = 1;
                p++;
            } else if (*p == '$') {
                ctx->count_accumulator = 0;
                motion_dollar(ctx);
                p++;
            } else {
                ctx->count_accumulator = 0;
                p++;
            }
        } else if (ctx->mode == VIM_MODE_COMMAND) {
            if (*p == '\r' || *p == '\n') {
                ctx->cmd_buf[ctx->cmd_len] = '\0';
                if (ctx->cmd_buf[0] == '/') {
                    const char *pattern = ctx->cmd_buf + 1;
                    if (strlen(pattern) > 0) {
                        strncpy(ctx->last_search, pattern, sizeof(ctx->last_search) - 1);
                        ctx->last_search[sizeof(ctx->last_search) - 1] = '\0';
                    }
                    if (ctx->last_search[0] == '\0') {
                        snprintf(ctx->last_error, sizeof(ctx->last_error), "E35: No previous regular expression");
                    } else {
                        if (vim_search_forward(ctx, ctx->last_search, false)) {
                            ctx->last_error[0] = '\0';
                        } else {
                            snprintf(ctx->last_error, sizeof(ctx->last_error), "Pattern not found: %s", ctx->last_search);
                        }
                    }
                } else {
                    vim_context_execute_ex(ctx, ctx->cmd_buf);
                }
                ctx->mode = VIM_MODE_NORMAL;
                ctx->is_search_cmd = false;
                ctx->cmd_len = 0;
                ctx->cmd_buf[0] = '\0';
                p++;
            } else if (*p == '\x1b') {
                ctx->mode = VIM_MODE_NORMAL;
                ctx->is_search_cmd = false;
                ctx->cmd_len = 0;
                ctx->cmd_buf[0] = '\0';
                p++;
            } else if (*p == '\x7f' || *p == '\x08') {
                if (ctx->cmd_len > 0) {
                    ctx->cmd_len--;
                    ctx->cmd_buf[ctx->cmd_len] = '\0';
                    if (ctx->cmd_len == 0) {
                        ctx->mode = VIM_MODE_NORMAL;
                        ctx->is_search_cmd = false;
                    }
                } else {
                    ctx->mode = VIM_MODE_NORMAL;
                    ctx->is_search_cmd = false;
                }
                p++;
            } else {
                if (ctx->cmd_len + 1 < sizeof(ctx->cmd_buf)) {
                    ctx->cmd_buf[ctx->cmd_len++] = *p;
                    ctx->cmd_buf[ctx->cmd_len] = '\0';
                }
                p++;
            }
        } else {
            p++;
        }
    }

    clamp_cursor(ctx);
}

static char* replace_substring(const char *str, const char *find, const char *replace, bool global) {
    if (!str || !find || !replace) return NULL;
    size_t find_len = strlen(find);
    if (find_len == 0) return duplicate_string(str);

    size_t replace_len = strlen(replace);
    const char *match = strstr(str, find);
    if (!match) return duplicate_string(str);

    size_t count = 0;
    const char *tmp = str;
    while ((match = strstr(tmp, find)) != NULL) {
        count++;
        tmp = match + find_len;
        if (!global) break;
    }

    size_t new_len = strlen(str) + count * (replace_len - find_len);
    char *result = (char *)malloc(new_len + 1);
    if (!result) return NULL;

    char *dst = result;
    tmp = str;
    while ((match = strstr(tmp, find)) != NULL) {
        size_t seg = match - tmp;
        memcpy(dst, tmp, seg);
        dst += seg;
        memcpy(dst, replace, replace_len);
        dst += replace_len;
        tmp = match + find_len;
        if (!global) break;
    }
    strcpy(dst, tmp);
    return result;
}

void vim_context_execute_ex(VimContextRef ctx, const char *command) {
    if (!ctx || !command) return;
    vim_activate_context(ctx);

    const char *cmd = command;
    while (*cmd == ' ' || *cmd == ':') cmd++;

    if (strcmp(cmd, "w") == 0) {
        ctx->pending_action = VIM_ACTION_SAVE;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "w!") == 0) {
        ctx->pending_action = VIM_ACTION_SAVE_FORCE;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "wa") == 0 || strcmp(cmd, "wall") == 0) {
        ctx->pending_action = VIM_ACTION_SAVE_ALL;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "q") == 0) {
        if (ctx->is_dirty) {
            snprintf(ctx->last_error, sizeof(ctx->last_error), "E37: No write since last change (add ! to override)");
            ctx->pending_action = VIM_ACTION_NONE;
        } else {
            ctx->pending_action = VIM_ACTION_QUIT;
            ctx->should_quit = true;
            ctx->last_error[0] = '\0';
        }
    } else if (strcmp(cmd, "q!") == 0) {
        ctx->pending_action = VIM_ACTION_QUIT_FORCE;
        ctx->should_quit = true;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "qa") == 0 || strcmp(cmd, "qall") == 0) {
        bool any_dirty = false;
        for (size_t i = 0; i < g_context_count; i++) {
            if (g_contexts[i] && g_contexts[i]->is_dirty) {
                any_dirty = true;
                break;
            }
        }
        if (any_dirty) {
            snprintf(ctx->last_error, sizeof(ctx->last_error), "E37: No write since last change (add ! to override)");
            ctx->pending_action = VIM_ACTION_NONE;
        } else {
            ctx->pending_action = VIM_ACTION_QUIT_ALL;
            ctx->should_quit = true;
            ctx->last_error[0] = '\0';
        }
    } else if (strcmp(cmd, "qa!") == 0 || strcmp(cmd, "qall!") == 0) {
        ctx->pending_action = VIM_ACTION_QUIT_ALL_FORCE;
        ctx->should_quit = true;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "wq") == 0 || strcmp(cmd, "wq!") == 0) {
        ctx->pending_action = VIM_ACTION_SAVE_AND_QUIT;
        ctx->should_quit = true;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "x") == 0 || strcmp(cmd, "xit") == 0) {
        if (ctx->is_dirty) {
            ctx->pending_action = VIM_ACTION_SAVE_AND_QUIT;
        } else {
            ctx->pending_action = VIM_ACTION_QUIT;
        }
        ctx->should_quit = true;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "ZZ") == 0) {
        if (ctx->is_dirty) {
            ctx->pending_action = VIM_ACTION_SAVE_AND_QUIT;
        } else {
            ctx->pending_action = VIM_ACTION_QUIT;
        }
        ctx->should_quit = true;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "e!") == 0 || strcmp(cmd, "edit!") == 0) {
        ctx->pending_action = VIM_ACTION_RELOAD_FORCE;
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "u") == 0 || strcmp(cmd, "undo") == 0) {
        vim_context_undo(ctx);
        ctx->last_error[0] = '\0';
    } else if (strcmp(cmd, "red") == 0 || strcmp(cmd, "redo") == 0) {
        vim_context_redo(ctx);
        ctx->last_error[0] = '\0';
    } else if (strncmp(cmd, "%s/", 3) == 0 || strncmp(cmd, "s/", 2) == 0) {
        bool is_global_lines = (cmd[0] == '%');
        const char *p = is_global_lines ? cmd + 3 : cmd + 2;

        const char *slash2 = strchr(p, '/');
        if (slash2) {
            size_t find_len = slash2 - p;
            char *find_buf = (char *)malloc(find_len + 1);
            if (!find_buf) return;
            memcpy(find_buf, p, find_len);
            find_buf[find_len] = '\0';

            const char *slash3 = strchr(slash2 + 1, '/');
            char *replace_buf = NULL;
            bool replace_all_in_line = false;

            if (slash3) {
                size_t rep_len = slash3 - (slash2 + 1);
                replace_buf = (char *)malloc(rep_len + 1);
                if (!replace_buf) {
                    free(find_buf);
                    return;
                }
                memcpy(replace_buf, slash2 + 1, rep_len);
                replace_buf[rep_len] = '\0';
                if (strchr(slash3 + 1, 'g')) {
                    replace_all_in_line = true;
                }
            } else {
                replace_buf = duplicate_string(slash2 + 1);
                if (!replace_buf) {
                    free(find_buf);
                    return;
                }
            }

            size_t start_line = is_global_lines ? 1 : (size_t)ctx->cursor.line;
            size_t end_line = is_global_lines ? ctx->line_count : (size_t)ctx->cursor.line;
            bool did_snapshot = false;

            for (size_t l = start_line; l <= end_line && l <= ctx->line_count; l++) {
                char *new_line = replace_substring(ctx->lines[l - 1], find_buf, replace_buf, replace_all_in_line);
                if (new_line) {
                    if (strcmp(new_line, ctx->lines[l - 1]) != 0) {
                        if (!did_snapshot) {
                            snapshot_for_undo(ctx);
                            did_snapshot = true;
                        }
                        free(ctx->lines[l - 1]);
                        ctx->lines[l - 1] = new_line;
                        ctx->is_dirty = true;
                        emit_line_delta(ctx, (int32_t)l, 1, 1);
                    } else {
                        free(new_line);
                    }
                }
            }

            free(find_buf);
            free(replace_buf);
        }
    }
}

char* vim_context_serialize_buffer(VimContextRef ctx, size_t *outLength) {
    if (!ctx || ctx->line_count == 0) {
        if (outLength) *outLength = 0;
        return NULL;
    }

    size_t total_len = 0;
    for (size_t i = 0; i < ctx->line_count; i++) {
        total_len += strlen(ctx->lines[i]);
        if (i < ctx->line_count - 1) {
            total_len += 1; // '\n'
        }
    }

    char *buf = (char *)malloc(total_len + 1);
    if (!buf) {
        if (outLength) *outLength = 0;
        return NULL;
    }

    char *dst = buf;
    for (size_t i = 0; i < ctx->line_count; i++) {
        size_t len = strlen(ctx->lines[i]);
        memcpy(dst, ctx->lines[i], len);
        dst += len;
        if (i < ctx->line_count - 1) {
            *dst++ = '\n';
        }
    }
    *dst = '\0';

    if (outLength) {
        *outLength = total_len;
    }
    return buf;
}

bool vim_context_can_undo(VimContextRef ctx) {
    if (!ctx) return false;
    return ctx->undo_head != NULL;
}

bool vim_context_can_redo(VimContextRef ctx) {
    if (!ctx) return false;
    return ctx->redo_head != NULL;
}

bool vim_context_undo(VimContextRef ctx) {
    if (!ctx || !ctx->undo_head) return false;

    // Snapshot current state into redo stack
    VimUndoNode *redo_node = create_undo_node(ctx);
    if (redo_node) {
        push_redo_node(ctx, redo_node);
    }

    // Pop top node from undo stack
    VimUndoNode *node = ctx->undo_head;
    ctx->undo_head = node->next;
    if (ctx->undo_head) {
        ctx->undo_head->prev = NULL;
    } else {
        ctx->undo_tail = NULL;
    }
    ctx->undo_count--;

    // Restore state
    size_t old_line_count = ctx->line_count;
    free_lines(ctx->lines, ctx->line_count);

    ctx->lines = node->lines;
    ctx->line_count = node->line_count;
    ctx->line_capacity = node->line_count;
    ctx->cursor = node->cursor;
    ctx->is_dirty = node->is_dirty;

    node->lines = NULL;
    free(node);

    clamp_cursor(ctx);
    ctx->in_insert_undo_group = false;

    // Dispatch delta
    emit_line_delta(ctx, 1, (int32_t)old_line_count, (int32_t)ctx->line_count);
    return true;
}

bool vim_context_redo(VimContextRef ctx) {
    if (!ctx || !ctx->redo_head) return false;

    // Snapshot current state into undo stack
    VimUndoNode *undo_node = create_undo_node(ctx);
    if (undo_node) {
        push_undo_node(ctx, undo_node);
    }

    // Pop top node from redo stack
    VimUndoNode *node = ctx->redo_head;
    ctx->redo_head = node->next;
    if (ctx->redo_head) {
        ctx->redo_head->prev = NULL;
    } else {
        ctx->redo_tail = NULL;
    }
    ctx->redo_count--;

    // Restore state
    size_t old_line_count = ctx->line_count;
    free_lines(ctx->lines, ctx->line_count);

    ctx->lines = node->lines;
    ctx->line_count = node->line_count;
    ctx->line_capacity = node->line_count;
    ctx->cursor = node->cursor;
    ctx->is_dirty = node->is_dirty;

    node->lines = NULL;
    free(node);

    clamp_cursor(ctx);
    ctx->in_insert_undo_group = false;

    // Dispatch delta
    emit_line_delta(ctx, 1, (int32_t)old_line_count, (int32_t)ctx->line_count);
    return true;
}

