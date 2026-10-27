#include "libvim_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>

static int g_tests_run = 0;
static int g_tests_passed = 0;

#define RUN_TEST(name) \
    do { \
        printf("[RUN ] %s\n", #name); \
        g_tests_run++; \
        name(); \
        g_tests_passed++; \
        printf("[PASS] %s\n", #name); \
    } while (0)

static void test_engine_init(void) {
    // Engine init must be idempotent and safe across multiple invocations
    vim_engine_init();
    vim_engine_init();
    // After init, context creation should succeed
    VimContextRef ctx = vim_context_create("init_test");
    assert(ctx != NULL);
    vim_context_destroy(ctx);
}

static void test_context_lifecycle(void) {
    const char *initial_text = "# Hello VimMD\nTesting context creation.";
    VimContextRef ctx = vim_context_create(initial_text);
    assert(ctx != NULL);

    VimEngineMode mode = vim_context_get_mode(ctx);
    assert(mode == VIM_MODE_NORMAL);

    VimBytePos cursor = vim_context_get_cursor(ctx);
    assert(cursor.line == 1);
    assert(cursor.byteCol == 1);

    assert(vim_context_is_dirty(ctx) == false);

    size_t out_len = 0;
    char *serialized = vim_context_serialize_buffer(ctx, &out_len);
    assert(serialized != NULL);
    assert(out_len == strlen(initial_text));
    assert(strcmp(serialized, initial_text) == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

static void test_context_empty_string(void) {
    VimContextRef ctx = vim_context_create("");
    assert(ctx != NULL);

    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    VimBytePos cursor = vim_context_get_cursor(ctx);
    assert(cursor.line == 1 && cursor.byteCol == 1);
    assert(vim_context_is_dirty(ctx) == false);

    size_t out_len = 999;
    char *serialized = vim_context_serialize_buffer(ctx, &out_len);
    assert(serialized != NULL);
    assert(out_len == 0);
    assert(strcmp(serialized, "") == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

static void test_context_clear_dirty(void) {
    VimContextRef ctx = vim_context_create("some text");
    assert(ctx != NULL);
    assert(vim_context_is_dirty(ctx) == false);

    // Explicitly clear dirty on a valid context
    vim_context_clear_dirty(ctx);
    assert(vim_context_is_dirty(ctx) == false);

    vim_context_destroy(ctx);
}

static void test_serialize_null_outlength(void) {
    const char *text = "Testing serialize with NULL outLength";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // outLength passed as NULL should not crash and return valid string
    char *serialized = vim_context_serialize_buffer(ctx, NULL);
    assert(serialized != NULL);
    assert(strcmp(serialized, text) == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

static void test_multibyte_utf8(void) {
    const char *multibyte_text = "# Header 🚀\n日本語と한국어\nCafé au lait — accents: é, è, ü, î\nEmoji: 🌍🎉";
    VimContextRef ctx = vim_context_create(multibyte_text);
    assert(ctx != NULL);

    size_t out_len = 0;
    char *serialized = vim_context_serialize_buffer(ctx, &out_len);
    assert(serialized != NULL);
    assert(out_len == strlen(multibyte_text));
    assert(strcmp(serialized, multibyte_text) == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

typedef struct {
    int32_t start_line;
    int32_t deleted_count;
    int32_t added_count;
    int call_count;
    char first_added_line[64];
} MockDeltaState;

static void mock_delta_callback(
    int32_t startLine,
    int32_t deletedCount,
    const char **newLines,
    int32_t addedCount,
    void *userInfo
) {
    MockDeltaState *state = (MockDeltaState *)userInfo;
    if (!state) return;
    state->call_count++;
    state->start_line = startLine;
    state->deleted_count = deletedCount;
    state->added_count = addedCount;
    if (newLines && addedCount > 0 && newLines[0]) {
        strncpy(state->first_added_line, newLines[0], sizeof(state->first_added_line) - 1);
        state->first_added_line[sizeof(state->first_added_line) - 1] = '\0';
    }
}

static void test_delta_callback(void) {
    VimContextRef ctx = vim_context_create("Line 1\nLine 2\nLine 3");
    assert(ctx != NULL);

    MockDeltaState state = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &state);

    const char *new_lines[] = { "Replacement Line 2", "Additional Line 2.5" };
    vim_context_dispatch_delta(ctx, 2, 1, new_lines, 2);

    assert(state.call_count == 1);
    assert(state.start_line == 2);
    assert(state.deleted_count == 1);
    assert(state.added_count == 2);
    assert(strcmp(state.first_added_line, "Replacement Line 2") == 0);

    // Unregister callback
    vim_context_set_delta_callback(ctx, NULL, NULL);
    vim_context_dispatch_delta(ctx, 1, 0, NULL, 0);
    assert(state.call_count == 1); // Not called again

    vim_context_destroy(ctx);
}

static void test_multi_instance_isolation(void) {
    const char *doc1_text = "Document One Content";
    const char *doc2_text = "Document Two Content with different length";

    VimContextRef ctx1 = vim_context_create(doc1_text);
    VimContextRef ctx2 = vim_context_create(doc2_text);

    assert(ctx1 != NULL);
    assert(ctx2 != NULL);
    assert(ctx1 != ctx2);

    // Contexts must return their respective independent buffers
    size_t len1 = 0, len2 = 0;
    char *ser1 = vim_context_serialize_buffer(ctx1, &len1);
    char *ser2 = vim_context_serialize_buffer(ctx2, &len2);

    assert(ser1 != NULL);
    assert(ser2 != NULL);
    assert(len1 == strlen(doc1_text));
    assert(len2 == strlen(doc2_text));
    assert(strcmp(ser1, doc1_text) == 0);
    assert(strcmp(ser2, doc2_text) == 0);

    free(ser1);
    free(ser2);

    vim_context_destroy(ctx1);

    // ctx2 must still remain valid after ctx1 is destroyed
    char *ser2_after = vim_context_serialize_buffer(ctx2, &len2);
    assert(ser2_after != NULL);
    assert(strcmp(ser2_after, doc2_text) == 0);
    free(ser2_after);

    vim_context_destroy(ctx2);
}

static void test_null_handling(void) {
    // NULL input should create an empty valid context
    VimContextRef ctx = vim_context_create(NULL);
    assert(ctx != NULL);
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(vim_context_is_dirty(ctx) == false);
    vim_context_destroy(ctx);

    // NULL context operations must be safe no-ops
    vim_context_destroy(NULL);
    vim_context_feed_keys(NULL, "iHello");
    vim_context_execute_ex(NULL, ":w");
    assert(vim_context_get_mode(NULL) == VIM_MODE_NORMAL);
    VimBytePos pos = vim_context_get_cursor(NULL);
    assert(pos.line == 1 && pos.byteCol == 1);
    assert(vim_context_is_dirty(NULL) == false);
    vim_context_clear_dirty(NULL);
    assert(vim_context_serialize_buffer(NULL, NULL) == NULL);
    vim_context_dispatch_delta(NULL, 1, 0, NULL, 0);
}

int main(void) {
    printf("=== CBridge Unit Tests ===\n");
    RUN_TEST(test_engine_init);
    RUN_TEST(test_context_lifecycle);
    RUN_TEST(test_context_empty_string);
    RUN_TEST(test_context_clear_dirty);
    RUN_TEST(test_serialize_null_outlength);
    RUN_TEST(test_multibyte_utf8);
    RUN_TEST(test_delta_callback);
    RUN_TEST(test_multi_instance_isolation);
    RUN_TEST(test_null_handling);
    printf("Result: %d/%d tests passed.\n", g_tests_passed, g_tests_run);
    return (g_tests_passed == g_tests_run) ? 0 : 1;
}
