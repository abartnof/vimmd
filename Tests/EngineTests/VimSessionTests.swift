import Foundation
import Engine
import CBridge

func runTest(name: String, test: () throws -> Void) -> Bool {
    print("[RUN ] \(name)")
    do {
        try test()
        print("[PASS] \(name)")
        return true
    } catch {
        print("[FAIL] \(name): \(error)")
        return false
    }
}

func testVimSessionInitialization() throws {
    let initial = "# VimMD Heading\nLine two content."
    let session = VimSession(initialText: initial)
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected VimSession to be valid upon initialization"])
    }
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected default mode to be VIM_MODE_NORMAL"])
    }
    guard session.cursor.line == 1 && session.cursor.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at (1, 1)"])
    }
    guard !session.isDirty else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected session not to be dirty initially"])
    }
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Serialized buffer does not match initial text"])
    }
}

func testVimSessionEmptyInitialization() throws {
    let session = VimSession(initialText: "")
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected empty VimSession to be valid"])
    }
    guard session.serializeBuffer() == "" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected empty buffer string"])
    }
}

func testVimSessionClearDirty() throws {
    let session = VimSession(initialText: "Testing dirty flag")
    session.clearDirty()
    guard !session.isDirty else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected clean session after clearDirty"])
    }
}

func testVimSessionFeedKeysAndExecuteEx() throws {
    let session = VimSession(initialText: "Buffer before keys")
    // feedKeys and executeEx must be robust, non-crashing methods
    session.feedKeys("gg")
    session.feedKeys("i")
    session.executeEx(":set number")
    session.executeEx(":w")
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session should remain valid after feedKeys and executeEx"])
    }
}

func testVimSessionMultibyteUnicode() throws {
    let multibyte = "Hello 🚀 世界! Testing emojis 🌍 and accents é, ü, ñ."
    let session = VimSession(initialText: multibyte)
    guard session.serializeBuffer() == multibyte else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unicode round-trip serialization failed"])
    }
}

func testVimSessionMultiSessionIsolation() throws {
    let text1 = "Document 1: Swift Engine"
    let text2 = "Document 2: Rust / C Engine with 🚀"
    let session1 = VimSession(initialText: text1)
    let session2 = VimSession(initialText: text2)

    guard session1.serializeBuffer() == text1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session 1 buffer mismatch"])
    }
    guard session2.serializeBuffer() == text2 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session 2 buffer mismatch"])
    }

    session1.clearDirty()
    guard !session1.isDirty && !session2.isDirty else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Isolation failure on dirty flag"])
    }
}

func testVimSessionLineDeltaCallback() throws {
    let session = VimSession(initialText: "Original line 1\nOriginal line 2")
    var receivedStartLine: Int32 = -1
    var receivedDeletedCount: Int32 = -1
    var receivedLines: [String] = []

    session.onLineDelta = { startLine, deletedCount, newLines in
        receivedStartLine = startLine
        receivedDeletedCount = deletedCount
        receivedLines = newLines
    }

    session.triggerLineDelta(startLine: 1, deletedCount: 1, newLines: ["Replaced line 1", "Appended line 1.5"])

    guard receivedStartLine == 1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected startLine 1, got \(receivedStartLine)"])
    }
    guard receivedDeletedCount == 1 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected deletedCount 1, got \(receivedDeletedCount)"])
    }
    guard receivedLines == ["Replaced line 1", "Appended line 1.5"] else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected replacement lines, got \(receivedLines)"])
    }
}

func testVimSessionLoopStability() throws {
    for i in 0..<500 {
        let text = "Iteration \(i) buffer content"
        let session = VimSession(initialText: text)
        guard session.isValid else {
            throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed creating session at iteration \(i)"])
        }
    }
}

func testVimSessionModalTransitions() throws {
    let session = VimSession(initialText: "Normal mode start")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected initial mode to be NORMAL"])
    }

    session.feedKeys("i")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected mode to be INSERT after 'i'"])
    }

    session.feedKeys("\u{1b}")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected mode to be NORMAL after Esc"])
    }

    session.feedKeys("v")
    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected mode to be VISUAL after 'v'"])
    }

    session.feedKeys("\u{1b}")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected mode to be NORMAL after Esc"])
    }
}

