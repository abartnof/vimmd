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

static void test_set_cursor(void) {
    const char *text = "Line 1\nSecond Line\nThird Line";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Set cursor to line 2, byteCol 4
    vim_context_set_cursor(ctx, 2, 4);
    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 2);
    assert(pos.byteCol == 4);

    // Set cursor out of bounds: line 10 -> clamped to 3
    vim_context_set_cursor(ctx, 10, 50);
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 3);
    assert(pos.byteCol <= 11);

    vim_context_destroy(ctx);
}

static void test_gg_motion_streaming(void) {
    const char *text = "Line 1 Header\nLine 2 Middle\nLine 3 Footer";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Place cursor at line 3, col 4
    vim_context_set_cursor(ctx, 3, 4);
    assert(vim_context_get_cursor(ctx).line == 3);

    // Feed first 'g' character-by-character
    vim_context_feed_keys(ctx, "g");
    // Leader is pending, cursor MUST still be at line 3, col 4
    assert(vim_context_get_cursor(ctx).line == 3);
    assert(vim_context_get_cursor(ctx).byteCol == 4);

    // Feed second 'g' character-by-character
    vim_context_feed_keys(ctx, "g");
    // Now 'gg' is complete -> cursor must jump to line 1, col 1
    assert(vim_context_get_cursor(ctx).line == 1);
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    // Test pending leader cancellation with non-'g' key
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "g");
    assert(vim_context_get_cursor(ctx).line == 2);
    // Feed 'j' instead of 'g'
    vim_context_feed_keys(ctx, "j");
    // Leader cancelled and 'j' executed -> moved to line 3
    assert(vim_context_get_cursor(ctx).line == 3);

    vim_context_destroy(ctx);
}

static void test_G_motion(void) {
    const char *text = "Line 1\nLine 2\n   First non blank on line 3";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    assert(vim_context_get_cursor(ctx).line == 1);
    vim_context_feed_keys(ctx, "G");
    // Line 3 has 3 leading spaces; first non-blank char 'F' is at 1-based col 4
    assert(vim_context_get_cursor(ctx).line == 3);
    assert(vim_context_get_cursor(ctx).byteCol == 4);

    // Test G on empty / all-whitespace last line -> col 1
    vim_context_destroy(ctx);
    VimContextRef ctx2 = vim_context_create("Alpha\nBeta\n");
    vim_context_feed_keys(ctx2, "G");
    assert(vim_context_get_cursor(ctx2).line == 3);
    assert(vim_context_get_cursor(ctx2).byteCol == 1);
    vim_context_destroy(ctx2);
}

static void test_visual_text_objects(void) {
    // 1. vi' (single quote)
    const char *text1 = "let greeting = 'hello world';";
    VimContextRef ctx1 = vim_context_create(text1);
    // Cursor on 'w' in 'world' (col 22)
    vim_context_set_cursor(ctx1, 1, 22);
    vim_context_feed_keys(ctx1, "v");
    vim_context_feed_keys(ctx1, "i");
    vim_context_feed_keys(ctx1, "'");
    assert(vim_context_get_mode(ctx1) == VIM_MODE_VISUAL);
    VimBytePos a1 = vim_context_get_visual_anchor(ctx1);
    VimBytePos c1 = vim_context_get_cursor(ctx1);
    // 'hello world' is from col 17 to col 27 (inside quotes at 16 and 28)
    assert(a1.line == 1 && a1.byteCol == 17);
    assert(c1.line == 1 && c1.byteCol == 27);
    vim_context_destroy(ctx1);

    // 2. vi" (double quote)
    const char *text2 = "let msg = \"test double quote\";";
    VimContextRef ctx2 = vim_context_create(text2);
    vim_context_set_cursor(ctx2, 1, 15);
    vim_context_feed_keys(ctx2, "v");
    vim_context_feed_keys(ctx2, "i");
    vim_context_feed_keys(ctx2, "\"");
    assert(vim_context_get_mode(ctx2) == VIM_MODE_VISUAL);
    VimBytePos a2 = vim_context_get_visual_anchor(ctx2);
    VimBytePos c2 = vim_context_get_cursor(ctx2);
    // "test double quote" is from col 12 to 28 (quotes at 11 and 29)
    assert(a2.line == 1 && a2.byteCol == 12);
    assert(c2.line == 1 && c2.byteCol == 28);
    vim_context_destroy(ctx2);

    // 3. vi( / vi) / vib (parentheses)
    const char *text3 = "call(param1, param2);";
    VimContextRef ctx3 = vim_context_create(text3);
    vim_context_set_cursor(ctx3, 1, 8);
    vim_context_feed_keys(ctx3, "v");
    vim_context_feed_keys(ctx3, "i");
    vim_context_feed_keys(ctx3, "(");
    assert(vim_context_get_mode(ctx3) == VIM_MODE_VISUAL);
    VimBytePos a3 = vim_context_get_visual_anchor(ctx3);
    VimBytePos c3 = vim_context_get_cursor(ctx3);
    // '(' at 5, ')' at 20 -> inner is 6 to 19
    assert(a3.line == 1 && a3.byteCol == 6);
    assert(c3.line == 1 && c3.byteCol == 19);

    // Also test vib
    vim_context_feed_keys(ctx3, "\x1b"); // Back to normal
    vim_context_set_cursor(ctx3, 1, 8);
    vim_context_feed_keys(ctx3, "v");
    vim_context_feed_keys(ctx3, "i");
    vim_context_feed_keys(ctx3, "b");
    assert(vim_context_get_mode(ctx3) == VIM_MODE_VISUAL);
    assert(vim_context_get_visual_anchor(ctx3).byteCol == 6);
    assert(vim_context_get_cursor(ctx3).byteCol == 19);
    vim_context_destroy(ctx3);

    // 4. vi[ / vi] (square brackets)
    const char *text4 = "arr = [itemA, itemB];";
    VimContextRef ctx4 = vim_context_create(text4);
    vim_context_set_cursor(ctx4, 1, 10);
    vim_context_feed_keys(ctx4, "v");
    vim_context_feed_keys(ctx4, "i");
    vim_context_feed_keys(ctx4, "[");
    assert(vim_context_get_mode(ctx4) == VIM_MODE_VISUAL);
    // '[' at 7, ']' at 20 -> inner is 8 to 19
    assert(vim_context_get_visual_anchor(ctx4).byteCol == 8);
    assert(vim_context_get_cursor(ctx4).byteCol == 19);
    vim_context_destroy(ctx4);

    // 5. vi< / vi> (angle brackets)
    const char *text5 = "vector<uint32_t> numbers;";
    VimContextRef ctx5 = vim_context_create(text5);
    vim_context_set_cursor(ctx5, 1, 10);
    vim_context_feed_keys(ctx5, "v");
    vim_context_feed_keys(ctx5, "i");
    vim_context_feed_keys(ctx5, "<");
    assert(vim_context_get_mode(ctx5) == VIM_MODE_VISUAL);
    // '<' at 7, '>' at 16 -> inner is 8 to 15
    assert(vim_context_get_visual_anchor(ctx5).byteCol == 8);
    assert(vim_context_get_cursor(ctx5).byteCol == 15);
    vim_context_destroy(ctx5);

    // 6. vi{ / vi} / viB (braces)
    const char *text6 = "void fn() { return 42; }";
    VimContextRef ctx6 = vim_context_create(text6);
    vim_context_set_cursor(ctx6, 1, 15);
    vim_context_feed_keys(ctx6, "v");
    vim_context_feed_keys(ctx6, "i");
    vim_context_feed_keys(ctx6, "{");
    assert(vim_context_get_mode(ctx6) == VIM_MODE_VISUAL);
    // '{' at 11, '}' at 24 -> inner is 12 to 23
    assert(vim_context_get_visual_anchor(ctx6).byteCol == 12);
    assert(vim_context_get_cursor(ctx6).byteCol == 23);

    // Also test viB
    vim_context_feed_keys(ctx6, "\x1b");
    vim_context_set_cursor(ctx6, 1, 15);
    vim_context_feed_keys(ctx6, "v");
    vim_context_feed_keys(ctx6, "i");
    vim_context_feed_keys(ctx6, "B");
    assert(vim_context_get_mode(ctx6) == VIM_MODE_VISUAL);
    assert(vim_context_get_visual_anchor(ctx6).byteCol == 12);
    assert(vim_context_get_cursor(ctx6).byteCol == 23);
    vim_context_destroy(ctx6);
}

static void test_operator_inner_quotes(void) {
    // 1. di'
    {
        const char *text = "const char *s = 'hello world';";
        VimContextRef ctx = vim_context_create(text);
        assert(ctx != NULL);
        vim_context_set_cursor(ctx, 1, 20); // on 'o' in hello
        vim_context_feed_keys(ctx, "di'");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "const char *s = '';") == 0);
        free(ser);
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(yanked != NULL);
        assert(strcmp(yanked, "hello world") == 0);
        assert(linewise == false);
        assert(vim_context_is_dirty(ctx));
        VimBytePos pos = vim_context_get_cursor(ctx);
        assert(pos.line == 1 && pos.byteCol == 18);
        vim_context_destroy(ctx);
    }

    // 2. ci'
    {
        const char *text = "msg = 'foo';";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 8); // on 'f'
        vim_context_feed_keys(ctx, "ci'bar\x1b");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "msg = 'bar';") == 0);
        free(ser);
        assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(strcmp(yanked, "foo") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx);
    }

    // 3. yi'
    {
        const char *text = "val = 'copied text';";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 9); // on 'c'
        vim_context_feed_keys(ctx, "yi'");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, text) == 0);
        free(ser);
        assert(!vim_context_is_dirty(ctx));
        assert(vim_context_get_cursor(ctx).line == 1 && vim_context_get_cursor(ctx).byteCol == 9);
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(strcmp(yanked, "copied text") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx);
    }

    // 4. di"
    {
        const char *text = "str = \"double quoted\";";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 9);
        vim_context_feed_keys(ctx, "di\"");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "str = \"\";") == 0);
        free(ser);
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(strcmp(yanked, "double quoted") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx);
    }

    // 5. ci"
    {
        const char *text = "str = \"old\";";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 8);
        vim_context_feed_keys(ctx, "ci\"new\x1b");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "str = \"new\";") == 0);
        free(ser);
        vim_context_destroy(ctx);
    }

    // 6. yi"
    {
        const char *text = "str = \"yank me\";";
        VimContextRef ctx = vim_context_create(text);
        vim_context_feed_keys(ctx, "yi\"");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, text) == 0);
        free(ser);
        assert(!vim_context_is_dirty(ctx));
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(strcmp(yanked, "yank me") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx);
    }

    // 7. Empty quotes: '' and ""
    {
        const char *text = "empty = '';";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 9);
        vim_context_feed_keys(ctx, "di'");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "empty = '';") == 0);
        free(ser);

        vim_context_feed_keys(ctx, "ci'inserted\x1b");
        ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "empty = 'inserted';") == 0);
        free(ser);
        vim_context_destroy(ctx);
    }
}

