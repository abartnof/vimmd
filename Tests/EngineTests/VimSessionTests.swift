import Foundation
import AppKit
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

func testVimSessionStreamingGGAndG() throws {
    let session = VimSession(initialText: "First line\nSecond line\n    Third line with spaces")
    session.setCursor(line: 3, byteCol: 2)

    // Feed first 'g'
    session.feedKeys("g")
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 2 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pending 'g' should not move cursor immediately"])
    }

    // Feed second 'g'
    session.feedKeys("g")
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "'gg' should move cursor to line 1, col 1, got \(session.cursorPosition)"])
    }

    // Feed 'G': should move to line 3, first non-blank col 5
    session.feedKeys("G")
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 5 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "'G' should move cursor to last line first non-blank, got \(session.cursorPosition)"])
    }
}

func testVimSessionVisualTextObjects() throws {
    // 1. vi'
    let s1 = VimSession(initialText: "let key = 'secret_value';")
    s1.setCursor(line: 1, byteCol: 15)
    s1.feedKeys("v")
    s1.feedKeys("i")
    s1.feedKeys("'")
    guard s1.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected VISUAL mode after vi'"])
    }
    guard let r1 = s1.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil visualSelectionRange"])
    }
    let sub1 = (s1.serializeBuffer() as NSString).substring(with: r1)
    guard sub1 == "secret_value" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "vi' expected 'secret_value', got '\(sub1)'"])
    }

    // 2. vi"
    let s2 = VimSession(initialText: "let title = \"Super VimMD\";")
    s2.setCursor(line: 1, byteCol: 16)
    s2.feedKeys("v")
    s2.feedKeys("i")
    s2.feedKeys("\"")
    guard let r2 = s2.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil visualSelectionRange"])
    }
    let sub2 = (s2.serializeBuffer() as NSString).substring(with: r2)
    guard sub2 == "Super VimMD" else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "vi\" expected 'Super VimMD', got '\(sub2)'"])
    }

    // 3. vi( and vib
    let s3 = VimSession(initialText: "print(hello, world)")
    s3.setCursor(line: 1, byteCol: 10)
    s3.feedKeys("v")
    s3.feedKeys("i")
    s3.feedKeys("(")
    guard let r3 = s3.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil visualSelectionRange"])
    }
    let sub3 = (s3.serializeBuffer() as NSString).substring(with: r3)
    guard sub3 == "hello, world" else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "vi( expected 'hello, world', got '\(sub3)'"])
    }

    s3.feedKeys("\u{1b}")
    s3.setCursor(line: 1, byteCol: 10)
    s3.feedKeys("v")
    s3.feedKeys("i")
    s3.feedKeys("b")
    guard let r3b = s3.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil visualSelectionRange"])
    }
    guard (s3.serializeBuffer() as NSString).substring(with: r3b) == "hello, world" else {
        throw NSError(domain: "EngineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "vib expected 'hello, world'"])
    }

    // 4. vi[
    let s4 = VimSession(initialText: "items = [first, second]")
    s4.setCursor(line: 1, byteCol: 12)
    s4.feedKeys("v")
    s4.feedKeys("i")
    s4.feedKeys("[")
    guard let r4 = s4.visualSelectionRange, (s4.serializeBuffer() as NSString).substring(with: r4) == "first, second" else {
        throw NSError(domain: "EngineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "vi[ mismatch"])
    }

    // 5. vi<
    let s5 = VimSession(initialText: "Array<String>")
    s5.setCursor(line: 1, byteCol: 8)
    s5.feedKeys("v")
    s5.feedKeys("i")
    s5.feedKeys("<")
    guard let r5 = s5.visualSelectionRange, (s5.serializeBuffer() as NSString).substring(with: r5) == "String" else {
        throw NSError(domain: "EngineTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "vi< mismatch"])
    }

    // 6. vi{ and viB
    let s6 = VimSession(initialText: "function() { doTask(); }")
    s6.setCursor(line: 1, byteCol: 16)
    s6.feedKeys("v")
    s6.feedKeys("i")
    s6.feedKeys("{")
    guard let r6 = s6.visualSelectionRange, (s6.serializeBuffer() as NSString).substring(with: r6) == " doTask(); " else {
        throw NSError(domain: "EngineTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "vi{ mismatch"])
    }

    s6.feedKeys("\u{1b}")
    s6.setCursor(line: 1, byteCol: 16)
    s6.feedKeys("v")
    s6.feedKeys("i")
    s6.feedKeys("B")
    guard let r6B = s6.visualSelectionRange, (s6.serializeBuffer() as NSString).substring(with: r6B) == " doTask(); " else {
        throw NSError(domain: "EngineTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "viB mismatch"])
    }
}

func testVimSessionBackwardVisualSelectionAndEmptyObjects() throws {
    // 1. Backward visual motions: vb, vh, v0
    let session = VimSession(initialText: "quick brown fox jumps")
    session.setCursor(line: 1, byteCol: 13) // on 'f' in 'fox'
    session.feedKeys("v")
    session.feedKeys("b") // backward word to 'b' in 'brown' (byteCol 7)
    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected VISUAL mode"])
    }
    guard let rB = session.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil visualSelectionRange for vb"])
    }
    let subB = (session.serializeBuffer() as NSString).substring(with: rB)
    guard subB == "brown f" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "vb expected 'brown f', got '\(subB)'"])
    }

    // 2. vh: single character backward step (anchor.byteCol == cursor.byteCol + 1)
    session.feedKeys("\u{1b}")
    session.setCursor(line: 1, byteCol: 3) // on 'i' in 'quick'
    session.feedKeys("v")
    session.feedKeys("h") // to 'u' (byteCol 2)
    guard let rH = session.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil range for vh"])
    }
    let subH = (session.serializeBuffer() as NSString).substring(with: rH)
    guard subH == "ui" else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "vh expected 'ui', got '\(subH)'"])
    }

    // 3. v0: line start
    session.feedKeys("\u{1b}")
    session.setCursor(line: 1, byteCol: 10) // on 'r' in 'brown'
    session.feedKeys("v")
    session.feedKeys("0")
    guard let r0 = session.visualSelectionRange else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil range for v0"])
    }
    let sub0 = (session.serializeBuffer() as NSString).substring(with: r0)
    guard sub0 == "quick brow" else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "v0 expected 'quick brow', got '\(sub0)'"])
    }

    // 4. Empty inner text objects: vi", vi', vi[
    let emptySession = VimSession(initialText: "let s = \"\"; let c = ''; let a = [];")
    emptySession.setCursor(line: 1, byteCol: 9) // on opening '"'
    emptySession.feedKeys("v")
    emptySession.feedKeys("i")
    emptySession.feedKeys("\"")
    guard emptySession.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected VISUAL mode after vi\" on empty string"])
    }
    guard emptySession.isEmptyVisualSelection else {
        throw NSError(domain: "EngineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected isEmptyVisualSelection == true"])
    }
    guard let rEmpty = emptySession.visualSelectionRange, rEmpty.length == 0 else {
        throw NSError(domain: "EngineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected 0-length visual selection for vi\" on empty quotes"])
    }
    // Delete on empty inner quotes does not delete delimiters
    emptySession.feedKeys("d")
    guard emptySession.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected NORMAL mode after delete"])
    }
    guard emptySession.serializeBuffer() == "let s = \"\"; let c = ''; let a = [];" else {
        throw NSError(domain: "EngineTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Empty quote delete modified text: '\(emptySession.serializeBuffer())'"])
    }

    // vi' on empty single quotes
    emptySession.setCursor(line: 1, byteCol: 21) // on opening '\''
    emptySession.feedKeys("vi'")
    guard emptySession.isEmptyVisualSelection && emptySession.visualSelectionRange?.length == 0 else {
        throw NSError(domain: "EngineTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected 0-length selection for vi' on empty single quotes"])
    }
    emptySession.feedKeys("\u{1b}")

    // vi[ on empty brackets
    emptySession.setCursor(line: 1, byteCol: 34) // on opening '['
    emptySession.feedKeys("vi[")
    guard emptySession.isEmptyVisualSelection && emptySession.visualSelectionRange?.length == 0 else {
        throw NSError(domain: "EngineTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected 0-length selection for vi[ on empty brackets"])
    }
    emptySession.feedKeys("\u{1b}")
}