func testVimSessionCursorOffsetSync() throws {
    let session = VimSession(initialText: "Line 1 🚀\nLine 2 Content")
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial cursor pos mismatch"])
    }
    guard session.cursorUtf16Offset == 0 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial cursor UTF-16 offset mismatch"])
    }

    // Move to end of line: '$'
    session.feedKeys("$")
    // In Normal mode, cursor rests ON the last character '🚀' (starts at UTF-16 offset 7)
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol >= 8 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cursor did not move to end of line, got \(session.cursorPosition)"])
    }
    guard session.cursorUtf16Offset == 7 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected cursorUtf16Offset 7 on '🚀', got \(session.cursorUtf16Offset)"])
    }

    // Entering insert append ('a') moves cursor to terminal position after '🚀' (offset 9)
    session.feedKeys("a")
    guard session.cursorUtf16Offset == 9 else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected cursorUtf16Offset 9 in insert append, got \(session.cursorUtf16Offset)"])
    }
    session.feedKeys("\u{1b}")

    // Move down to Line 2: 'j'
    session.feedKeys("j")
    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected cursor on line 2, got \(session.cursorPosition)"])
    }
}

func testVimSessionExSubstitutionAndDeltaSync() throws {
    let session = VimSession(initialText: "Old title\nOld subtitle")
    var deltaReceived = false

    session.onLineDelta = { startLine, deletedCount, newLines in
        deltaReceived = true
    }

    session.executeEx(":%s/Old/New/g")
    guard session.serializeBuffer() == "New title\nNew subtitle" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ex substitution buffer mismatch: \(session.serializeBuffer())"])
    }
    guard deltaReceived else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected delta callback to be dispatched"])
    }
    guard session.lineIndexTable.lineCount == 2 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable lineCount mismatch"])
    }
    let rangeLine1 = session.lineIndexTable.characterRange(startLine: 1, count: 1)
    guard rangeLine1.length == "New title".utf16.count else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable character range not updated, expected 9, got \(rangeLine1.length)"])
    }
}

func testVimSessionQuitState() throws {
    let session = VimSession(initialText: "Quit test")
    guard session.shouldQuit == false else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "shouldQuit should be false initially"])
    }
    session.executeEx(":q")
    guard session.shouldQuit == true else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "shouldQuit should be true after :q"])
    }
}

func testVimSessionInsertModeLineMutations() throws {
    let session = VimSession(initialText: "Hello World")
    guard session.lineIndexTable.lineCount == 1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial lineCount mismatch"])
    }

    // 1. Newline splitting at cursor in insert mode
    // Move to col 6 (' '), enter insert mode, insert '\n', return to normal
    session.feedKeys("0lllll") // moves to col 6
    session.feedKeys("i\n\u{1b}")

    guard session.serializeBuffer() == "Hello\n World" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Split buffer mismatch: \(session.serializeBuffer())"])
    }
    guard session.lineIndexTable.lineCount == 2 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable lineCount should be 2, got \(session.lineIndexTable.lineCount)"])
    }
    guard session.lineIndexTable.characterRange(startLine: 1, count: 1).length == 5 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Line 1 length mismatch after split"])
    }

    // 2. Open line below ('o')
    session.feedKeys("oLine Two\u{1b}")
    guard session.lineIndexTable.lineCount == 3 else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable lineCount should be 3 after 'o', got \(session.lineIndexTable.lineCount)"])
    }

    // 3. Open line above ('O')
    session.feedKeys("gg")
    session.feedKeys("OHeader\u{1b}")
    guard session.lineIndexTable.lineCount == 4 else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable lineCount should be 4 after 'O', got \(session.lineIndexTable.lineCount)"])
    }
    guard session.lineIndexTable.characterRange(startLine: 1, count: 1).length == "Header".utf16.count else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Top header length mismatch"])
    }
}

func testVimSessionQuitVariations() throws {
    // 1. Test :wq
    let s1 = VimSession(initialText: "Session 1")
    s1.feedKeys("iEdit\u{1b}")
    guard s1.isDirty else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected s1 to be dirty"])
    }
    s1.executeEx(":wq")
    guard s1.shouldQuit && s1.pendingAction == VIM_ACTION_SAVE_AND_QUIT else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: ":wq should set shouldQuit and VIM_ACTION_SAVE_AND_QUIT"])
    }

    // 2. Test ZZ
    let s2 = VimSession(initialText: "Session 2")
    s2.feedKeys("iEdit\u{1b}")
    s2.feedKeys("ZZ")
    guard s2.shouldQuit && s2.pendingAction == VIM_ACTION_SAVE_AND_QUIT else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "ZZ should set shouldQuit and VIM_ACTION_SAVE_AND_QUIT"])
    }

    // 3. Test ZQ
    let s3 = VimSession(initialText: "Session 3")
    s3.feedKeys("iEdit\u{1b}")
    s3.feedKeys("ZQ")
    guard s3.shouldQuit && s3.isDirty else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "ZQ should set shouldQuit and preserve dirty"])
    }
}