static void test_operator_inner_brackets(void) {
    // 1. di( / di) / dib
    {
        VimContextRef ctx1 = vim_context_create("foo(1, 2, 3);");
        vim_context_set_cursor(ctx1, 1, 7);
        vim_context_feed_keys(ctx1, "di(");
        char *ser1 = vim_context_serialize_buffer(ctx1, NULL);
        assert(strcmp(ser1, "foo();") == 0);
        free(ser1);
        bool linewise = true;
        assert(strcmp(vim_context_get_yank_buffer(ctx1, &linewise), "1, 2, 3") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx1);

        VimContextRef ctx2 = vim_context_create("bar(alpha);");
        vim_context_set_cursor(ctx2, 1, 6);
        vim_context_feed_keys(ctx2, "di)");
        char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
        assert(strcmp(ser2, "bar();") == 0);
        free(ser2);
        assert(strcmp(vim_context_get_yank_buffer(ctx2, &linewise), "alpha") == 0);
        vim_context_destroy(ctx2);

        VimContextRef ctx3 = vim_context_create("baz(test);");
        vim_context_set_cursor(ctx3, 1, 6);
        vim_context_feed_keys(ctx3, "dib");
        char *ser3 = vim_context_serialize_buffer(ctx3, NULL);
        assert(strcmp(ser3, "baz();") == 0);
        free(ser3);
        assert(strcmp(vim_context_get_yank_buffer(ctx3, &linewise), "test") == 0);
        vim_context_destroy(ctx3);
    }

    // 2. di[ / di]
    {
        VimContextRef ctx1 = vim_context_create("items = [a, b, c];");
        vim_context_set_cursor(ctx1, 1, 11);
        vim_context_feed_keys(ctx1, "di[");
        char *ser1 = vim_context_serialize_buffer(ctx1, NULL);
        assert(strcmp(ser1, "items = [];") == 0);
        free(ser1);
        bool linewise = true;
        assert(strcmp(vim_context_get_yank_buffer(ctx1, &linewise), "a, b, c") == 0);
        vim_context_destroy(ctx1);

        VimContextRef ctx2 = vim_context_create("items = [x, y];");
        vim_context_set_cursor(ctx2, 1, 10);
        vim_context_feed_keys(ctx2, "di]");
        char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
        assert(strcmp(ser2, "items = [];") == 0);
        free(ser2);
        assert(strcmp(vim_context_get_yank_buffer(ctx2, &linewise), "x, y") == 0);
        vim_context_destroy(ctx2);
    }

    // 3. di< / di>
    {
        VimContextRef ctx1 = vim_context_create("Template<TypeA, TypeB> x;");
        vim_context_set_cursor(ctx1, 1, 12);
        vim_context_feed_keys(ctx1, "di<");
        char *ser1 = vim_context_serialize_buffer(ctx1, NULL);
        assert(strcmp(ser1, "Template<> x;") == 0);
        free(ser1);
        bool linewise = true;
        assert(strcmp(vim_context_get_yank_buffer(ctx1, &linewise), "TypeA, TypeB") == 0);
        vim_context_destroy(ctx1);

        VimContextRef ctx2 = vim_context_create("List<Element> y;");
        vim_context_set_cursor(ctx2, 1, 7);
        vim_context_feed_keys(ctx2, "di>");
        char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
        assert(strcmp(ser2, "List<> y;") == 0);
        free(ser2);
        assert(strcmp(vim_context_get_yank_buffer(ctx2, &linewise), "Element") == 0);
        vim_context_destroy(ctx2);
    }

    // 4. di{ / di} / diB
    {
        VimContextRef ctx1 = vim_context_create("int fn() { return 0; }");
        vim_context_set_cursor(ctx1, 1, 14);
        vim_context_feed_keys(ctx1, "di{");
        char *ser1 = vim_context_serialize_buffer(ctx1, NULL);
        assert(strcmp(ser1, "int fn() {}") == 0);
        free(ser1);
        bool linewise = true;
        assert(strcmp(vim_context_get_yank_buffer(ctx1, &linewise), " return 0; ") == 0);
        vim_context_destroy(ctx1);

        VimContextRef ctx2 = vim_context_create("int fn() { x = 1; }");
        vim_context_set_cursor(ctx2, 1, 13);
        vim_context_feed_keys(ctx2, "di}");
        char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
        assert(strcmp(ser2, "int fn() {}") == 0);
        free(ser2);
        assert(strcmp(vim_context_get_yank_buffer(ctx2, &linewise), " x = 1; ") == 0);
        vim_context_destroy(ctx2);

        VimContextRef ctx3 = vim_context_create("int fn() { y = 2; }");
        vim_context_set_cursor(ctx3, 1, 13);
        vim_context_feed_keys(ctx3, "diB");
        char *ser3 = vim_context_serialize_buffer(ctx3, NULL);
        assert(strcmp(ser3, "int fn() {}") == 0);
        free(ser3);
        assert(strcmp(vim_context_get_yank_buffer(ctx3, &linewise), " y = 2; ") == 0);
        vim_context_destroy(ctx3);
    }

    // 5. Nested brackets: (foo (bar) baz)
    {
        VimContextRef ctx = vim_context_create("(foo (bar) baz)");
        vim_context_set_cursor(ctx, 1, 8); // on 'b' in bar
        vim_context_feed_keys(ctx, "di(");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "(foo () baz)") == 0);
        free(ser);
        bool linewise = true;
        assert(strcmp(vim_context_get_yank_buffer(ctx, &linewise), "bar") == 0);
        vim_context_destroy(ctx);
    }

    // 6. Empty brackets () and ci(
    {
        VimContextRef ctx = vim_context_create("run();");
        vim_context_set_cursor(ctx, 1, 4); // on '('
        vim_context_feed_keys(ctx, "di(");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "run();") == 0);
        free(ser);

        vim_context_feed_keys(ctx, "ci(param\x1b");
        ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "run(param);") == 0);
        free(ser);
        vim_context_destroy(ctx);
    }
}

static void test_operator_inner_multiline(void) {
    // 1. Multiline parentheses: di(
    {
        const char *text = "call(\n    arg1,\n    arg2\n);";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 2, 6); // on 'arg1'
        vim_context_feed_keys(ctx, "di(");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "call();") == 0);
        free(ser);
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(yanked != NULL);
        assert(strcmp(yanked, "\n    arg1,\n    arg2\n") == 0);
        assert(linewise == false);

        // Undo restores multiline text
        assert(vim_context_undo(ctx));
        char *ser_undo = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_undo, text) == 0);
        free(ser_undo);
        vim_context_destroy(ctx);
    }

    // 2. Multiline braces: ciB
    {
        const char *text = "struct Point {\n    int x;\n    int y;\n};";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 2, 5);
        vim_context_feed_keys(ctx, "ciBfloat x; float y;\x1b");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, "struct Point {float x; float y;};") == 0);
        free(ser);

        // Undo restores original in a single step
        assert(vim_context_undo(ctx));
        char *ser_undo = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_undo, text) == 0);
        free(ser_undo);
        vim_context_destroy(ctx);
    }

    // 3. Multiline square brackets: yi[
    {
        const char *text = "[\n  1,\n  2\n]";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 2, 3);
        vim_context_feed_keys(ctx, "yi[");
        char *ser = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser, text) == 0); // buffer unmodified
        free(ser);
        assert(!vim_context_is_dirty(ctx));
        bool linewise = true;
        const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
        assert(strcmp(yanked, "\n  1,\n  2\n") == 0);
        assert(linewise == false);
        vim_context_destroy(ctx);
    }
}

static void test_operator_inner_undo_redo(void) {
    // 1. di' undo and redo
    {
        const char *text = "val = 'original';";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 9);
        vim_context_feed_keys(ctx, "di'");
        char *ser1 = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser1, "val = '';") == 0);
        free(ser1);

        // Undo
        assert(vim_context_undo(ctx));
        char *ser_u = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_u, text) == 0);
        free(ser_u);

        // Redo (Ctrl-R)
        vim_context_feed_keys(ctx, "\x12");
        char *ser_r = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_r, "val = '';") == 0);
        free(ser_r);
        vim_context_destroy(ctx);
    }

    // 2. ci' cohesive undo group
    {
        const char *text = "str = 'alpha';";
        VimContextRef ctx = vim_context_create(text);
        vim_context_set_cursor(ctx, 1, 9);
        vim_context_feed_keys(ctx, "ci'beta\x1b");
        char *ser1 = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser1, "str = 'beta';") == 0);
        free(ser1);

        // Single 'u' should restore 'alpha', NOT an intermediate empty ''
        assert(vim_context_undo(ctx));
        char *ser_u = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_u, text) == 0);
        free(ser_u);

        // Redo restores 'beta'
        vim_context_feed_keys(ctx, "\x12");
        char *ser_r = vim_context_serialize_buffer(ctx, NULL);
        assert(strcmp(ser_r, "str = 'beta';") == 0);
        free(ser_r);
        vim_context_destroy(ctx);
    }
}

