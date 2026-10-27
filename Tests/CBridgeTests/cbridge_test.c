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

static void test_modal_transitions(void) {
    VimContextRef ctx = vim_context_create("Initial content");
    assert(ctx != NULL);
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // Normal -> Insert via 'i'
    vim_context_feed_keys(ctx, "i");
    assert(vim_context_get_mode(ctx) == VIM_MODE_INSERT);

    // Insert -> Normal via Esc
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // Normal -> Insert via 'a'
    vim_context_feed_keys(ctx, "a");
    assert(vim_context_get_mode(ctx) == VIM_MODE_INSERT);
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // Normal -> Visual via 'v'
    vim_context_feed_keys(ctx, "v");
    assert(vim_context_get_mode(ctx) == VIM_MODE_VISUAL);

    // Visual -> Normal via Esc
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // Normal -> Command via ':'
    vim_context_feed_keys(ctx, ":");
    assert(vim_context_get_mode(ctx) == VIM_MODE_COMMAND);
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    vim_context_destroy(ctx);
}

static void test_cursor_navigation(void) {
    const char *text = "Line 1 Hello\nLine 2 World\nLine 3";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // Right 'l'
    vim_context_feed_keys(ctx, "l");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 2);

    vim_context_feed_keys(ctx, "l");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 3);

    // Left 'h'
    vim_context_feed_keys(ctx, "h");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 2);

    // Down 'j'
    vim_context_feed_keys(ctx, "j");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 2 && pos.byteCol == 2);

    // Up 'k'
    vim_context_feed_keys(ctx, "k");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 2);

    // Start of line '0'
    vim_context_feed_keys(ctx, "0");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // End of line '$'
    vim_context_feed_keys(ctx, "$");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 12);

    // Last line 'G'
    vim_context_feed_keys(ctx, "G");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 3);

    // First line 'gg'
    vim_context_feed_keys(ctx, "gg");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    vim_context_destroy(ctx);
}

static void test_insert_mode_mutations(void) {
    VimContextRef ctx = vim_context_create("Hello");
    assert(ctx != NULL);

    // Enter insert mode and insert "World" at cursor col 1
    vim_context_feed_keys(ctx, "iWorld\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(vim_context_is_dirty(ctx) == true);

    size_t len = 0;
    char *serialized = vim_context_serialize_buffer(ctx, &len);
    assert(serialized != NULL);
    assert(strcmp(serialized, "WorldHello") == 0);
    free(serialized);

    // Append at end of line: 'A' enters insert at end
    vim_context_feed_keys(ctx, "A!\x1b");
    serialized = vim_context_serialize_buffer(ctx, &len);
    assert(strcmp(serialized, "WorldHello!") == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

static void test_ex_substitution(void) {
    const char *text = "foo and foo\nfoo bar";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    MockDeltaState delta_state = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &delta_state);

    // Substitute first line: :s/foo/baz/
    vim_context_execute_ex(ctx, ":s/foo/baz/");
    assert(vim_context_is_dirty(ctx) == true);
    assert(delta_state.call_count >= 1);

    size_t len = 0;
    char *serialized = vim_context_serialize_buffer(ctx, &len);
    assert(strncmp(serialized, "baz and foo\n", 12) == 0);
    free(serialized);

    // Global substitute: :%s/foo/qux/g
    vim_context_execute_ex(ctx, ":%s/foo/qux/g");
    serialized = vim_context_serialize_buffer(ctx, &len);
    assert(strcmp(serialized, "baz and qux\nqux bar") == 0);
    free(serialized);

    // :w sets pending action VIM_ACTION_SAVE (host clears dirty upon save)
    vim_context_execute_ex(ctx, ":w");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE);
    vim_context_clear_dirty(ctx);
    assert(vim_context_is_dirty(ctx) == false);

    // :q sets quit flag when clean
    assert(vim_context_should_quit(ctx) == false);
    vim_context_execute_ex(ctx, ":q");
    assert(vim_context_should_quit(ctx) == true);
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_QUIT);

    vim_context_destroy(ctx);
}