func testVimSessionSearchAndNavigation() throws {
    let session = VimSession(initialText: "target one\nsecond target\ntarget three")

    // Stream /target\r
    let searchInput = "/target\r"
    for ch in searchInput {
        session.feedKeys(String(ch))
    }

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mode should return to NORMAL after <CR>"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Search match 1 mismatch: \(session.cursorPosition)"])
    }
    guard session.lastSearchPattern == "target" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "lastSearchPattern mismatch: \(String(describing: session.lastSearchPattern))"])
    }

    // n -> next match at line 2, col 8
    session.searchNext()
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 8 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "n match 2 mismatch: \(session.cursorPosition)"])
    }

    // n -> next match at line 3, col 1
    session.searchNext()
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "n match 3 mismatch: \(session.cursorPosition)"])
    }

    // n -> wrap around to line 1, col 1
    session.searchNext()
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "n wrap mismatch: \(session.cursorPosition)"])
    }

    // N -> backward to line 3, col 1
    session.searchPrevious()
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "N backwards mismatch: \(session.cursorPosition)"])
    }
}

func testVimSessionExCommandsAndZZ() throws {
    let session = VimSession(initialText: "foo apple foo\nsecond line foo")

    // 1. Stream :%s/foo/bar/g\r
    let subCmd = ":%s/foo/bar/g\r"
    for ch in subCmd {
        session.feedKeys(String(ch))
    }
    guard session.serializeBuffer() == "bar apple bar\nsecond line bar" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Streaming :%s failed: \(session.serializeBuffer())"])
    }

    // 2. Stream :w\r
    var actions: [VimSystemAction] = []
    session.onSystemAction = { act in actions.append(act) }
    for ch in ":w\r" {
        session.feedKeys(String(ch))
    }
    guard actions.contains(VIM_ACTION_SAVE) else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected VIM_ACTION_SAVE"])
    }
    session.clearPendingAction()
    actions.removeAll()

    // 3. Stream :w!\r
    for ch in ":w!\r" {
        session.feedKeys(String(ch))
    }
    guard actions.contains(VIM_ACTION_SAVE_FORCE) else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected VIM_ACTION_SAVE_FORCE"])
    }
    session.clearPendingAction()
    actions.removeAll()

    // 4. Stream ZZ character-by-character
    session.feedKeys("Z")
    guard !session.shouldQuit else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Single 'Z' should not quit"])
    }
    session.feedKeys("Z")
    guard session.shouldQuit else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "'ZZ' should set shouldQuit"])
    }

    // 5. Ex command :ZZ
    let cleanSession = VimSession(initialText: "clean")
    cleanSession.executeEx("ZZ")
    guard cleanSession.shouldQuit else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: ":ZZ should set shouldQuit"])
    }
}