static void test_operator_inner_esc_cancellation(void) {
    const char *text = "name = 'test';";
    VimContextRef ctx = vim_context_create(text);
    vim_context_set_cursor(ctx, 1, 9);

    // 1. d<Esc>
    vim_context_feed_keys(ctx, "d\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(!vim_context_is_dirty(ctx));

    // 2. di<Esc>
    vim_context_feed_keys(ctx, "di\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(!vim_context_is_dirty(ctx));

    // 3. c<Esc>
    vim_context_feed_keys(ctx, "c\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(!vim_context_is_dirty(ctx));

    // 4. ci<Esc>
    vim_context_feed_keys(ctx, "ci\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(!vim_context_is_dirty(ctx));

    // 5. y<Esc>
    vim_context_feed_keys(ctx, "y\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // 6. yi<Esc>
    vim_context_feed_keys(ctx, "yi\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    // Subsequent normal motion works
    vim_context_feed_keys(ctx, "0");
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, text) == 0);
    free(ser);
    vim_context_destroy(ctx);
}

static void test_search_forward_n_N(void) {
    const char *text = "apple banana cherry\napple date elderberry\nfig grape apple";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Stream search "/apple\r"
    vim_context_feed_keys(ctx, "/");
    assert(vim_context_get_mode(ctx) == VIM_MODE_COMMAND);
    vim_context_feed_keys(ctx, "a");
    vim_context_feed_keys(ctx, "p");
    vim_context_feed_keys(ctx, "p");
    vim_context_feed_keys(ctx, "l");
    vim_context_feed_keys(ctx, "e");
    vim_context_feed_keys(ctx, "\r");

    // After <CR>, mode returns to NORMAL and cursor matches first occurrence (line 1, col 1)
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(vim_context_get_cursor(ctx).line == 1);
    assert(vim_context_get_cursor(ctx).byteCol == 1);
    assert(strcmp(vim_context_get_last_search(ctx), "apple") == 0);

    // 'n' moves forward to next match: line 2, col 1
    vim_context_feed_keys(ctx, "n");
    assert(vim_context_get_cursor(ctx).line == 2);
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    // 'n' moves forward to 3rd match: line 3, col 11
    vim_context_feed_keys(ctx, "n");
    assert(vim_context_get_cursor(ctx).line == 3);
    assert(vim_context_get_cursor(ctx).byteCol == 11);

    // 'n' wraps around to first match: line 1, col 1
    vim_context_feed_keys(ctx, "n");
    assert(vim_context_get_cursor(ctx).line == 1);
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    // 'N' moves backward to previous match: line 3, col 11
    vim_context_feed_keys(ctx, "N");
    assert(vim_context_get_cursor(ctx).line == 3);
    assert(vim_context_get_cursor(ctx).byteCol == 11);

    // 'N' moves backward to line 2, col 1
    vim_context_feed_keys(ctx, "N");
    assert(vim_context_get_cursor(ctx).line == 2);
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    // 'p' with empty yank buffer moves backward to line 1, col 1
    vim_context_feed_keys(ctx, "p");
    assert(vim_context_get_cursor(ctx).line == 1);
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    // 'p' wraps backward to line 3, col 11
    vim_context_feed_keys(ctx, "p");
    assert(vim_context_get_cursor(ctx).line == 3);
    assert(vim_context_get_cursor(ctx).byteCol == 11);

    // Yank line 3: now yank buffer is non-empty
    vim_context_feed_keys(ctx, "yy");
    bool lw = false;
    assert(vim_context_get_yank_buffer(ctx, &lw) != NULL);

    // 'p' now performs paste instead of search navigation!
    vim_context_feed_keys(ctx, "p");
    size_t ser_len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &ser_len);
    // After paste, buffer has 4 lines
    int nl_count = 0;
    for (size_t i = 0; i < ser_len; i++) {
        if (ser[i] == '\n') nl_count++;
    }
    assert(nl_count == 3); // 4 lines = 3 newlines
    free(ser);

    vim_context_destroy(ctx);

    // Test E35: No previous regular expression
    VimContextRef ctx_empty = vim_context_create("hello world");
    vim_context_feed_keys(ctx_empty, "n");
    assert(strstr(vim_context_get_last_error(ctx_empty), "E35") != NULL);

    vim_context_feed_keys(ctx_empty, "N");
    assert(strstr(vim_context_get_last_error(ctx_empty), "E35") != NULL);

    vim_context_feed_keys(ctx_empty, "/\r");
    assert(strstr(vim_context_get_last_error(ctx_empty), "E35") != NULL);

    // Test Pattern not found
    vim_context_feed_keys(ctx_empty, "/nonexistent\r");
    assert(strstr(vim_context_get_last_error(ctx_empty), "Pattern not found: nonexistent") != NULL);

    vim_context_destroy(ctx_empty);
}

static void test_ex_commands_streaming_and_ZZ(void) {
    const char *text = "alpha beta gamma\nfoo bar baz";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. Stream :%s/foo/super/g\r
    const char *s_cmd = ":%s/foo/super/g\r";
    for (size_t i = 0; i < strlen(s_cmd); i++) {
        char ch[2] = { s_cmd[i], '\0' };
        vim_context_feed_keys(ctx, ch);
    }
    size_t out_len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &out_len);
    assert(strstr(ser, "super bar baz") != NULL);
    free(ser);

    // 2. Stream :w\r
    vim_context_feed_keys(ctx, ":");
    vim_context_feed_keys(ctx, "w");
    vim_context_feed_keys(ctx, "\r");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE);
    vim_context_clear_pending_action(ctx);

    // 3. Stream :w!\r
    vim_context_feed_keys(ctx, ":");
    vim_context_feed_keys(ctx, "w");
    vim_context_feed_keys(ctx, "!");
    vim_context_feed_keys(ctx, "\r");
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE_FORCE);
    vim_context_clear_pending_action(ctx);

    // 4. Stream ZZ character-by-character
    vim_context_feed_keys(ctx, "Z");
    assert(vim_context_should_quit(ctx) == false);
    vim_context_feed_keys(ctx, "Z");
    assert(vim_context_should_quit(ctx) == true);
    assert(vim_context_get_pending_action(ctx) == VIM_ACTION_SAVE_AND_QUIT);
    vim_context_destroy(ctx);

    // 5. Ex command :ZZ
    VimContextRef ctx2 = vim_context_create("Clean doc");
    vim_context_execute_ex(ctx2, "ZZ");
    assert(vim_context_should_quit(ctx2) == true);
    assert(vim_context_get_pending_action(ctx2) == VIM_ACTION_QUIT);
    vim_context_destroy(ctx2);
}

static void test_navigation_motions_and_counts(void) {
    const char *text = "   hello world foo_bar baz\nsecond line 123 456\nthird line";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. Line motions: 0, ^, $
    vim_context_set_cursor(ctx, 1, 10);
    vim_context_feed_keys(ctx, "0"); // Start of line
    assert(vim_context_get_cursor(ctx).byteCol == 1);

    vim_context_feed_keys(ctx, "^"); // First non-blank
    assert(vim_context_get_cursor(ctx).byteCol == 4); // 'h'

    vim_context_feed_keys(ctx, "$"); // End of line
    assert(vim_context_get_cursor(ctx).byteCol == 26); // 'z'

    // 2. Word motions: w, b, e, ge
    vim_context_set_cursor(ctx, 1, 4); // on 'h' in 'hello'
    vim_context_feed_keys(ctx, "w");
    assert(vim_context_get_cursor(ctx).byteCol == 10); // 'w' in 'world'

    vim_context_feed_keys(ctx, "e");
    assert(vim_context_get_cursor(ctx).byteCol == 14); // 'd' in 'world'

    vim_context_feed_keys(ctx, "b");
    assert(vim_context_get_cursor(ctx).byteCol == 10); // 'w' in 'world'

    vim_context_feed_keys(ctx, "ge");
    assert(vim_context_get_cursor(ctx).byteCol == 8); // 'o' in 'hello'

    // 3. Inline find/till: f<char>, t<char>
    vim_context_set_cursor(ctx, 1, 4);
    vim_context_feed_keys(ctx, "f");
    vim_context_feed_keys(ctx, "w"); // find 'w' forward
    assert(vim_context_get_cursor(ctx).byteCol == 10);

    vim_context_set_cursor(ctx, 1, 4);
    vim_context_feed_keys(ctx, "t");
    vim_context_feed_keys(ctx, "w"); // till 'w' forward -> col 9 (space before 'w')
    assert(vim_context_get_cursor(ctx).byteCol == 9);

    // 4. Count prefixes: 2j, 2k, 2w
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "2");
    vim_context_feed_keys(ctx, "j");
    assert(vim_context_get_cursor(ctx).line == 3);

    vim_context_feed_keys(ctx, "2");
    vim_context_feed_keys(ctx, "k");
    assert(vim_context_get_cursor(ctx).line == 1);

    vim_context_set_cursor(ctx, 1, 4);
    vim_context_feed_keys(ctx, "2");
    vim_context_feed_keys(ctx, "w"); // 2w from 'hello' jumps to 'foo_bar'
    assert(vim_context_get_cursor(ctx).byteCol == 16);

    vim_context_destroy(ctx);
}

static void test_find_repeat_semicolon_comma(void) {
    // 0. Calling ';' or ',' before any find motion is executed
    {
        VimContextRef ctx0 = vim_context_create("hello world");
        assert(ctx0 != NULL);
        assert(vim_context_get_cursor(ctx0).byteCol == 1);
        vim_context_feed_keys(ctx0, ";");
        assert(vim_context_get_cursor(ctx0).byteCol == 1);
        vim_context_feed_keys(ctx0, ",");
        assert(vim_context_get_cursor(ctx0).byteCol == 1);
        vim_context_feed_keys(ctx0, "2;");
        assert(vim_context_get_cursor(ctx0).byteCol == 1);
        vim_context_destroy(ctx0);
    }

    const char *text = "alpha.bravo.charlie.delta.echo";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Initial cursor at (1, 1) on 'a'
    // Find '.' forward
    vim_context_feed_keys(ctx, "f.");
    assert(vim_context_get_cursor(ctx).byteCol == 6); // on first '.'

    // Repeat find forward with ';'
    vim_context_feed_keys(ctx, ";");
    assert(vim_context_get_cursor(ctx).byteCol == 12); // on second '.'

    // Repeat find forward with ';'
    vim_context_feed_keys(ctx, ";");
    assert(vim_context_get_cursor(ctx).byteCol == 20); // on third '.'

    // Repeat find backward with ','
    vim_context_feed_keys(ctx, ",");
    assert(vim_context_get_cursor(ctx).byteCol == 12); // back to second '.'

    // Repeat find backward with ',' again
    vim_context_feed_keys(ctx, ",");
    assert(vim_context_get_cursor(ctx).byteCol == 6); // back to first '.'

    // Now test 't' (till)
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "t.");
    assert(vim_context_get_cursor(ctx).byteCol == 5); // on 'a' before '.'

    vim_context_feed_keys(ctx, ";");
    assert(vim_context_get_cursor(ctx).byteCol == 11); // on 'o' before second '.'

    vim_context_feed_keys(ctx, ",");
    assert(vim_context_get_cursor(ctx).byteCol == 7); // on 'b' after first '.'

    // Count multipliers: 2; and 2,
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "f."); // col 6 (first '.')
    assert(vim_context_get_cursor(ctx).byteCol == 6);
    vim_context_feed_keys(ctx, "2;"); // skips second '.', lands on third '.' at col 20
    assert(vim_context_get_cursor(ctx).byteCol == 20);
    vim_context_feed_keys(ctx, "2,"); // backward 2 dots: from col 20 to col 6
    assert(vim_context_get_cursor(ctx).byteCol == 6);

    // Search misses where character is not found
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "fz"); // 'z' not in text
    assert(vim_context_get_cursor(ctx).byteCol == 1); // cursor unmoved

    // EOL clamping when repeating forward
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "f."); // col 6
    vim_context_feed_keys(ctx, ";");  // col 12
    vim_context_feed_keys(ctx, ";");  // col 20
    vim_context_feed_keys(ctx, ";");  // col 26 (fourth '.')
    assert(vim_context_get_cursor(ctx).byteCol == 26);
    vim_context_feed_keys(ctx, ";");  // no more '.' forward -> remains at 26
    assert(vim_context_get_cursor(ctx).byteCol == 26);
    vim_context_feed_keys(ctx, "5;"); // count beyond available matches -> remains at 26
    assert(vim_context_get_cursor(ctx).byteCol == 26);

    // BOL clamping at column 1 when repeating backward
    vim_context_feed_keys(ctx, "3,"); // backward 3 dots to first '.' (col 6)
    assert(vim_context_get_cursor(ctx).byteCol == 6);
    vim_context_feed_keys(ctx, ",");  // no more '.' backward -> remains at 6
    assert(vim_context_get_cursor(ctx).byteCol == 6);
    vim_context_feed_keys(ctx, "5,"); // large count backward -> remains at 6
    assert(vim_context_get_cursor(ctx).byteCol == 6);

    vim_context_destroy(ctx);
}