static void test_multi_window_context_isolation(void) {
    VimContextRef ctxA = vim_context_create("Window A Content");
    VimContextRef ctxB = vim_context_create("Window B Content");

    assert(ctxA != NULL && ctxB != NULL);

    // Mutate ctxA
    vim_context_feed_keys(ctxA, "i123\x1b");
    assert(vim_context_is_dirty(ctxA) == true);
    assert(vim_context_is_dirty(ctxB) == false);

    // Move cursor and change mode in ctxB
    vim_context_feed_keys(ctxB, "l");
    vim_context_feed_keys(ctxB, "v");
    assert(vim_context_get_mode(ctxB) == VIM_MODE_VISUAL);
    assert(vim_context_get_mode(ctxA) == VIM_MODE_NORMAL);

    // Activate ctxA explicitly
    vim_activate_context(ctxA);
    assert(vim_context_get_mode(ctxA) == VIM_MODE_NORMAL);

    // Verify independent serialized contents
    size_t lenA = 0, lenB = 0;
    char *serA = vim_context_serialize_buffer(ctxA, &lenA);
    char *serB = vim_context_serialize_buffer(ctxB, &lenB);

    assert(strcmp(serA, "123Window A Content") == 0);
    assert(strcmp(serB, "Window B Content") == 0);

    free(serA);
    free(serB);

    vim_context_destroy(ctxA);
    vim_context_destroy(ctxB);
}

static void test_quit_commands(void) {
    // 1. Test :wq: sets should_quit and VIM_ACTION_SAVE_AND_QUIT
    VimContextRef ctx1 = vim_context_create("Testing :wq");
    vim_context_feed_keys(ctx1, "iEdited\x1b");
    assert(vim_context_is_dirty(ctx1) == true);
    assert(vim_context_should_quit(ctx1) == false);
    vim_context_execute_ex(ctx1, ":wq");
    assert(vim_context_should_quit(ctx1) == true);
    assert(vim_context_get_pending_action(ctx1) == VIM_ACTION_SAVE_AND_QUIT);
    vim_context_destroy(ctx1);

    // 2. Test ZZ: sets should_quit and VIM_ACTION_SAVE_AND_QUIT
    VimContextRef ctx2 = vim_context_create("Testing ZZ");
    vim_context_feed_keys(ctx2, "iEdited\x1b");
    assert(vim_context_is_dirty(ctx2) == true);
    assert(vim_context_should_quit(ctx2) == false);
    vim_context_feed_keys(ctx2, "ZZ");
    assert(vim_context_should_quit(ctx2) == true);
    assert(vim_context_get_pending_action(ctx2) == VIM_ACTION_SAVE_AND_QUIT);
    vim_context_destroy(ctx2);

    // 3. Test ZQ: quits WITHOUT clearing dirty flag
    VimContextRef ctx3 = vim_context_create("Testing ZQ");
    vim_context_feed_keys(ctx3, "iEdited\x1b");
    assert(vim_context_is_dirty(ctx3) == true);
    assert(vim_context_should_quit(ctx3) == false);
    vim_context_feed_keys(ctx3, "ZQ");
    assert(vim_context_should_quit(ctx3) == true);
    assert(vim_context_get_pending_action(ctx3) == VIM_ACTION_QUIT_FORCE);
    assert(vim_context_is_dirty(ctx3) == true); // Must preserve dirty!
    vim_context_destroy(ctx3);
}

static void test_open_line_deltas(void) {
    VimContextRef ctx = vim_context_create("Line 1\nLine 2");
    assert(ctx != NULL);

    MockDeltaState delta_state = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &delta_state);

    // 'o' opens line below line 1: delta should replace line 1 (count 1) with 2 lines (Line 1, "")
    vim_context_feed_keys(ctx, "o\x1b");
    assert(delta_state.call_count >= 1);
    assert(delta_state.start_line == 1);
    assert(delta_state.deleted_count == 1);
    assert(delta_state.added_count == 2);

    size_t len = 0;
    char *serialized = vim_context_serialize_buffer(ctx, &len);
    assert(strcmp(serialized, "Line 1\n\nLine 2") == 0);
    free(serialized);

    // 'O' opens line above: cursor is on line 2, 'O' replaces line 2 (count 1) with 2 lines ("", Line 2)
    vim_context_feed_keys(ctx, "O\x1b");
    assert(delta_state.start_line == 2);
    assert(delta_state.deleted_count == 1);
    assert(delta_state.added_count == 2);

    serialized = vim_context_serialize_buffer(ctx, &len);
    assert(strcmp(serialized, "Line 1\n\n\nLine 2") == 0);
    free(serialized);

    vim_context_destroy(ctx);
}