func testVimSessionCore8020Commands() throws {
    let text = "alpha beta gamma\none two three\nfoo bar baz"
    let session = VimSession(initialText: text)

    // 1. Navigation: 0, ^, $, w, b, e, ge, f, t, counts
    session.setCursor(line: 1, byteCol: 10)
    session.feedKeys("0")
    guard session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "'0' motion failed"])
    }
    session.feedKeys("$")
    guard session.cursorPosition.byteCol == 16 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "'$' motion failed"])
    }
    session.feedKeys("b")
    guard session.cursorPosition.byteCol == 12 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "'b' motion failed"])
    }
    session.feedKeys("e")
    guard session.cursorPosition.byteCol == 16 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "'e' motion failed"])
    }
    session.feedKeys("w")
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "'w' motion to next line failed"])
    }

    // Inline find 'b'
    session.setCursor(line: 1, byteCol: 1)
    session.feedKeys("f")
    session.feedKeys("b")
    guard session.cursorPosition.byteCol == 7 else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "'fb' motion failed"])
    }

    // Counts: 2j
    session.feedKeys("2")
    session.feedKeys("j")
    guard session.cursorPosition.line == 3 else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "'2j' motion failed"])
    }

    // 2. Operators: dd, p
    session.setCursor(line: 2, byteCol: 1)
    session.feedKeys("d")
    session.feedKeys("d")
    guard session.serializeBuffer() == "alpha beta gamma\nfoo bar baz" else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "'dd' failed: \(session.serializeBuffer())"])
    }
    session.feedKeys("p")
    guard session.serializeBuffer() == "alpha beta gamma\nfoo bar baz\none two three" else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "'p' paste failed: \(session.serializeBuffer())"])
    }

    // 3. dw, r<char>, x, s, J
    let s2 = VimSession(initialText: "word1 word2\nline2")
    s2.feedKeys("d")
    s2.feedKeys("w")
    guard s2.serializeBuffer() == "word2\nline2" else {
        throw NSError(domain: "EngineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "'dw' failed"])
    }
    s2.feedKeys("r")
    s2.feedKeys("W")
    guard s2.serializeBuffer() == "Word2\nline2" else {
        throw NSError(domain: "EngineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "'r' failed"])
    }
    s2.feedKeys("x")
    guard s2.serializeBuffer() == "ord2\nline2" else {
        throw NSError(domain: "EngineTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "'x' failed"])
    }
    s2.feedKeys("J")
    guard s2.serializeBuffer() == "ord2 line2" else {
        throw NSError(domain: "EngineTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "'J' failed"])
    }
}

func testVimSessionEscCancellation() throws {
    let session = VimSession(initialText: "Line 1\nLine 2\nLine 3")
    session.setCursor(line: 2, byteCol: 1)

    // Cancel pending 'g'
    session.feedKeys("g")
    session.feedKeys("\u{1b}")
    session.feedKeys("g")
    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pending 'g' was not cancelled"])
    }
    session.feedKeys("\u{1b}")

    // Cancel pending operator 'd'
    session.feedKeys("d")
    session.feedKeys("\u{1b}")
    session.feedKeys("d")
    guard session.serializeBuffer() == "Line 1\nLine 2\nLine 3" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Pending 'd' was not cancelled"])
    }
    session.feedKeys("\u{1b}")

    // Cancel count
    session.feedKeys("5")
    session.feedKeys("\u{1b}")
    session.feedKeys("j")
    guard session.cursorPosition.line == 3 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Count was not cancelled"])
    }
}