static void test_operator_mutations(void) {
    const char *text = "alpha beta gamma\none two three\nfoo bar baz";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. dd (delete line)
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "d");
    vim_context_feed_keys(ctx, "d");
    size_t out_len = 0;
    char *ser1 = vim_context_serialize_buffer(ctx, &out_len);
    assert(strstr(ser1, "one two three") == NULL);
    assert(strcmp(ser1, "alpha beta gamma\nfoo bar baz") == 0);
    free(ser1);

    // 2. p (paste after) - pastes the deleted line "one two three" below line 2
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "p");
    char *ser2 = vim_context_serialize_buffer(ctx, &out_len);
    assert(strcmp(ser2, "alpha beta gamma\nfoo bar baz\none two three") == 0);
    free(ser2);

    // 3. yy and P (paste before)
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "y");
    vim_context_feed_keys(ctx, "y");
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "P");
    char *ser3 = vim_context_serialize_buffer(ctx, &out_len);
    assert(strcmp(ser3, "alpha beta gamma\nalpha beta gamma\nfoo bar baz\none two three") == 0);
    free(ser3);
    vim_context_destroy(ctx);

    // 4. dw (delete word) and yw (yank word)
    VimContextRef ctx2 = vim_context_create("first second third");
    vim_context_set_cursor(ctx2, 1, 1);
    vim_context_feed_keys(ctx2, "d");
    vim_context_feed_keys(ctx2, "w");
    char *ser4 = vim_context_serialize_buffer(ctx2, &out_len);
    assert(strcmp(ser4, "second third") == 0);
    free(ser4);

    // 5. d$ (delete to end of line) and d0 (delete to start of line)
    VimContextRef ctx3 = vim_context_create("prefix middle suffix");
    vim_context_set_cursor(ctx3, 1, 8); // on 'm'
    vim_context_feed_keys(ctx3, "d");
    vim_context_feed_keys(ctx3, "$");
    char *ser5 = vim_context_serialize_buffer(ctx3, &out_len);
    assert(strcmp(ser5, "prefix ") == 0);
    free(ser5);

    VimContextRef ctx3b = vim_context_create("prefix middle suffix");
    vim_context_set_cursor(ctx3b, 1, 8); // on 'm'
    vim_context_feed_keys(ctx3b, "d");
    vim_context_feed_keys(ctx3b, "0");
    char *ser5b = vim_context_serialize_buffer(ctx3b, &out_len);
    assert(strcmp(ser5b, "middle suffix") == 0);
    free(ser5b);
    vim_context_destroy(ctx3);
    vim_context_destroy(ctx3b);

    // 6. cc and cw (change line / word)
    VimContextRef ctx4 = vim_context_create("old line text\nnext line");
    vim_context_set_cursor(ctx4, 1, 1);
    vim_context_feed_keys(ctx4, "c");
    vim_context_feed_keys(ctx4, "c");
    assert(vim_context_get_mode(ctx4) == VIM_MODE_INSERT);
    vim_context_feed_keys(ctx4, "new content\x1b");
    char *ser6 = vim_context_serialize_buffer(ctx4, &out_len);
    assert(strcmp(ser6, "new content\nnext line") == 0);
    free(ser6);

    vim_context_set_cursor(ctx4, 2, 1);
    vim_context_feed_keys(ctx4, "c");
    vim_context_feed_keys(ctx4, "w");
    assert(vim_context_get_mode(ctx4) == VIM_MODE_INSERT);
    vim_context_feed_keys(ctx4, "final\x1b");
    char *ser7 = vim_context_serialize_buffer(ctx4, &out_len);
    assert(strcmp(ser7, "new content\nfinal line") == 0);
    free(ser7);
    vim_context_destroy(ctx4);

    // 7. x (delete char), s (substitute char), r<char> (replace char)
    VimContextRef ctx5 = vim_context_create("abcdef");
    vim_context_set_cursor(ctx5, 1, 2); // 'b'
    vim_context_feed_keys(ctx5, "x");
    char *ser8 = vim_context_serialize_buffer(ctx5, &out_len);
    assert(strcmp(ser8, "acdef") == 0);
    free(ser8);

    vim_context_set_cursor(ctx5, 1, 2); // 'c'
    vim_context_feed_keys(ctx5, "r");
    vim_context_feed_keys(ctx5, "Z");
    char *ser9 = vim_context_serialize_buffer(ctx5, &out_len);
    assert(strcmp(ser9, "aZdef") == 0);
    free(ser9);

    vim_context_set_cursor(ctx5, 1, 2); // 'Z'
    vim_context_feed_keys(ctx5, "s");
    assert(vim_context_get_mode(ctx5) == VIM_MODE_INSERT);
    vim_context_feed_keys(ctx5, "NEW\x1b");
    char *ser10 = vim_context_serialize_buffer(ctx5, &out_len);
    assert(strcmp(ser10, "aNEWdef") == 0);
    free(ser10);
    vim_context_destroy(ctx5);

    // 8. J (join lines)
    VimContextRef ctx6 = vim_context_create("First line\nSecond line");
    vim_context_feed_keys(ctx6, "J");
    char *ser11 = vim_context_serialize_buffer(ctx6, &out_len);
    assert(strcmp(ser11, "First line Second line") == 0);
    free(ser11);
    vim_context_destroy(ctx6);
    vim_context_destroy(ctx2);
}

static void test_visual_selection_and_operators(void) {
    const char *text = "one two three\nfour five six";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. v (characterwise visual) + d (delete)
    vim_context_set_cursor(ctx, 1, 5); // on 't' in 'two'
    vim_context_feed_keys(ctx, "v");
    vim_context_feed_keys(ctx, "l");
    vim_context_feed_keys(ctx, "l"); // select 'two'
    vim_context_feed_keys(ctx, "d");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    size_t out_len = 0;
    char *ser1 = vim_context_serialize_buffer(ctx, &out_len);
    assert(strcmp(ser1, "one  three\nfour five six") == 0);
    free(ser1);

    // 2. V (linewise visual) + y (yank) + p (paste)
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "V");
    assert(vim_context_get_mode(ctx) == VIM_MODE_VISUAL);
    vim_context_feed_keys(ctx, "y");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "p");
    char *ser2 = vim_context_serialize_buffer(ctx, &out_len);
    assert(strcmp(ser2, "one  three\nfour five six\nfour five six") == 0);
    free(ser2);

    // 3. Visual characterwise delete only sets dirty flag if actual mutation occurs
    {
        VimContextRef ctx_dirty = vim_context_create("let x = \"\";");
        assert(ctx_dirty != NULL);
        assert(!vim_context_is_dirty(ctx_dirty));

        // vi" selects inner empty quotes
        vim_context_set_cursor(ctx_dirty, 1, 9);
        vim_context_feed_keys(ctx_dirty, "vi\"");
        assert(vim_context_get_mode(ctx_dirty) == VIM_MODE_VISUAL);
        assert(vim_context_is_empty_visual_selection(ctx_dirty));

        // Deleting empty selection (end <= start) should NOT mutate buffer or mark dirty
        vim_context_feed_keys(ctx_dirty, "d");
        assert(vim_context_get_mode(ctx_dirty) == VIM_MODE_NORMAL);
        assert(!vim_context_is_dirty(ctx_dirty));
        char *ser_clean = vim_context_serialize_buffer(ctx_dirty, NULL);
        assert(strcmp(ser_clean, "let x = \"\";") == 0);
        free(ser_clean);

        vim_context_destroy(ctx_dirty);
    }

    vim_context_destroy(ctx);
}

static void test_visual_motions_word_and_find(void) {
    const char *text = "alpha beta gamma delta";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. vey (visual select word to end, yank)
    vim_context_set_cursor(ctx, 1, 1); // on 'a' in 'alpha'
    vim_context_feed_keys(ctx, "vey");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    bool linewise = true;
    const char *yanked = vim_context_get_yank_buffer(ctx, &linewise);
    assert(yanked != NULL);
    assert(linewise == false);
    assert(strcmp(yanked, "alpha") == 0);

    // 2. vfgd (visual find 'g' in 'gamma' and delete)
    vim_context_set_cursor(ctx, 1, 7); // on 'b' in 'beta'
    vim_context_feed_keys(ctx, "vfgd"); // select from 'beta' to 'g' in 'gamma' and delete
    size_t out_len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &out_len);
    assert(ser != NULL);
    assert(strcmp(ser, "alpha amma delta") == 0);
    free(ser);
    vim_context_destroy(ctx);

    // 3. Visual backward motions (vb, vh)
    {
        VimContextRef ctx_b = vim_context_create("one two three four");
        assert(ctx_b != NULL);
        // Place cursor on 't' in 'three' (col 9)
        vim_context_set_cursor(ctx_b, 1, 9);
        vim_context_feed_keys(ctx_b, "v");
        assert(vim_context_get_mode(ctx_b) == VIM_MODE_VISUAL);
        // 'b' backward motion in visual mode
        vim_context_feed_keys(ctx_b, "b");
        assert(vim_context_get_cursor(ctx_b).byteCol == 5); // on 't' in 'two'
        // '2h' backward motion in visual mode
        vim_context_feed_keys(ctx_b, "2h");
        assert(vim_context_get_cursor(ctx_b).byteCol == 3); // on 'e' in 'one'
        // Delete backward visual selection (from col 3 to col 9)
        vim_context_feed_keys(ctx_b, "d");
        assert(vim_context_get_mode(ctx_b) == VIM_MODE_NORMAL);
        char *ser_b = vim_context_serialize_buffer(ctx_b, NULL);
        assert(strcmp(ser_b, "onhree four") == 0);
        free(ser_b);
        vim_context_destroy(ctx_b);
    }

    // 4. Visual repeat find motions (; and ,)
    {
        VimContextRef ctx_find = vim_context_create("first.second.third.fourth");
        assert(ctx_find != NULL);
        vim_context_set_cursor(ctx_find, 1, 1);
        vim_context_feed_keys(ctx_find, "v");
        vim_context_feed_keys(ctx_find, "f."); // to first '.' at col 6
        assert(vim_context_get_cursor(ctx_find).byteCol == 6);
        vim_context_feed_keys(ctx_find, ";");  // to second '.' at col 13
        assert(vim_context_get_cursor(ctx_find).byteCol == 13);
        vim_context_feed_keys(ctx_find, ";");  // to third '.' at col 19
        assert(vim_context_get_cursor(ctx_find).byteCol == 19);
        vim_context_feed_keys(ctx_find, ",");  // backward repeat to second '.' at col 13
        assert(vim_context_get_cursor(ctx_find).byteCol == 13);
        vim_context_feed_keys(ctx_find, "y");
        assert(vim_context_get_mode(ctx_find) == VIM_MODE_NORMAL);
        bool lwise = true;
        const char *y = vim_context_get_yank_buffer(ctx_find, &lwise);
        assert(y != NULL && strcmp(y, "first.second.") == 0);
        vim_context_destroy(ctx_find);
    }

    // 5. Visual till motions (vt)
    {
        VimContextRef ctx_till = vim_context_create("prefix:target:suffix");
        assert(ctx_till != NULL);
        vim_context_set_cursor(ctx_till, 1, 1);
        vim_context_feed_keys(ctx_till, "vt:"); // till ':' -> col 6 ('x')
        assert(vim_context_get_cursor(ctx_till).byteCol == 6);
        vim_context_feed_keys(ctx_till, "y");
        bool lwise = true;
        const char *y = vim_context_get_yank_buffer(ctx_till, &lwise);
        assert(y != NULL && strcmp(y, "prefix") == 0);
        vim_context_destroy(ctx_till);
    }

    // 6. Visual line boundary motions (v0, v$, v^)
    {
        VimContextRef ctx_bnd = vim_context_create("   indented line   ");
        assert(ctx_bnd != NULL);
        // Cursor at col 12 ('l' in line)
        vim_context_set_cursor(ctx_bnd, 1, 12);

        // v0 -> cursor to col 1
        vim_context_feed_keys(ctx_bnd, "v0\x1b");
        assert(vim_context_get_cursor(ctx_bnd).byteCol == 1);
        assert(vim_context_get_mode(ctx_bnd) == VIM_MODE_NORMAL);

        // v^ -> cursor to first non-whitespace (col 4 'i')
        vim_context_set_cursor(ctx_bnd, 1, 12);
        vim_context_feed_keys(ctx_bnd, "v^\x1b");
        assert(vim_context_get_cursor(ctx_bnd).byteCol == 4);

        // v$ -> cursor to last character (col 19)
        vim_context_set_cursor(ctx_bnd, 1, 4);
        vim_context_feed_keys(ctx_bnd, "v$\x1b");
        assert(vim_context_get_cursor(ctx_bnd).byteCol == 19);

        vim_context_destroy(ctx_bnd);
    }

    // 7. Motion count multipliers in visual mode (e.g. v2wd)
    {
        VimContextRef ctx_cnt = vim_context_create("word1 word2 word3 word4");
        assert(ctx_cnt != NULL);
        vim_context_set_cursor(ctx_cnt, 1, 1);
        vim_context_feed_keys(ctx_cnt, "v2wd"); // select forward 2 words (inclusive of 'w' in word3) and delete
        assert(vim_context_get_mode(ctx_cnt) == VIM_MODE_NORMAL);
        char *ser_cnt = vim_context_serialize_buffer(ctx_cnt, NULL);
        assert(strcmp(ser_cnt, "ord3 word4") == 0);
        free(ser_cnt);
        vim_context_destroy(ctx_cnt);
    }

    // 8. Esc cancellation in visual mode (vf<Esc>, vg<Esc>)
    {
        VimContextRef ctx_esc = vim_context_create("alpha beta gamma");
        assert(ctx_esc != NULL);
        vim_context_set_cursor(ctx_esc, 1, 1);

        // vf<Esc>: cancels pending find, mode remains VISUAL
        vim_context_feed_keys(ctx_esc, "vf");
        vim_context_feed_keys(ctx_esc, "\x1b"); // cancel find
        assert(vim_context_get_mode(ctx_esc) == VIM_MODE_VISUAL);
        // Next key 'w' is a motion, NOT target for 'f'
        vim_context_feed_keys(ctx_esc, "w");
        assert(vim_context_get_cursor(ctx_esc).byteCol == 7);
        vim_context_feed_keys(ctx_esc, "\x1b"); // exit visual mode
        assert(vim_context_get_mode(ctx_esc) == VIM_MODE_NORMAL);

        // vg<Esc>: cancels pending leader, mode remains VISUAL
        vim_context_feed_keys(ctx_esc, "vg");
        vim_context_feed_keys(ctx_esc, "\x1b"); // cancel leader
        assert(vim_context_get_mode(ctx_esc) == VIM_MODE_VISUAL);
        vim_context_feed_keys(ctx_esc, "\x1b"); // exit visual mode
        assert(vim_context_get_mode(ctx_esc) == VIM_MODE_NORMAL);

        vim_context_destroy(ctx_esc);
    }
}

