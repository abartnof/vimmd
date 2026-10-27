#include "libvim_bridge.h"
#include <stdlib.h>
#include <string.h>

struct VimDocumentContext {
    char *buffer_content;
    size_t buffer_length;
    VimEngineMode mode;
    VimBytePos cursor;
    bool is_dirty;
    VimLineDeltaCallback delta_cb;
    void *user_info;
};

static bool g_engine_initialized = false;

void vim_engine_init(void) {
    if (g_engine_initialized) {
        return;
    }
    // Perform one-time global Vim engine initialization
    g_engine_initialized = true;
}

VimContextRef vim_context_create(const char *initial_utf8) {
    struct VimDocumentContext *ctx = (struct VimDocumentContext *)calloc(1, sizeof(struct VimDocumentContext));
    if (!ctx) {
        return NULL;
    }

    if (initial_utf8 != NULL) {
        ctx->buffer_length = strlen(initial_utf8);
        ctx->buffer_content = (char *)malloc(ctx->buffer_length + 1);
        if (!ctx->buffer_content) {
            free(ctx);
            return NULL;
        }
        memcpy(ctx->buffer_content, initial_utf8, ctx->buffer_length + 1);
    } else {
        ctx->buffer_content = (char *)calloc(1, 1);
        if (!ctx->buffer_content) {
            free(ctx);
            return NULL;
        }
        ctx->buffer_length = 0;
    }

    ctx->mode = VIM_MODE_NORMAL;
    ctx->cursor.line = 1;
    ctx->cursor.byteCol = 1;
    ctx->is_dirty = false;
    ctx->delta_cb = NULL;
    ctx->user_info = NULL;

    return ctx;
}

void vim_context_destroy(VimContextRef ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->buffer_content) {
        free(ctx->buffer_content);
        ctx->buffer_content = NULL;
    }
    free(ctx);
}

void vim_context_feed_keys(VimContextRef ctx, const char *keys) {
    if (!ctx || !keys) {
        return;
    }
    // Stub for input processing
}

void vim_context_execute_ex(VimContextRef ctx, const char *command) {
    if (!ctx || !command) {
        return;
    }
    // Stub for ex command processing
}

VimEngineMode vim_context_get_mode(VimContextRef ctx) {
    if (!ctx) {
        return VIM_MODE_NORMAL;
    }
    return ctx->mode;
}

VimBytePos vim_context_get_cursor(VimContextRef ctx) {
    if (!ctx) {
        VimBytePos default_pos = { .line = 1, .byteCol = 1 };
        return default_pos;
    }
    return ctx->cursor;
}

bool vim_context_is_dirty(VimContextRef ctx) {
    if (!ctx) {
        return false;
    }
    return ctx->is_dirty;
}

void vim_context_clear_dirty(VimContextRef ctx) {
    if (!ctx) {
        return;
    }
    ctx->is_dirty = false;
}

void vim_context_set_delta_callback(VimContextRef ctx, VimLineDeltaCallback cb, void *userInfo) {
    if (!ctx) {
        return;
    }
    ctx->delta_cb = cb;
    ctx->user_info = userInfo;
}

void vim_context_dispatch_delta(VimContextRef ctx, int32_t startLine, int32_t deletedCount, const char **newLines, int32_t addedCount) {
    if (!ctx || !ctx->delta_cb) {
        return;
    }
    ctx->delta_cb(startLine, deletedCount, newLines, addedCount, ctx->user_info);
}

char* vim_context_serialize_buffer(VimContextRef ctx, size_t *outLength) {
    if (!ctx || !ctx->buffer_content) {
        if (outLength) {
            *outLength = 0;
        }
        return NULL;
    }

    char *copy = (char *)malloc(ctx->buffer_length + 1);
    if (!copy) {
        if (outLength) {
            *outLength = 0;
        }
        return NULL;
    }

    memcpy(copy, ctx->buffer_content, ctx->buffer_length + 1);
    if (outLength) {
        *outLength = ctx->buffer_length;
    }
    return copy;
}
