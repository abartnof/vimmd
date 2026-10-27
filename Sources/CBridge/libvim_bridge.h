#ifndef LIBVIM_BRIDGE_H
#define LIBVIM_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VimDocumentContext* VimContextRef;

typedef enum {
    VIM_MODE_NORMAL = 0,
    VIM_MODE_INSERT,
    VIM_MODE_VISUAL,
    VIM_MODE_COMMAND
} VimEngineMode;

typedef struct {
    int32_t line;    // 1-based line number
    int32_t byteCol; // 1-based UTF-8 byte offset
} VimBytePos;

// Granular Delta Callback (Avoids full-buffer extraction on :%s)
typedef void (*VimLineDeltaCallback)(
    int32_t startLine,
    int32_t deletedCount,
    const char **newLines,
    int32_t addedCount,
    void *userInfo
);

// Lifecycle
void vim_engine_init(void);
VimContextRef vim_context_create(const char *initial_utf8);
void vim_context_destroy(VimContextRef ctx);

// Input & Ex Engine
void vim_context_feed_keys(VimContextRef ctx, const char *keys);
void vim_context_execute_ex(VimContextRef ctx, const char *command);

// State Queries
VimEngineMode vim_context_get_mode(VimContextRef ctx);
VimBytePos vim_context_get_cursor(VimContextRef ctx);
bool vim_context_is_dirty(VimContextRef ctx);
void vim_context_clear_dirty(VimContextRef ctx);

// Delta mutation callback registration & dispatch
void vim_context_set_delta_callback(VimContextRef ctx, VimLineDeltaCallback cb, void *userInfo);
void vim_context_dispatch_delta(VimContextRef ctx, int32_t startLine, int32_t deletedCount, const char **newLines, int32_t addedCount);

// Full serialization (Save operations only)
char* vim_context_serialize_buffer(VimContextRef ctx, size_t *outLength);

#ifdef __cplusplus
}
#endif

#endif /* LIBVIM_BRIDGE_H */