static void test_esc_cancellation(void) {
    VimContextRef ctx = vim_context_create("Line 1\nLine 2\nLine 3");
    assert(ctx != NULL);

    // 1. Pending 'g' cancelled by <Esc>
    vim_context_set_cursor(ctx, 2, 1);
    vim_context_feed_keys(ctx, "g");
    vim_context_feed_keys(ctx, "\x1b"); // cancel
    vim_context_feed_keys(ctx, "g"); // this is now a fresh leader, not second 'g'
    assert(vim_context_get_cursor(ctx).line == 2); // Still at line 2!
    vim_context_feed_keys(ctx, "\x1b"); // clean up

    // 2. Pending operator 'd' cancelled by <Esc>
    vim_context_feed_keys(ctx, "d");
    vim_context_feed_keys(ctx, "\x1b");
    vim_context_feed_keys(ctx, "d"); // fresh operator, not second 'd' of 'dd'
    size_t out_len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &out_len);
    assert(strcmp(ser, "Line 1\nLine 2\nLine 3") == 0); // No lines deleted!
    free(ser);
    vim_context_feed_keys(ctx, "\x1b");

    // 3. Count cancelled by <Esc>
    vim_context_feed_keys(ctx, "5");
    vim_context_feed_keys(ctx, "\x1b");
    vim_context_feed_keys(ctx, "j"); // single 'j', not 5j
    assert(vim_context_get_cursor(ctx).line == 3); // Moved from 2 to 3 (single step)

    vim_context_destroy(ctx);
}

static char g_last_yank_text[512];
static bool g_last_yank_linewise = false;
static int g_yank_callback_count = 0;

static void cbridge_test_yank_cb(const char *text, bool linewise, void *userInfo) {
    (void)userInfo;
    g_yank_callback_count++;
    g_last_yank_linewise = linewise;
    if (text) {
        strncpy(g_last_yank_text, text, sizeof(g_last_yank_text) - 1);
        g_last_yank_text[sizeof(g_last_yank_text) - 1] = '\0';
    } else {
        g_last_yank_text[0] = '\0';
    }
}

static void test_yank_callback_and_clipboard(void) {
    VimContextRef ctx = vim_context_create("first line\nsecond line\nthird line");
    assert(ctx != NULL);

    g_yank_callback_count = 0;
    g_last_yank_text[0] = '\0';
    g_last_yank_linewise = false;

    // Register yank callback
    vim_context_set_yank_callback(ctx, cbridge_test_yank_cb, NULL);

    // 1. Test 'yy' (yank line)
    vim_context_feed_keys(ctx, "yy");
    assert(g_yank_callback_count == 1);
    assert(g_last_yank_linewise == true);
    assert(strstr(g_last_yank_text, "first line") != NULL);

    bool out_linewise = false;
    const char *y_buf = vim_context_get_yank_buffer(ctx, &out_linewise);
    assert(y_buf != NULL);
    assert(out_linewise == true);
    assert(strstr(y_buf, "first line") != NULL);

    // 2. Test 'yw' (yank word)
    vim_context_feed_keys(ctx, "yw");
    assert(g_yank_callback_count == 2);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "first ") == 0 || strcmp(g_last_yank_text, "first") == 0);

    // 3. Test 'y$' (yank to end of line)
    vim_context_feed_keys(ctx, "y$");
    assert(g_yank_callback_count == 3);
    assert(g_last_yank_linewise == false);
    assert(strstr(g_last_yank_text, "first line") != NULL);

    // 4. Test 'dd' (delete line)
    vim_context_feed_keys(ctx, "dd");
    assert(g_yank_callback_count == 4);
    assert(g_last_yank_linewise == true);
    assert(strstr(g_last_yank_text, "first line") != NULL);

    // 5. Test 'dw' (delete word) on line 1 ("second line")
    vim_context_feed_keys(ctx, "dw");
    assert(g_yank_callback_count == 5);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "second ") == 0 || strcmp(g_last_yank_text, "second") == 0);

    // 6. Test 'x' (cut single character) on "line"
    vim_context_feed_keys(ctx, "x");
    assert(g_yank_callback_count == 6);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "l") == 0);

    // 7. Test 's' (substitute single character) -> 'i', then escape
    vim_context_feed_keys(ctx, "s\x1b");
    assert(g_yank_callback_count == 7);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "i") == 0);

    // 8. Test 'cw' (change word)
    vim_context_feed_keys(ctx, "cw\x1b");
    assert(g_yank_callback_count == 8);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "ne") == 0);

    // 9. Test 'cc' (change line)
    vim_context_feed_keys(ctx, "cc\x1b");
    assert(g_yank_callback_count == 9);
    assert(g_last_yank_linewise == true);

    // 10. Visual mode yank 'v...y'
    vim_context_set_cursor(ctx, 2, 1); // "third line"
    vim_context_feed_keys(ctx, "v2ly"); // visual select "thi", yank
    assert(g_yank_callback_count == 10);
    assert(g_last_yank_linewise == false);
    assert(strcmp(g_last_yank_text, "thi") == 0);

    // 11. Visual linewise yank 'V...y'
    vim_context_feed_keys(ctx, "Vy");
    assert(g_yank_callback_count == 11);
    assert(g_last_yank_linewise == true);
    assert(strstr(g_last_yank_text, "third line") != NULL);

    // 12. Test external pasteboard sync: vim_context_set_yank_buffer and 'p'
    const char *ext_clip = "external pasted text";
    vim_context_set_yank_buffer(ctx, ext_clip, false);
    const char *check_buf = vim_context_get_yank_buffer(ctx, &out_linewise);
    assert(strcmp(check_buf, ext_clip) == 0);
    assert(out_linewise == false);

    // Paste with 'p'
    vim_context_feed_keys(ctx, "p");
    size_t out_len = 0;
    char *ser = vim_context_serialize_buffer(ctx, &out_len);
    assert(ser != NULL);
    assert(strstr(ser, ext_clip) != NULL);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_undo_redo_basic(void) {
    const char *initial = "Hello World\nLine two";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);
    assert(!vim_context_can_undo(ctx));
    assert(!vim_context_can_redo(ctx));

    // Delete character 'H' with 'x'
    vim_context_feed_keys(ctx, "x");
    assert(vim_context_can_undo(ctx));
    assert(!vim_context_can_redo(ctx));
    assert(vim_context_is_dirty(ctx));

    char *ser1 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser1, "ello World\nLine two") == 0);
    free(ser1);

    // Undo with 'u'
    vim_context_feed_keys(ctx, "u");
    assert(!vim_context_can_undo(ctx));
    assert(vim_context_can_redo(ctx));
    assert(!vim_context_is_dirty(ctx));

    char *ser2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser2, initial) == 0);
    free(ser2);

    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // Redo with Ctrl+R (\x12)
    vim_context_feed_keys(ctx, "\x12");
    assert(vim_context_can_undo(ctx));
    assert(!vim_context_can_redo(ctx));
    assert(vim_context_is_dirty(ctx));

    char *ser3 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser3, "ello World\nLine two") == 0);
    free(ser3);

    vim_context_destroy(ctx);
}

static void test_undo_redo_sequential(void) {
    const char *initial = "Line 1\nLine 2\nLine 3";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    // Edit 1: delete line 1 with "dd"
    vim_context_feed_keys(ctx, "dd");
    char *s1 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s1, "Line 2\nLine 3") == 0);
    free(s1);

    // Edit 2: append line "Line 2.5" with "oLine 2.5\x1b"
    vim_context_feed_keys(ctx, "oLine 2.5\x1b");
    char *s2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s2, "Line 2\nLine 2.5\nLine 3") == 0);
    free(s2);

    // Undo 1: should undo Edit 2, restoring "Line 2\nLine 3"
    bool u1 = vim_context_undo(ctx);
    assert(u1);
    char *u1_ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(u1_ser, "Line 2\nLine 3") == 0);
    free(u1_ser);

    // Undo 2: should undo Edit 1, restoring initial text "Line 1\nLine 2\nLine 3"
    bool u2 = vim_context_undo(ctx);
    assert(u2);
    char *u2_ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(u2_ser, initial) == 0);
    free(u2_ser);
    assert(!vim_context_can_undo(ctx));

    // Redo 1: should redo Edit 1, restoring "Line 2\nLine 3"
    bool r1 = vim_context_redo(ctx);
    assert(r1);
    char *r1_ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(r1_ser, "Line 2\nLine 3") == 0);
    free(r1_ser);

    // Redo 2: should redo Edit 2, restoring "Line 2\nLine 2.5\nLine 3"
    bool r2 = vim_context_redo(ctx);
    assert(r2);
    char *r2_ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(r2_ser, "Line 2\nLine 2.5\nLine 3") == 0);
    free(r2_ser);
    assert(!vim_context_can_redo(ctx));

    vim_context_destroy(ctx);
}

static void test_undo_insert_session_cohesive(void) {
    const char *initial = "Header: ";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    // Move to end of line: "$"
    vim_context_feed_keys(ctx, "$");

    // Enter insert mode, type multiple words, insert newline, backspace, and exit
    vim_context_feed_keys(ctx, "aDraft One\nDraft Two\x7f\x7f\x1b");

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Header: Draft One\nDraft T") == 0);
    free(ser);

    // Single 'u' must undo the ENTIRE insert session
    vim_context_feed_keys(ctx, "u");

    char *undone = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(undone, initial) == 0);
    free(undone);

    // Redo with Ctrl+R restores the whole typed session
    vim_context_feed_keys(ctx, "\x12");

    char *redone = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(redone, "Header: Draft One\nDraft T") == 0);
    free(redone);

    vim_context_destroy(ctx);
}

