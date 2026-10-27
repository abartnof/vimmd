#include "libvim_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

struct VimDocumentContext {
    char **lines;
    size_t line_count;
    size_t line_capacity;
    VimEngineMode mode;
    VimBytePos cursor;
    bool is_dirty;
    bool should_quit;
    VimLineDeltaCallback delta_cb;
    void *user_info;

    // Upstream context state simulation
    void *buf_ptr;
    void *win_ptr;
    int mode_state;
};

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
    ctx->is_dirty = false;
    ctx->should_quit = false;

    if (!initial_utf8 || strlen(initial_utf8) == 0) {
        if (!ensure_line_capacity(ctx, 1)) {
            free(ctx);
            return NULL;
        }
        ctx->lines[0] = duplicate_string("");
        ctx->line_count = 1;
    } else {
        // Split by \n, stripping any \r
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

        // Final line after last \n
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

    vim_activate_context(ctx);
    return ctx;
}

void vim_context_destroy(VimContextRef ctx) {
    if (!ctx) return;
    if (g_active_ctx == ctx) {
        g_active_ctx = NULL;
    }
    free_lines(ctx->lines, ctx->line_count);
    free(ctx);
}

VimEngineMode vim_context_get_mode(VimContextRef ctx) {
    if (!ctx) return VIM_MODE_NORMAL;
    return ctx->mode;
}