static void test_system_actions(void) {
    // 1. :w does NOT clear dirty, sets VIM_ACTION_SAVE
    VimContextRef ctx = vim_context_create("Initial");
    vim_context_feed_keys(ctx, "iMutated\x1b");
    assert(vim_context_is_dirty(ctx) == true);
    vim_context_execute_ex(ctx, "w");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE);
    assert(vim_context_is_dirty(ctx) == true); // Must NOT clear dirty on :w!
    vim_context_clear_pending_action(ctx);
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_NONE);

    // 2. :w! sets VIM_ACTION_SAVE_FORCE
    vim_context_execute_ex(ctx, "w!");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE_FORCE);
    vim_context_clear_pending_action(ctx);

    // 3. :wa / :wall sets VIM_ACTION_SAVE_ALL
    vim_context_execute_ex(ctx, "wa");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE_ALL);
    vim_context_clear_pending_action(ctx);
    vim_context_execute_ex(ctx, "wall");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE_ALL);
    vim_context_clear_pending_action(ctx);

    // 4. :q on dirty context: must REFUSE quit, set last_error to E37
    vim_context_execute_ex(ctx, "q");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_NONE);
    assert(vim_context_should_quit(ctx) == false);
    assert(strstr(vim_context_get_last_error(ctx), "E37") != NULL);

    // 5. :q! on dirty context: forces quit
    vim_context_execute_ex(ctx, "q!");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_QUIT_FORCE);
    assert(vim_context_should_quit(ctx) == true);
    vim_context_destroy(ctx);

    // 6. :q on clean context: succeeds with VIM_ACTION_QUIT
    VimContextRef ctxClean = vim_context_create("Clean document");
    assert(vim_context_is_dirty(ctxClean) == false);
    vim_context_execute_ex(ctxClean, "q");
    assert(vim_context_get_pending_action(ctxClean) == VIM_ACTION_QUIT);
    assert(vim_context_should_quit(ctxClean) == true);
    vim_context_destroy(ctxClean);

    // 7. :wq and :wq! set VIM_ACTION_SAVE_AND_QUIT
    VimContextRef ctxWq = vim_context_create("WQ Test");
    vim_context_feed_keys(ctxWq, "iMut\x1b");
    vim_context_execute_ex(ctxWq, "wq");
    assert(vim_context_get_pending_action(ctxWq) == VIM_ACTION_SAVE_AND_QUIT);
    assert(vim_context_should_quit(ctxWq) == true);
    vim_context_clear_pending_action(ctxWq);
    vim_context_execute_ex(ctxWq, "wq!");
    assert(vim_context_get_pending_action(ctxWq) == VIM_ACTION_SAVE_AND_QUIT);
    vim_context_destroy(ctxWq);

    // 8. :x and :xit: SAVE_AND_QUIT if dirty, QUIT if clean
    VimContextRef ctxXDirty = vim_context_create("X Test");
    vim_context_feed_keys(ctxXDirty, "iX\x1b");
    vim_context_execute_ex(ctxXDirty, "x");
    assert(vim_context_get_pending_action(ctxXDirty) == VIM_ACTION_SAVE_AND_QUIT);
    assert(vim_context_should_quit(ctxXDirty) == true);
    vim_context_destroy(ctxXDirty);

    VimContextRef ctxXClean = vim_context_create("X Clean");
    vim_context_execute_ex(ctxXClean, "xit");
    assert(vim_context_get_pending_action(ctxXClean) == VIM_ACTION_QUIT);
    assert(vim_context_should_quit(ctxXClean) == true);
    vim_context_destroy(ctxXClean);

    // 9. ZZ and ZQ in normal mode
    VimContextRef ctxZZ = vim_context_create("ZZ Test");
    vim_context_feed_keys(ctxZZ, "iZZ\x1b");
    vim_context_feed_keys(ctxZZ, "ZZ");
    assert(vim_context_get_pending_action(ctxZZ) == VIM_ACTION_SAVE_AND_QUIT);
    assert(vim_context_should_quit(ctxZZ) == true);
    vim_context_destroy(ctxZZ);

    VimContextRef ctxZQ = vim_context_create("ZQ Test");
    vim_context_feed_keys(ctxZQ, "iZQ\x1b");
    vim_context_feed_keys(ctxZQ, "ZQ");
    assert(vim_context_get_pending_action(ctxZQ) == VIM_ACTION_QUIT_FORCE);
    assert(vim_context_should_quit(ctxZQ) == true);
    vim_context_destroy(ctxZQ);

    // 10. :e! and :edit! set VIM_ACTION_RELOAD_FORCE
    VimContextRef ctxE = vim_context_create("Reload Test");
    vim_context_execute_ex(ctxE, "e!");
    assert(vim_context_get_pending_action(ctxE) == VIM_ACTION_RELOAD_FORCE);
    vim_context_clear_pending_action(ctxE);
    vim_context_execute_ex(ctxE, "edit!");
    assert(vim_context_get_pending_action(ctxE) == VIM_ACTION_RELOAD_FORCE);
    vim_context_destroy(ctxE);

    // 11. :qa and :qa!
    VimContextRef ctxQA1 = vim_context_create("Doc 1");
    VimContextRef ctxQA2 = vim_context_create("Doc 2");
    vim_context_feed_keys(ctxQA1, "iDirty\x1b");
    vim_context_execute_ex(ctxQA2, "qa");
    assert(vim_context_get_pending_action(ctxQA2) == VIM_ACTION_NONE);
    assert(strstr(vim_context_get_last_error(ctxQA2), "E37") != NULL);

    vim_context_execute_ex(ctxQA2, "qa!");
    assert(vim_context_get_pending_action(ctxQA2) == VIM_ACTION_QUIT_ALL_FORCE);
    assert(vim_context_should_quit(ctxQA2) == true);

    vim_context_destroy(ctxQA1);
    vim_context_destroy(ctxQA2);

    VimContextRef ctxQAClean = vim_context_create("Doc Clean");
    vim_context_execute_ex(ctxQAClean, "qa");
    assert(vim_context_get_pending_action(ctxQAClean) == VIM_ACTION_QUIT_ALL);
    assert(vim_context_should_quit(ctxQAClean) == true);
    vim_context_destroy(ctxQAClean);
}