static void test_undo_ex_commands(void) {
    const char *initial = "apple banana apple";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    // Substitute apple -> orange
    vim_context_execute_ex(ctx, "%s/apple/orange/g");

    char *s1 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s1, "orange banana orange") == 0);
    free(s1);

    // Undo via Ex command ":u"
    vim_context_execute_ex(ctx, "u");

    char *s2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s2, initial) == 0);
    free(s2);

    // Redo via Ex command ":redo"
    vim_context_execute_ex(ctx, "redo");

    char *s3 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s3, "orange banana orange") == 0);
    free(s3);

    // Undo via Ex command ":undo"
    vim_context_execute_ex(ctx, "undo");
    char *s4 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s4, initial) == 0);
    free(s4);

    // Redo via Ex command ":red"
    vim_context_execute_ex(ctx, "red");
    char *s5 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(s5, "orange banana orange") == 0);
    free(s5);

    vim_context_destroy(ctx);
}

static void test_undo_tree_truncation_on_new_edit(void) {
    VimContextRef ctx = vim_context_create("Base Line");
    assert(ctx != NULL);

    vim_context_feed_keys(ctx, "oSecond\x1b");
    vim_context_feed_keys(ctx, "oThird\x1b");

    // Undo to "Second"
    vim_context_feed_keys(ctx, "u");
    assert(vim_context_can_redo(ctx));

    // Performing a new edit must invalidate and clear redo history
    vim_context_feed_keys(ctx, "oBranch Line\x1b");
    assert(!vim_context_can_redo(ctx));

    // Ctrl+R should do nothing
    bool redone = vim_context_redo(ctx);
    assert(!redone);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Base Line\nSecond\nBranch Line") == 0);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_undo_cap_levels(void) {
    VimContextRef ctx = vim_context_create("Initial");
    assert(ctx != NULL);

    // Perform 120 sequential edits
    for (int i = 0; i < 120; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "oLine %d\x1b", i);
        vim_context_feed_keys(ctx, buf);
    }

    assert(vim_context_can_undo(ctx));

    // Undo 100 times should succeed
    int undos = 0;
    while (vim_context_undo(ctx)) {
        undos++;
    }
    // Cap is 100 levels
    assert(undos == 100);
    assert(!vim_context_can_undo(ctx));

    vim_context_destroy(ctx);
}

static void test_sort_alphabetical(void) {
    const char *initial = "delta\nalpha\ncharlie\nbravo";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    MockDeltaState delta = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &delta);

    vim_context_execute_ex(ctx, "sort");
    assert(vim_context_is_dirty(ctx) == true);
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "alpha\nbravo\ncharlie\ndelta") == 0);
    free(ser);

    assert(delta.call_count == 1);
    assert(delta.start_line == 1);
    assert(delta.deleted_count == 4);
    assert(delta.added_count == 4);
    assert(strcmp(delta.first_added_line, "alpha") == 0);

    // Test with leading colon and with %sort
    VimContextRef ctx2 = vim_context_create("z\ny\nx");
    vim_context_execute_ex(ctx2, ":%sort");
    char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(ser2, "x\ny\nz") == 0);
    free(ser2);
    vim_context_destroy(ctx2);

    vim_context_destroy(ctx);
}

static void test_sort_reverse(void) {
    const char *initial = "alpha\nbravo\ncharlie\ndelta";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    vim_context_execute_ex(ctx, "sort!");
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "delta\ncharlie\nbravo\nalpha") == 0);
    free(ser);

    // Test with :%sort!
    vim_context_execute_ex(ctx, ":%sort!");
    char *ser2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser2, "delta\ncharlie\nbravo\nalpha") == 0);
    free(ser2);

    vim_context_destroy(ctx);
}

static void test_sort_case_insensitive(void) {
    // In ASCII: Apple (65), Cherry (67), apple (97), banana (98)
    const char *initial = "banana\napple\nApple\nCherry";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    // Without 'i', standard sort: Apple, Cherry, apple, banana
    // With 'i', case-insensitive sort: Apple & apple before banana before Cherry
    vim_context_execute_ex(ctx, "sort i");
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "Apple\napple\nbanana\nCherry") == 0);
    free(ser);

    // Reverse case-insensitive: sort! i
    vim_context_execute_ex(ctx, ":sort! i");
    char *ser2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser2, "Cherry\nbanana\napple\nApple") == 0);
    free(ser2);

    vim_context_destroy(ctx);
}

static void test_sort_unique(void) {
    const char *initial = "delta\nalpha\nbravo\nalpha\ncharlie\nbravo\ndelta";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    MockDeltaState delta = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &delta);

    vim_context_execute_ex(ctx, "sort u");
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "alpha\nbravo\ncharlie\ndelta") == 0);
    free(ser);

    assert(delta.call_count == 1);
    assert(delta.start_line == 1);
    assert(delta.deleted_count == 7);
    assert(delta.added_count == 4);

    // Test sort! u (reverse unique)
    VimContextRef ctx2 = vim_context_create("b\na\nb\na\nc");
    vim_context_execute_ex(ctx2, ":sort! u");
    char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(ser2, "c\nb\na") == 0);
    free(ser2);
    vim_context_destroy(ctx2);

    vim_context_destroy(ctx);
}

static void test_sort_numeric(void) {
    const char *initial = "item 100\nitem 2\nitem 10\nitem 1";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    vim_context_execute_ex(ctx, "sort n");
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "item 1\nitem 2\nitem 10\nitem 100") == 0);
    free(ser);

    // Test sort! n (reverse numeric)
    vim_context_execute_ex(ctx, ":sort! n");
    char *ser2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser2, "item 100\nitem 10\nitem 2\nitem 1") == 0);
    free(ser2);

    // Combined unique + numeric: sort u n
    VimContextRef ctx2 = vim_context_create("20\n2\n100\n20\n2");
    vim_context_execute_ex(ctx2, "sort u n");
    char *ser3 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(ser3, "2\n20\n100") == 0);
    free(ser3);
    vim_context_destroy(ctx2);

    vim_context_destroy(ctx);
}

static void test_sort_range(void) {
    const char *initial = "header\nzebra\napple\nmango\nfooter";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    MockDeltaState delta = {0};
    vim_context_set_delta_callback(ctx, mock_delta_callback, &delta);

    // Explicit range :2,4sort
    vim_context_execute_ex(ctx, ":2,4sort");
    assert(strlen(vim_context_get_last_error(ctx)) == 0);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(ser != NULL);
    assert(strcmp(ser, "header\napple\nmango\nzebra\nfooter") == 0);
    free(ser);

    assert(delta.call_count == 1);
    assert(delta.start_line == 2);
    assert(delta.deleted_count == 3);
    assert(delta.added_count == 3);

    // Visual range :'<,'>sort
    VimContextRef ctx2 = vim_context_create("line1\nzoo\nbear\ncat\nline5");
    vim_context_set_visual_anchor(ctx2, 2, 1);
    vim_context_set_cursor(ctx2, 4, 1);
    vim_context_execute_ex(ctx2, ":'<,'>sort");
    assert(strlen(vim_context_get_last_error(ctx2)) == 0);

    char *ser2 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(ser2, "line1\nbear\ncat\nzoo\nline5") == 0);
    free(ser2);
    vim_context_destroy(ctx2);

    // Single-line range: safe no-op
    VimContextRef ctx3 = vim_context_create("single");
    vim_context_execute_ex(ctx3, ":1,1sort");
    assert(strlen(vim_context_get_last_error(ctx3)) == 0);
    vim_context_destroy(ctx3);

    // Empty buffer: safe no-op
    VimContextRef ctx4 = vim_context_create("");
    vim_context_execute_ex(ctx4, ":sort");
    assert(strlen(vim_context_get_last_error(ctx4)) == 0);
    vim_context_destroy(ctx4);

    // Invalid range: start > end -> E16: Invalid range
    vim_context_execute_ex(ctx, ":5,2sort");
    assert(strstr(vim_context_get_last_error(ctx), "E16: Invalid range") != NULL);

    // Invalid range: start < 1
    vim_context_execute_ex(ctx, ":0,3sort");
    assert(strstr(vim_context_get_last_error(ctx), "E16: Invalid range") != NULL);

    // Malformed sort command
    vim_context_execute_ex(ctx, ":sort xyz");
    assert(strstr(vim_context_get_last_error(ctx), "E492") != NULL);

    vim_context_destroy(ctx);
}

static void test_sort_undo_redo(void) {
    const char *initial = "dog\ncat\nbird";
    VimContextRef ctx = vim_context_create(initial);
    assert(ctx != NULL);

    vim_context_execute_ex(ctx, "sort");
    char *ser1 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser1, "bird\ncat\ndog") == 0);
    free(ser1);

    // Undo restores original order
    bool u1 = vim_context_undo(ctx);
    assert(u1);
    char *ser2 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser2, initial) == 0);
    free(ser2);

    // Redo restores sorted order
    bool r1 = vim_context_redo(ctx);
    assert(r1);
    char *ser3 = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser3, "bird\ncat\ndog") == 0);
    free(ser3);

    // Undo with unique deduplication
    VimContextRef ctx2 = vim_context_create("b\na\nb\na");
    vim_context_execute_ex(ctx2, "sort u");
    char *s1 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(s1, "a\nb") == 0);
    free(s1);

    assert(vim_context_undo(ctx2));
    char *s2 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(s2, "b\na\nb\na") == 0);
    free(s2);

    assert(vim_context_redo(ctx2));
    char *s3 = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(s3, "a\nb") == 0);
    free(s3);

    vim_context_destroy(ctx2);
    vim_context_destroy(ctx);
}

static void test_count_accumulator(void) {
    VimContextRef ctx = vim_context_create("line 1\nline 2\nline 3\nline 4\nline 5\n");
    assert(ctx != NULL);

    assert(vim_context_get_count_accumulator(ctx) == 0);
    assert(!vim_context_has_pending_command(ctx));

    // Feed '2'
    vim_context_feed_keys(ctx, "2");
    assert(vim_context_get_count_accumulator(ctx) == 2);

    // Feed '3' -> accumulator becomes 23
    vim_context_feed_keys(ctx, "3");
    assert(vim_context_get_count_accumulator(ctx) == 23);

    // Clear accumulator
    vim_context_clear_count_accumulator(ctx);
    assert(vim_context_get_count_accumulator(ctx) == 0);

    // Overflow protection: feeding 9999999999 should not overflow or become negative
    vim_context_feed_keys(ctx, "9999999999");
    int acc = vim_context_get_count_accumulator(ctx);
    assert(acc > 0);
    assert(acc <= 999999999);

    vim_context_clear_count_accumulator(ctx);

    // Test has_pending_command with 'f'
    assert(!vim_context_has_pending_command(ctx));
    vim_context_feed_keys(ctx, "f");
    assert(vim_context_has_pending_command(ctx));
    vim_context_feed_keys(ctx, "1"); // complete find
    assert(!vim_context_has_pending_command(ctx));

    // Test has_pending_command with 'r'
    vim_context_feed_keys(ctx, "r");
    assert(vim_context_has_pending_command(ctx));
    vim_context_feed_keys(ctx, "x"); // complete replace
    assert(!vim_context_has_pending_command(ctx));

    vim_context_destroy(ctx);
}

