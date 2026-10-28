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

typedef enum {
    VIM_ACTION_NONE = 0,
    VIM_ACTION_SAVE,           // :w
    VIM_ACTION_SAVE_FORCE,     // :w!
    VIM_ACTION_SAVE_ALL,       // :wa, :wall
    VIM_ACTION_QUIT,           // :q (must refuse if dirty!)
    VIM_ACTION_QUIT_FORCE,     // :q!, ZQ
    VIM_ACTION_SAVE_AND_QUIT,  // :wq, :wq!, :x, :xit, ZZ
    VIM_ACTION_QUIT_ALL,       // :qa, :qall
    VIM_ACTION_QUIT_ALL_FORCE, // :qa!, :qall!
    VIM_ACTION_RELOAD_FORCE    // :e!, :edit!
} VimSystemAction;

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

// Yank & Cut Callback & Clipboard Buffer
typedef void (*VimYankCallback)(const char *text, bool linewise, void *userInfo);
void vim_context_set_yank_callback(VimContextRef ctx, VimYankCallback cb, void *userInfo);
const char* vim_context_get_yank_buffer(VimContextRef ctx, bool *out_linewise);
void vim_context_set_yank_buffer(VimContextRef ctx, const char *text, bool linewise);

// Lifecycle & Context Switching
void vim_engine_init(void);
VimContextRef vim_context_create(const char *initial_utf8);
void vim_context_destroy(VimContextRef ctx);
void vim_activate_context(VimContextRef ctx);

// Input & Ex Engine
void vim_context_feed_keys(VimContextRef ctx, const char *keys);
void vim_context_execute_ex(VimContextRef ctx, const char *command);

// State Queries
VimEngineMode vim_context_get_mode(VimContextRef ctx);
VimBytePos vim_context_get_cursor(VimContextRef ctx);
void vim_context_set_cursor(VimContextRef ctx, int32_t line, int32_t byteCol);
VimBytePos vim_context_get_visual_anchor(VimContextRef ctx);
void vim_context_set_visual_anchor(VimContextRef ctx, int32_t line, int32_t byteCol);
bool vim_context_is_visual_linewise(VimContextRef ctx);
bool vim_context_is_dirty(VimContextRef ctx);
void vim_context_clear_dirty(VimContextRef ctx);
bool vim_context_should_quit(VimContextRef ctx);

// Search State
const char* vim_context_get_last_search(VimContextRef ctx);
void vim_context_set_last_search(VimContextRef ctx, const char *pattern);

// System Actions & Error State
VimSystemAction vim_context_get_pending_action(VimContextRef ctx);
void vim_context_clear_pending_action(VimContextRef ctx);
const char* vim_context_get_last_error(VimContextRef ctx);

// Delta mutation callback registration & dispatch
void vim_context_set_delta_callback(VimContextRef ctx, VimLineDeltaCallback cb, void *userInfo);
void vim_context_dispatch_delta(VimContextRef ctx, int32_t startLine, int32_t deletedCount, const char **newLines, int32_t addedCount);

// Full serialization (Save operations only)
char* vim_context_serialize_buffer(VimContextRef ctx, size_t *outLength);

#ifdef __cplusplus
}
#endif

#endif /* LIBVIM_BRIDGE_H */