static void test_interactive_command_line(void) {
    VimContextRef ctx = vim_context_create("Interactive Command Line Test");
    assert(ctx != NULL);

    // Type ':w' followed by '\r'
    vim_context_feed_keys(ctx, ":");
    assert(vim_context_get_mode(ctx) == VIM_MODE_COMMAND);
    vim_context_feed_keys(ctx, "w\r");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE);
    vim_context_clear_pending_action(ctx);

    // Type ':s/Line/Buffer/g' followed by '\n'
    vim_context_feed_keys(ctx, ":s/Line/Buffer/g\n");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    size_t len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &len);
    assert(strcmp(ser, "Interactive Command Buffer Test") == 0);
    free(ser);

    // Type ':' then Escape to cancel
    vim_context_feed_keys(ctx, ":some_unknown_command");
    assert(vim_context_get_mode(ctx) == VIM_MODE_COMMAND);
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_NONE);

    // Type ':' then backspace past start to cancel
    vim_context_feed_keys(ctx, ":a\x7f\x7f");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    vim_context_destroy(ctx);
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
    RUN_TEST(test_modal_transitions);
    RUN_TEST(test_cursor_navigation);
    RUN_TEST(test_insert_mode_mutations);
    RUN_TEST(test_ex_substitution);
    RUN_TEST(test_multi_window_context_isolation);
    RUN_TEST(test_quit_commands);
    RUN_TEST(test_open_line_deltas);
    RUN_TEST(test_system_actions);
    RUN_TEST(test_interactive_command_line);
    printf("Result: %d/%d tests passed.\n", g_tests_passed, g_tests_run);
    return (g_tests_passed == g_tests_run) ? 0 : 1;
}