static void test_replace_mode_overwrite_and_backspace_restore(void) {
    const char *text = "hello world\nsecond line";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Enter replace mode with 'R'
    vim_context_feed_keys(ctx, "R");
    assert(vim_context_get_mode(ctx) == VIM_MODE_REPLACE);

    // Overwrite with 'X', 'Y', 'Z'
    vim_context_feed_keys(ctx, "XYZ");
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "XYZlo world\nsecond line") == 0);
    free(ser);
    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 4);

    // Backspace twice: restore 'e' and 'l'
    vim_context_feed_keys(ctx, "\x7f\x7f");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Xello world\nsecond line") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 2);

    // Backspace once more: restore 'h'
    vim_context_feed_keys(ctx, "\x7f");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "hello world\nsecond line") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // Backspacing at column 1 stays at column 1 and does not crash or underflow
    vim_context_feed_keys(ctx, "\x7f");
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // 4-byte UTF-8 emoji replacement (😀: \xF0\x9F\x98\x80) and Backspace restoration in Replace mode
    vim_context_feed_keys(ctx, "\xf0\x9f\x98\x80");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strncmp(ser, "\xf0\x9f\x98\x80", 4) == 0);
    free(ser);
    // Backspace restores original 1-byte char 'h'
    vim_context_feed_keys(ctx, "\x7f");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strncmp(ser, "hello", 5) == 0);
    free(ser);

    // Exit Replace mode with Esc
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);

    vim_context_destroy(ctx);
}

static void test_replace_mode_extend_line_and_esc_undo(void) {
    const char *text = "abc";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Move to col 2 ('b')
    vim_context_feed_keys(ctx, "l");
    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.byteCol == 2);

    // Enter Replace mode and type '1', '2', '3', '4', '5'
    // '1' overwrites 'b', '2' overwrites 'c', '3','4','5' extend the line
    vim_context_feed_keys(ctx, "R12345");
    assert(vim_context_get_mode(ctx) == VIM_MODE_REPLACE);
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "a12345") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.byteCol == 7);

    // Backspace once restores/truncates '5'
    vim_context_feed_keys(ctx, "\x7f");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "a1234") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.byteCol == 6);

    // Esc returns to Normal mode, clamps cursor to col 5 (on '4')
    vim_context_feed_keys(ctx, "\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    pos = vim_context_get_cursor(ctx);
    assert(pos.byteCol == 5);

    // Single cohesive undo restores the original buffer "abc"
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "abc") == 0);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_single_char_replace_multibyte(void) {
    const char *text = "hello world";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Single ASCII replace
    vim_context_feed_keys(ctx, "rX");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Xello world") == 0);
    free(ser);

    // Move to col 2 ('e') and replace with 2-byte UTF-8 'é' (\xC3\xA9)
    vim_context_feed_keys(ctx, "l");
    vim_context_feed_keys(ctx, "r\xc3\xa9");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "X\xc3\xa9llo world") == 0);
    free(ser);

    // Replace the 2-byte 'é' with a 3-byte UTF-8 '世' (\xE4\xB8\x96)
    vim_context_feed_keys(ctx, "r\xe4\xb8\x96");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "X\xe4\xb8\x96llo world") == 0);
    free(ser);

    // Undo should restore 'é'
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "X\xc3\xa9llo world") == 0);
    free(ser);

    // Undo again restores 'e'
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Xello world") == 0);
    free(ser);

    // r<Esc> cancellation leaves buffer unchanged
    vim_context_feed_keys(ctx, "r\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Xello world") == 0);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_visual_selection_replace(void) {
    const char *text = "abcdef\n123456";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // Characterwise visual selection: select "abc" and replace with '*'
    // 'v' starts visual at col 1, 'l' to col 2, 'l' to col 3
    vim_context_feed_keys(ctx, "vllr*");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "***def\n123456") == 0);
    free(ser);
    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 1);

    // Single undo restores "abcdef\n123456"
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "abcdef\n123456") == 0);
    free(ser);

    // Linewise visual selection: select both lines and replace with 'X'
    vim_context_feed_keys(ctx, "VjrX");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "XXXXXX\nXXXXXX") == 0);
    free(ser);

    // Single undo restores original
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "abcdef\n123456") == 0);
    free(ser);

    // Multiline characterwise visual replace (v...j...r*)
    // Start at line 1 col 3 ('c'), select down to line 2 col 4 ('4')
    vim_context_feed_keys(ctx, "ggllvjl");
    assert(vim_context_get_mode(ctx) == VIM_MODE_VISUAL);
    vim_context_feed_keys(ctx, "r*");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "ab****\n****56") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1 && pos.byteCol == 3);

    // Single undo restores original
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "abcdef\n123456") == 0);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_substitute_line_S(void) {
    const char *text = "first line\nsecond line";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 'S' clears current line and enters insert mode
    vim_context_feed_keys(ctx, "SReplacement\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "Replacement\nsecond line") == 0);
    free(ser);

    // Single undo restores "first line\nsecond line"
    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "first line\nsecond line") == 0);
    free(ser);

    // Also verify 's' (single char substitute) with undo
    vim_context_feed_keys(ctx, "sF\x1b");
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "First line\nsecond line") == 0);
    free(ser);

    vim_context_feed_keys(ctx, "u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "first line\nsecond line") == 0);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_ex_substitute_case_insensitive_and_ranges(void) {
    const char *text = "Foo foo FOO\nBar bar BAR\nBaz baz BAZ\nQux qux QUX";
    VimContextRef ctx = vim_context_create(text);
    assert(ctx != NULL);

    // 1. Case-insensitive substitution with 'i' flag
    vim_context_execute_ex(ctx, ":%s/foo/REP/gi");
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strncmp(ser, "REP REP REP\n", 12) == 0);
    free(ser);

    // 2. Case-sensitive substitution with 'I' flag
    vim_context_execute_ex(ctx, ":%s/BAR/DONE/gI");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "Bar bar DONE") != NULL);
    free(ser);

    // 3. Explicit line range :3,4s/.../g
    vim_context_execute_ex(ctx, ":3,4s/a/X/g");
    ser = vim_context_serialize_buffer(ctx, NULL);
    // Line 2 (Bar bar DONE) should still have 'a'
    assert(strstr(ser, "Bar bar DONE") != NULL);
    // Line 3 (Baz baz BAZ) should have lowercase 'a' replaced with 'X'
    assert(strstr(ser, "BXz bXz BAZ") != NULL);
    free(ser);

    // 4. Visual selection range :'<,'>s/.../g
    vim_context_set_cursor(ctx, 4, 1);
    vim_context_set_visual_anchor(ctx, 4, 1);
    vim_context_execute_ex(ctx, ":'<,'>s/qux/FOUND/g");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "Qux FOUND QUX") != NULL);
    free(ser);

    // 5. Current line substitution :s/find/rep/ (without % or ranges)
    vim_context_set_cursor(ctx, 3, 1);
    vim_context_execute_ex(ctx, ":s/BAZ/UPDATED/");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "BXz bXz UPDATED") != NULL);
    // Line 4 should NOT be affected
    assert(strstr(ser, "Qux FOUND QUX") != NULL);
    free(ser);

    // 6. Explicit range substitution :1,2s/find/rep/g
    vim_context_execute_ex(ctx, ":1,2s/REP/FINAL/g");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "FINAL FINAL FINAL") != NULL);
    free(ser);

    // Undo step 6 reverts "FINAL" back to "REP"
    vim_context_execute_ex(ctx, ":u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "REP REP REP") != NULL);
    free(ser);

    // Undo step 5 reverts ":s/BAZ/UPDATED/"
    vim_context_execute_ex(ctx, ":u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "BXz bXz BAZ") != NULL);
    free(ser);

    // Undo step 4 reverts visual range substitution on line 4
    vim_context_execute_ex(ctx, ":u");
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strstr(ser, "Qux qux QUX") != NULL);
    free(ser);

    vim_context_destroy(ctx);
}

static void test_word_end_operators_de_ce_ye(void) {
    // 1. 'de' deletes to the end of the current word (inclusive) and leaves cursor at current character
    VimContextRef ctx = vim_context_create("apple banana cherry");
    assert(ctx != NULL);
    vim_context_set_cursor(ctx, 1, 1);
    vim_context_feed_keys(ctx, "d");
    vim_context_feed_keys(ctx, "e");
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, " banana cherry") == 0);
    free(ser);
    VimBytePos pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1);
    assert(pos.byteCol == 1);

    // Test 'de' from middle of word
    vim_context_feed_keys(ctx, "l"); // move to 'b' of banana (col 2)
    vim_context_feed_keys(ctx, "l"); // move to 'a' of banana (col 3)
    vim_context_feed_keys(ctx, "d");
    vim_context_feed_keys(ctx, "e"); // delete "anana"
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, " b cherry") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx);
    assert(pos.line == 1);
    assert(pos.byteCol == 3); // cursor at ' ' after 'b'
    vim_context_destroy(ctx);

    // 2. '2de' deletes to end of 2nd word
    VimContextRef ctx2 = vim_context_create("one two three four");
    assert(ctx2 != NULL);
    vim_context_set_cursor(ctx2, 1, 1);
    vim_context_feed_keys(ctx2, "2");
    vim_context_feed_keys(ctx2, "d");
    vim_context_feed_keys(ctx2, "e");
    ser = vim_context_serialize_buffer(ctx2, NULL);
    assert(strcmp(ser, " three four") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx2);
    assert(pos.line == 1);
    assert(pos.byteCol == 1);
    vim_context_destroy(ctx2);

    // 3. 'ce' deletes to end of word and enters Insert mode
    VimContextRef ctx3 = vim_context_create("first second third");
    assert(ctx3 != NULL);
    vim_context_set_cursor(ctx3, 1, 1);
    vim_context_feed_keys(ctx3, "c");
    vim_context_feed_keys(ctx3, "e");
    assert(vim_context_get_mode(ctx3) == VIM_MODE_INSERT);
    ser = vim_context_serialize_buffer(ctx3, NULL);
    assert(strcmp(ser, " second third") == 0);
    free(ser);
    // Type replacement text and exit insert mode with ESC
    vim_context_feed_keys(ctx3, "replaced\x1b");
    assert(vim_context_get_mode(ctx3) == VIM_MODE_NORMAL);
    ser = vim_context_serialize_buffer(ctx3, NULL);
    assert(strcmp(ser, "replaced second third") == 0);
    free(ser);
    vim_context_destroy(ctx3);

    // 4. 'ye' yanks to end of word and pastes with 'p'
    VimContextRef ctx4 = vim_context_create("lorem ipsum dolor");
    assert(ctx4 != NULL);
    vim_context_set_cursor(ctx4, 1, 1);
    vim_context_feed_keys(ctx4, "y");
    vim_context_feed_keys(ctx4, "e");
    // Verify buffer untouched
    ser = vim_context_serialize_buffer(ctx4, NULL);
    assert(strcmp(ser, "lorem ipsum dolor") == 0);
    free(ser);
    // Paste at end of line ($p)
    vim_context_feed_keys(ctx4, "$");
    vim_context_feed_keys(ctx4, "p");
    ser = vim_context_serialize_buffer(ctx4, NULL);
    assert(strcmp(ser, "lorem ipsum dolorlorem") == 0);
    free(ser);
    vim_context_destroy(ctx4);

    // 5. Single cohesive undo restores the buffer
    // For 'de':
    VimContextRef ctx5 = vim_context_create("quick brown fox");
    assert(ctx5 != NULL);
    vim_context_set_cursor(ctx5, 1, 1);
    vim_context_feed_keys(ctx5, "d");
    vim_context_feed_keys(ctx5, "e");
    ser = vim_context_serialize_buffer(ctx5, NULL);
    assert(strcmp(ser, " brown fox") == 0);
    free(ser);
    vim_context_feed_keys(ctx5, "u");
    ser = vim_context_serialize_buffer(ctx5, NULL);
    assert(strcmp(ser, "quick brown fox") == 0);
    free(ser);

    // For 'ce' with multiple typed characters in insert mode:
    vim_context_set_cursor(ctx5, 1, 1);
    vim_context_feed_keys(ctx5, "c");
    vim_context_feed_keys(ctx5, "e");
    vim_context_feed_keys(ctx5, "slow\x1b");
    ser = vim_context_serialize_buffer(ctx5, NULL);
    assert(strcmp(ser, "slow brown fox") == 0);
    free(ser);
    // Single cohesive undo should revert entire 'ce' + typed text in one step
    vim_context_feed_keys(ctx5, "u");
    ser = vim_context_serialize_buffer(ctx5, NULL);
    assert(strcmp(ser, "quick brown fox") == 0);
    free(ser);
    vim_context_destroy(ctx5);
}