func testVimSessionClipboardYankIntegration() throws {
    let session = VimSession(initialText: "First line\nSecond line\nThird line")

    var yankCount = 0
    var lastYank = ""
    var lastLinewise = false
    session.onYank = { text, linewise in
        yankCount += 1
        lastYank = text
        lastLinewise = linewise
    }

    // 1. yy (yank line)
    session.feedKeys("yy")
    guard yankCount == 1, lastLinewise == true, lastYank.contains("First line") else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "yy failed to trigger onYank: count=\(yankCount), text=\(lastYank)"])
    }
    let pb1 = NSPasteboard.general.string(forType: .string) ?? ""
    guard pb1.contains("First line") else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "yy failed to update NSPasteboard: '\(pb1)'"])
    }

    // 2. yw (yank word)
    session.feedKeys("yw")
    guard yankCount == 2, lastLinewise == false, lastYank.hasPrefix("First") else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "yw failed to trigger onYank: count=\(yankCount), text=\(lastYank)"])
    }
    let pb2 = NSPasteboard.general.string(forType: .string) ?? ""
    guard pb2.hasPrefix("First") else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "yw failed to update NSPasteboard: '\(pb2)'"])
    }

    // 3. dd (delete line)
    session.feedKeys("dd")
    guard yankCount == 3, lastLinewise == true, lastYank.contains("First line") else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "dd failed to trigger onYank: count=\(yankCount), text=\(lastYank)"])
    }
    let pb3 = NSPasteboard.general.string(forType: .string) ?? ""
    guard pb3.contains("First line") else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "dd failed to update NSPasteboard: '\(pb3)'"])
    }

    // 4. dw (delete word) on "Second line"
    session.feedKeys("dw")
    guard yankCount == 4, lastLinewise == false, lastYank.hasPrefix("Second") else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "dw failed to trigger onYank: count=\(yankCount), text=\(lastYank)"])
    }
    let pb4 = NSPasteboard.general.string(forType: .string) ?? ""
    guard pb4.hasPrefix("Second") else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "dw failed to update NSPasteboard: '\(pb4)'"])
    }

    // 5. x (cut character) on "line"
    session.feedKeys("x")
    guard yankCount == 5, lastLinewise == false, lastYank == "l" else {
        throw NSError(domain: "EngineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "x failed to trigger onYank: count=\(yankCount), text=\(lastYank)"])
    }
    let pb5 = NSPasteboard.general.string(forType: .string) ?? ""
    guard pb5 == "l" else {
        throw NSError(domain: "EngineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "x failed to update NSPasteboard: '\(pb5)'"])
    }
}

func testVimSessionClipboardPasteIntegration() throws {
    let session = VimSession(initialText: "Header Line\nTarget Line")

    // 1. External clipboard write
    let extString = "Injected From macOS Pasteboard"
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(extString, forType: .string)

    // Move to col 1 of line 2 and paste 'p' (characterwise)
    session.setCursor(line: 2, byteCol: 1)
    session.feedKeys("p")

    let contentAfterP = session.serializeBuffer()
    guard contentAfterP.contains(extString) else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "'p' did not paste external clipboard string: '\(contentAfterP)'"])
    }

    // 2. Multiline external clipboard paste
    let multilineClip = "Inserted Row 1\nInserted Row 2\n"
    pb.clearContents()
    pb.setString(multilineClip, forType: .string)

    session.setCursor(line: 1, byteCol: 1)
    session.feedKeys("p") // linewise paste after line 1

    let contentAfterMultiline = session.serializeBuffer()
    guard contentAfterMultiline.contains("Inserted Row 1") && contentAfterMultiline.contains("Inserted Row 2") else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "multiline 'p' did not paste rows: '\(contentAfterMultiline)'"])
    }
}