VimBytePos vim_context_get_cursor(VimContextRef ctx) {
    if (!ctx) {
        VimBytePos def = { .line = 1, .byteCol = 1 };
        return def;
    }
    return ctx->cursor;
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

void vim_context_feed_keys(VimContextRef ctx, const char *keys) {
    if (!ctx || !keys) return;
    vim_activate_context(ctx);

    const char *p = keys;
    while (*p) {
        if (ctx->mode == VIM_MODE_NORMAL) {
            if (*p == 'i') {
                ctx->mode = VIM_MODE_INSERT;
                p++;
            } else if (*p == 'I') {
                ctx->cursor.byteCol = 1;
                ctx->mode = VIM_MODE_INSERT;
                p++;
            } else if (*p == 'a') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                if (line_len > 0) {
                    ctx->cursor.byteCol++;
                }
                ctx->mode = VIM_MODE_INSERT;
                p++;
            } else if (*p == 'A') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                ctx->cursor.byteCol = (int32_t)line_len + 1;
                ctx->mode = VIM_MODE_INSERT;
                p++;
            } else if (*p == 'o') {
                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) {
                    p++;
                    continue;
                }
                char *new_line = duplicate_string("");
                if (!new_line) {
                    p++;
                    continue;
                }
                size_t insert_idx = (size_t)ctx->cursor.line;
                memmove(&ctx->lines[insert_idx + 1], &ctx->lines[insert_idx], (ctx->line_count - insert_idx) * sizeof(char *));
                ctx->lines[insert_idx] = new_line;
                ctx->line_count++;
                ctx->cursor.line++;
                ctx->cursor.byteCol = 1;
                ctx->is_dirty = true;
                ctx->mode = VIM_MODE_INSERT;
                emit_line_delta(ctx, ctx->cursor.line, 0, 1);
                p++;
            } else if (*p == 'O') {
                if (!ensure_line_capacity(ctx, ctx->line_count + 1)) {
                    p++;
                    continue;
                }
                char *new_line = duplicate_string("");
                if (!new_line) {
                    p++;
                    continue;
                }
                size_t insert_idx = (size_t)(ctx->cursor.line - 1);
                memmove(&ctx->lines[insert_idx + 1], &ctx->lines[insert_idx], (ctx->line_count - insert_idx) * sizeof(char *));
                ctx->lines[insert_idx] = new_line;
                ctx->line_count++;
                ctx->cursor.byteCol = 1;
                ctx->is_dirty = true;
                ctx->mode = VIM_MODE_INSERT;
                emit_line_delta(ctx, ctx->cursor.line, 0, 1);
                p++;
            } else if (*p == 'v' || *p == 'V') {
                ctx->mode = VIM_MODE_VISUAL;
                p++;
            } else if (*p == ':') {
                ctx->mode = VIM_MODE_COMMAND;
                p++;
            } else if (*p == 'h') {
                if (ctx->cursor.byteCol > 1) ctx->cursor.byteCol--;
                p++;
            } else if (*p == 'l') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                if ((size_t)ctx->cursor.byteCol < line_len) ctx->cursor.byteCol++;
                p++;
            } else if (*p == 'j') {
                if ((size_t)ctx->cursor.line < ctx->line_count) {
                    ctx->cursor.line++;
                    clamp_cursor(ctx);
                }
                p++;
            } else if (*p == 'k') {
                if (ctx->cursor.line > 1) {
                    ctx->cursor.line--;
                    clamp_cursor(ctx);
                }
                p++;
            } else if (*p == '0') {
                ctx->cursor.byteCol = 1;
                p++;
            } else if (*p == '$') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                ctx->cursor.byteCol = line_len > 0 ? (int32_t)line_len : 1;
                p++;
            } else if (*p == 'G') {
                ctx->cursor.line = (int32_t)ctx->line_count;
                clamp_cursor(ctx);
                p++;
            } else if (*p == 'g') {
                if (*(p + 1) == 'g') {
                    ctx->cursor.line = 1;
                    ctx->cursor.byteCol = 1;
                    p += 2;
                } else {
                    p++;
                }
            } else if (*p == 'x') {
                size_t line_idx = (size_t)(ctx->cursor.line - 1);
                char *line = ctx->lines[line_idx];
                size_t line_len = strlen(line);
                if (line_len > 0 && (size_t)ctx->cursor.byteCol <= line_len) {
                    size_t char_pos = (size_t)(ctx->cursor.byteCol - 1);
                    memmove(&line[char_pos], &line[char_pos + 1], line_len - char_pos);
                    ctx->is_dirty = true;
                    clamp_cursor(ctx);
                    emit_line_delta(ctx, ctx->cursor.line, 1, 1);
                }
                p++;
            } else if (*p == 'Z') {
                if (*(p + 1) == 'Z') {
                    ctx->is_dirty = false;
                    ctx->should_quit = true;
                    p += 2;
                } else if (*(p + 1) == 'Q') {
                    ctx->should_quit = true;
                    p += 2;
                } else {
                    p++;
                }
            } else {
                p++;
            }
        } else if (ctx->mode == VIM_MODE_INSERT) {
            if (*p == '\x1b') {
                ctx->mode = VIM_MODE_NORMAL;
                if (ctx->cursor.byteCol > 1) {
                    ctx->cursor.byteCol--;
                }
                p++;
            } else if (*p == '\x7f' || *p == '\x08') {
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
                // Insert character
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
                p++;
            } else if (*p == 'h') {
                if (ctx->cursor.byteCol > 1) ctx->cursor.byteCol--;
                p++;
            } else if (*p == 'l') {
                size_t line_len = strlen(ctx->lines[ctx->cursor.line - 1]);
                if ((size_t)ctx->cursor.byteCol < line_len) ctx->cursor.byteCol++;
                p++;
            } else if (*p == 'j') {
                if ((size_t)ctx->cursor.line < ctx->line_count) {
                    ctx->cursor.line++;
                    clamp_cursor(ctx);
                }
                p++;
            } else if (*p == 'k') {
                if (ctx->cursor.line > 1) {
                    ctx->cursor.line--;
                    clamp_cursor(ctx);
                }
                p++;
            } else {
                p++;
            }
        } else if (ctx->mode == VIM_MODE_COMMAND) {
            if (*p == '\x1b') {
                ctx->mode = VIM_MODE_NORMAL;
                p++;
            } else {
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
        ctx->is_dirty = false;
    } else if (strcmp(cmd, "q") == 0 || strcmp(cmd, "q!") == 0) {
        ctx->should_quit = true;
    } else if (strcmp(cmd, "wq") == 0) {
        ctx->is_dirty = false;
        ctx->should_quit = true;
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

            for (size_t l = start_line; l <= end_line && l <= ctx->line_count; l++) {
                char *new_line = replace_substring(ctx->lines[l - 1], find_buf, replace_buf, replace_all_in_line);
                if (new_line) {
                    if (strcmp(new_line, ctx->lines[l - 1]) != 0) {
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