static void test_word_end_operators_advanced_coverage(void) {
    // A. Empty line behavior for de, ye, ce
    VimContextRef ctx = vim_context_create("");
    assert(ctx != NULL);
    assert(!vim_context_is_dirty(ctx));

    // Preset yank buffer by yanking something
    VimContextRef ctx_yank = vim_context_create("preserved");
    vim_context_feed_keys(ctx_yank, "y");
    vim_context_feed_keys(ctx_yank, "e");
    vim_context_destroy(ctx_yank);

    // de on empty line: strict no-op, clean buffer remains clean
    vim_context_feed_keys(ctx, "d");
    vim_context_feed_keys(ctx, "e");
    assert(!vim_context_is_dirty(ctx));
    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "") == 0);
    free(ser);

    // ye on empty line: strict no-op, clean buffer remains clean
    vim_context_feed_keys(ctx, "y");
    vim_context_feed_keys(ctx, "e");
    assert(!vim_context_is_dirty(ctx));

    // ce on empty line: enters insert mode, clean buffer remains clean before typing
    vim_context_feed_keys(ctx, "c");
    vim_context_feed_keys(ctx, "e");
    assert(vim_context_get_mode(ctx) == VIM_MODE_INSERT);
    assert(!vim_context_is_dirty(ctx));
    vim_context_feed_keys(ctx, "\x1b"); // exit insert mode
    assert(vim_context_get_mode(ctx) == VIM_MODE_NORMAL);
    assert(!vim_context_is_dirty(ctx));
    vim_context_destroy(ctx);

    // B. EOL boundary: cursor on final char 'o' in "hello" -> deletes 'o', leaving "hell", cursor clamped
    VimContextRef ctx_eol = vim_context_create("hello");
    vim_context_set_cursor(ctx_eol, 1, 5); // on 'o'
    vim_context_feed_keys(ctx_eol, "d");
    vim_context_feed_keys(ctx_eol, "e");
    ser = vim_context_serialize_buffer(ctx_eol, NULL);
    assert(strcmp(ser, "hell") == 0);
    free(ser);
    VimBytePos pos = vim_context_get_cursor(ctx_eol);
    assert(pos.line == 1 && pos.byteCol == 4); // clamped to 'l'
    vim_context_destroy(ctx_eol);

    // C. Single-character words: "a b c"
    VimContextRef ctx_single = vim_context_create("a b c");
    vim_context_set_cursor(ctx_single, 1, 1);
    vim_context_feed_keys(ctx_single, "y");
    vim_context_feed_keys(ctx_single, "e"); // yanks "a"
    vim_context_feed_keys(ctx_single, "$");
    vim_context_feed_keys(ctx_single, "p"); // pastes "a" at end
    ser = vim_context_serialize_buffer(ctx_single, NULL);
    assert(strcmp(ser, "a b ca") == 0);
    free(ser);

    vim_context_set_cursor(ctx_single, 1, 1);
    vim_context_feed_keys(ctx_single, "d");
    vim_context_feed_keys(ctx_single, "e"); // deletes "a"
    ser = vim_context_serialize_buffer(ctx_single, NULL);
    assert(strcmp(ser, " b ca") == 0);
    free(ser);

    vim_context_set_cursor(ctx_single, 1, 2); // on 'b'
    vim_context_feed_keys(ctx_single, "c");
    vim_context_feed_keys(ctx_single, "e"); // ce deletes 'b'
    vim_context_feed_keys(ctx_single, "z\x1b");
    ser = vim_context_serialize_buffer(ctx_single, NULL);
    assert(strcmp(ser, " z ca") == 0);
    free(ser);
    vim_context_destroy(ctx_single);

    // D. Punctuation transitions: "foo.bar_baz"
    VimContextRef ctx_punct = vim_context_create("foo.bar_baz");
    vim_context_set_cursor(ctx_punct, 1, 1);
    vim_context_feed_keys(ctx_punct, "d");
    vim_context_feed_keys(ctx_punct, "e"); // deletes "foo"
    ser = vim_context_serialize_buffer(ctx_punct, NULL);
    assert(strcmp(ser, ".bar_baz") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx_punct);
    assert(pos.line == 1 && pos.byteCol == 1); // at '.'

    vim_context_feed_keys(ctx_punct, "d");
    vim_context_feed_keys(ctx_punct, "e"); // deletes "."
    ser = vim_context_serialize_buffer(ctx_punct, NULL);
    assert(strcmp(ser, "bar_baz") == 0);
    free(ser);
    pos = vim_context_get_cursor(ctx_punct);
    assert(pos.line == 1 && pos.byteCol == 1); // at 'b'
    vim_context_destroy(ctx_punct);

    // E. Count multipliers: explicit assertions for 2ce and 2ye
    // 2ce:
    VimContextRef ctx_count = vim_context_create("one two three");
    vim_context_set_cursor(ctx_count, 1, 1);
    vim_context_feed_keys(ctx_count, "2");
    vim_context_feed_keys(ctx_count, "c");
    vim_context_feed_keys(ctx_count, "e");
    assert(vim_context_get_mode(ctx_count) == VIM_MODE_INSERT);
    ser = vim_context_serialize_buffer(ctx_count, NULL);
    assert(strcmp(ser, " three") == 0);
    free(ser);
    vim_context_feed_keys(ctx_count, "done\x1b");
    ser = vim_context_serialize_buffer(ctx_count, NULL);
    assert(strcmp(ser, "done three") == 0);
    free(ser);
    vim_context_destroy(ctx_count);

    // 2ye:
    VimContextRef ctx_2ye = vim_context_create("alpha beta gamma");
    vim_context_set_cursor(ctx_2ye, 1, 1);
    vim_context_feed_keys(ctx_2ye, "2");
    vim_context_feed_keys(ctx_2ye, "y");
    vim_context_feed_keys(ctx_2ye, "e");
    ser = vim_context_serialize_buffer(ctx_2ye, NULL);
    assert(strcmp(ser, "alpha beta gamma") == 0);
    free(ser);
    vim_context_feed_keys(ctx_2ye, "$");
    vim_context_feed_keys(ctx_2ye, "p");
    ser = vim_context_serialize_buffer(ctx_2ye, NULL);
    assert(strcmp(ser, "alpha beta gammaalpha beta") == 0);
    free(ser);
    vim_context_destroy(ctx_2ye);
}

typedef struct {
    int32_t startLine;
    int32_t deletedCount;
    int32_t addedCount;
    int callCount;
} TestInsertTextDeltaState;

static void test_insert_text_delta_cb(int32_t startLine, int32_t deletedCount, const char **newLines, int32_t addedCount, void *userInfo) {
    (void)newLines;
    TestInsertTextDeltaState *state = (TestInsertTextDeltaState *)userInfo;
    state->startLine = startLine;
    state->deletedCount = deletedCount;
    state->addedCount = addedCount;
    state->callCount++;
}

static void test_insert_text_batched(void) {
    VimContextRef ctx = vim_context_create("hello world");
    assert(ctx != NULL);
    TestInsertTextDeltaState state = {0, 0, 0, 0};
    vim_context_set_delta_callback(ctx, test_insert_text_delta_cb, &state);

    // 1. Single line batched insert in insert mode
    vim_context_feed_keys(ctx, "i");
    vim_context_set_cursor(ctx, 1, 6);
    vim_context_insert_text(ctx, " beautiful");
    assert(state.callCount == 1);
    assert(state.startLine == 1);
    assert(state.deletedCount == 1);
    assert(state.addedCount == 1);

    char *ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "hello beautiful world") == 0);
    free(ser);

    // 2. Multiline batched insert
    state.callCount = 0;
    vim_context_insert_text(ctx, "\nnew line 2\nnew line 3\n");
    assert(state.callCount == 1);
    assert(state.startLine == 1);
    assert(state.deletedCount == 1);
    assert(state.addedCount == 4);

    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "hello beautiful\nnew line 2\nnew line 3\n world") == 0);
    free(ser);

    // 3. Undo restores previous state
    bool undone = vim_context_undo(ctx);
    assert(undone == true);
    ser = vim_context_serialize_buffer(ctx, NULL);
    assert(strcmp(ser, "hello world") == 0);
    free(ser);

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
    RUN_TEST(test_set_cursor);
    RUN_TEST(test_gg_motion_streaming);
    RUN_TEST(test_G_motion);
    RUN_TEST(test_visual_text_objects);
    RUN_TEST(test_operator_inner_quotes);
    RUN_TEST(test_operator_inner_brackets);
    RUN_TEST(test_operator_inner_multiline);
    RUN_TEST(test_operator_inner_undo_redo);
    RUN_TEST(test_operator_inner_esc_cancellation);
    RUN_TEST(test_search_forward_n_N);
    RUN_TEST(test_ex_commands_streaming_and_ZZ);
    RUN_TEST(test_navigation_motions_and_counts);
    RUN_TEST(test_find_repeat_semicolon_comma);
    RUN_TEST(test_operator_mutations);
    RUN_TEST(test_word_end_operators_de_ce_ye);
    RUN_TEST(test_word_end_operators_advanced_coverage);
    RUN_TEST(test_visual_selection_and_operators);
    RUN_TEST(test_visual_motions_word_and_find);
    RUN_TEST(test_esc_cancellation);
    RUN_TEST(test_yank_callback_and_clipboard);
    RUN_TEST(test_undo_redo_basic);
    RUN_TEST(test_undo_redo_sequential);
    RUN_TEST(test_undo_insert_session_cohesive);
    RUN_TEST(test_undo_ex_commands);
    RUN_TEST(test_undo_tree_truncation_on_new_edit);
    RUN_TEST(test_undo_cap_levels);
    RUN_TEST(test_sort_alphabetical);
    RUN_TEST(test_sort_reverse);
    RUN_TEST(test_sort_case_insensitive);
    RUN_TEST(test_sort_unique);
    RUN_TEST(test_sort_numeric);
    RUN_TEST(test_sort_range);
    RUN_TEST(test_sort_undo_redo);
    RUN_TEST(test_count_accumulator);
    RUN_TEST(test_replace_mode_overwrite_and_backspace_restore);
    RUN_TEST(test_replace_mode_extend_line_and_esc_undo);
    RUN_TEST(test_single_char_replace_multibyte);
    RUN_TEST(test_visual_selection_replace);
    RUN_TEST(test_substitute_line_S);
    RUN_TEST(test_ex_substitute_case_insensitive_and_ranges);
    RUN_TEST(test_insert_text_batched);
    printf("Result: %d/%d tests passed.\n", g_tests_passed, g_tests_run);
    return (g_tests_passed == g_tests_run) ? 0 : 1;
}