func testVimSessionUndoRedoBasic() throws {
    let initial = "The quick brown fox"
    let session = VimSession(initialText: initial)
    guard !session.canUndo else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial session should not have undo states"])
    }
    guard !session.canRedo else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial session should not have redo states"])
    }

    session.feedKeys("x")
    guard session.serializeBuffer() == "he quick brown fox" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after 'x'"])
    }
    guard session.canUndo else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected canUndo == true after edit"])
    }
    guard !session.canRedo else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected canRedo == false after edit"])
    }

    session.undo()
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after undo: \(session.serializeBuffer())"])
    }
    guard !session.canUndo else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected canUndo == false after full undo"])
    }
    guard session.canRedo else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected canRedo == true after undo"])
    }

    session.redo()
    guard session.serializeBuffer() == "he quick brown fox" else {
        throw NSError(domain: "EngineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after redo"])
    }
    guard session.canUndo && !session.canRedo else {
        throw NSError(domain: "EngineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "State flags incorrect after redo"])
    }
}

func testVimSessionUndoInsertSession() throws {
    let initial = "Prefix: "
    let session = VimSession(initialText: initial)
    session.feedKeys("$aInserted Text\u{1b}")

    guard session.serializeBuffer() == "Prefix: Inserted Text" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after insert session"])
    }

    session.undo()
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after undo of insert session: '\(session.serializeBuffer())'"])
    }

    session.redo()
    guard session.serializeBuffer() == "Prefix: Inserted Text" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after redo of insert session"])
    }
}