func testVimSessionSystemActionsAndErrors() throws {
    let session = VimSession(initialText: "System Actions Test")

    var dispatchedActions: [VimSystemAction] = []
    session.onSystemAction = { action in
        dispatchedActions.append(action)
    }

    // 1. :w sets VIM_ACTION_SAVE and calls onSystemAction
    session.executeEx("w")
    guard session.pendingAction == VIM_ACTION_SAVE else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected pendingAction VIM_ACTION_SAVE, got \(session.pendingAction)"])
    }
    guard dispatchedActions.count == 1 && dispatchedActions.first == VIM_ACTION_SAVE else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected dispatched action VIM_ACTION_SAVE"])
    }

    session.clearPendingAction()
    guard session.pendingAction == VIM_ACTION_NONE else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected VIM_ACTION_NONE after clearPendingAction"])
    }

    // 2. :q on dirty session
    session.feedKeys("iModified\u{1b}")
    dispatchedActions.removeAll()
    session.executeEx("q")
    guard session.pendingAction == VIM_ACTION_NONE else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected no action on failed :q"])
    }
    guard let err = session.lastError, err.contains("E37") else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected E37 error on :q with dirty document"])
    }
    guard dispatchedActions.isEmpty else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected no dispatched actions on refused quit"])
    }

    // 3. :wq via feedKeys interactive
    session.feedKeys(":wq\r")
    guard dispatchedActions.contains(VIM_ACTION_SAVE_AND_QUIT) else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected VIM_ACTION_SAVE_AND_QUIT from :wq"])
    }
}

func testVimSessionSetCursorAndModeNotifications() throws {
    let session = VimSession(initialText: "First line\nSecond line\nThird line")

    // 1. setCursor
    session.setCursor(line: 2, byteCol: 4)
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 4 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cursor position mismatch after setCursor"])
    }

    // 2. Mode string and onModeChanged
    guard session.modeString == "NORMAL" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial modeString should be NORMAL"])
    }

    var recordedModes: [VimEngineMode] = []
    session.onModeChanged = { mode in
        recordedModes.append(mode)
    }

    session.feedKeys("i")
    guard session.modeString == "INSERT" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected modeString INSERT after 'i'"])
    }

    session.feedKeys("\u{1b}")
    guard session.modeString == "NORMAL" else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected modeString NORMAL after <Esc>"])
    }

    guard recordedModes == [VIM_MODE_INSERT, VIM_MODE_NORMAL] else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "recordedModes mismatch: \(recordedModes)"])
    }
}

print("=== Engine Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testVimSessionInitialization", testVimSessionInitialization),
    ("testVimSessionEmptyInitialization", testVimSessionEmptyInitialization),
    ("testVimSessionClearDirty", testVimSessionClearDirty),
    ("testVimSessionFeedKeysAndExecuteEx", testVimSessionFeedKeysAndExecuteEx),
    ("testVimSessionMultibyteUnicode", testVimSessionMultibyteUnicode),
    ("testVimSessionMultiSessionIsolation", testVimSessionMultiSessionIsolation),
    ("testVimSessionLineDeltaCallback", testVimSessionLineDeltaCallback),
    ("testVimSessionLoopStability", testVimSessionLoopStability),
    ("testVimSessionModalTransitions", testVimSessionModalTransitions),
    ("testVimSessionCursorOffsetSync", testVimSessionCursorOffsetSync),
    ("testVimSessionExSubstitutionAndDeltaSync", testVimSessionExSubstitutionAndDeltaSync),
    ("testVimSessionQuitState", testVimSessionQuitState),
    ("testVimSessionInsertModeLineMutations", testVimSessionInsertModeLineMutations),
    ("testVimSessionQuitVariations", testVimSessionQuitVariations),
    ("testVimSessionSystemActionsAndErrors", testVimSessionSystemActionsAndErrors),
    ("testVimSessionSetCursorAndModeNotifications", testVimSessionSetCursorAndModeNotifications)
]

for (name, test) in tests {
    total += 1
    if runTest(name: name, test: test) {
        passed += 1
    }
}

print("Result: \(passed)/\(total) tests passed.")
if passed != total {
    exit(1)
}