func testVimSessionExUndoRedo() throws {
    let initial = "red green blue"
    let session = VimSession(initialText: initial)

    session.executeEx(":%s/green/yellow/g")
    guard session.serializeBuffer() == "red yellow blue" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Substitution failed"])
    }

    session.executeEx(":u")
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Undo via :u failed"])
    }

    session.executeEx(":redo")
    guard session.serializeBuffer() == "red yellow blue" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Redo via :redo failed"])
    }
}

func testVimSessionMultiStepUndoRedoWithCoordinateResolver() throws {
    let initial = "Row 1\nRow 2\nRow 3"
    let session = VimSession(initialText: initial)

    // Edit 1: delete Row 1
    session.feedKeys("dd")
    // Edit 2: append Row 4
    session.feedKeys("G")
    session.feedKeys("oRow 4\u{1b}")

    guard session.lineIndexTable.lineCount == 3 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 lines in lineIndexTable"])
    }

    // Undo edit 2
    session.undo()
    guard session.serializeBuffer() == "Row 2\nRow 3" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Undo 2 failed"])
    }
    guard session.lineIndexTable.lineCount == 2 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable should have 2 lines after undo 2"])
    }

    // Undo edit 1
    session.undo()
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Undo 1 failed"])
    }
    guard session.lineIndexTable.lineCount == 3 else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "lineIndexTable should have 3 lines after undo 1"])
    }

    // Redo edit 1
    session.redo()
    guard session.serializeBuffer() == "Row 2\nRow 3" else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Redo 1 failed"])
    }

    // Redo edit 2
    session.redo()
    guard session.serializeBuffer() == "Row 2\nRow 3\nRow 4" else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Redo 2 failed"])
    }
}

func testVimSessionCommandCount() throws {
    let session = VimSession(initialText: "line 1\nline 2\nline 3\nline 4\nline 5\n")
    guard session.commandCount == 0 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial commandCount must be 0"])
    }

    session.feedKeys("3")
    guard session.commandCount == 3 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected commandCount 3 after '3', got \(session.commandCount)"])
    }

    session.feedKeys("5")
    guard session.commandCount == 35 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected commandCount 35 after '5', got \(session.commandCount)"])
    }

    session.clearCommandCount()
    guard session.commandCount == 0 else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected commandCount 0 after clear, got \(session.commandCount)"])
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
    ("testVimSessionSetCursorAndModeNotifications", testVimSessionSetCursorAndModeNotifications),
    ("testVimSessionStreamingGGAndG", testVimSessionStreamingGGAndG),
    ("testVimSessionVisualTextObjects", testVimSessionVisualTextObjects),
    ("testVimSessionBackwardVisualSelectionAndEmptyObjects", testVimSessionBackwardVisualSelectionAndEmptyObjects),
    ("testVimSessionSearchAndNavigation", testVimSessionSearchAndNavigation),
    ("testVimSessionExCommandsAndZZ", testVimSessionExCommandsAndZZ),
    ("testVimSessionCore8020Commands", testVimSessionCore8020Commands),
    ("testVimSessionEscCancellation", testVimSessionEscCancellation),
    ("testVimSessionClipboardYankIntegration", testVimSessionClipboardYankIntegration),
    ("testVimSessionClipboardPasteIntegration", testVimSessionClipboardPasteIntegration),
    ("testVimSessionUndoRedoBasic", testVimSessionUndoRedoBasic),
    ("testVimSessionUndoInsertSession", testVimSessionUndoInsertSession),
    ("testVimSessionExUndoRedo", testVimSessionExUndoRedo),
    ("testVimSessionMultiStepUndoRedoWithCoordinateResolver", testVimSessionMultiStepUndoRedoWithCoordinateResolver),
    ("testVimSessionCommandCount", testVimSessionCommandCount)
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
