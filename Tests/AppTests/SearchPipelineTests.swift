import Foundation
import AppKit
import App
import Engine
import Views
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

func sendKey(_ tv: VimMDTextView, char: String, keyCode: UInt16 = 0) {
    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: keyCode
    )!
    tv.keyDown(with: event)
}

func sendBackspace(_ tv: VimMDTextView) {
    sendKey(tv, char: "\u{7f}", keyCode: 51)
}

func sendEscape(_ tv: VimMDTextView) {
    sendKey(tv, char: "\u{1b}", keyCode: 53)
}

func sendReturn(_ tv: VimMDTextView) {
    sendKey(tv, char: "\r", keyCode: 36)
}

func testLiveSearchPromptUI() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let msgLabel = doc.messageLabel, let modeLabel = doc.modeLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document views nil"])
    }

    // Verify initial Normal mode UI
    guard modeLabel.stringValue == "NORMAL" || modeLabel.stringValue == "-- NORMAL --" else {
        throw NSError(domain: "SearchPipelineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected initial mode label 'NORMAL', got '\(modeLabel.stringValue)'"])
    }
    // modeLabel is positioned to the right of ruler gutter (x > 8), text aligned with text body margin
    guard modeLabel.frame.origin.x > 8 else {
        throw NSError(domain: "SearchPipelineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "modeLabel should be positioned past gutter (x > 8), got \(modeLabel.frame.origin.x)"])
    }
    guard msgLabel.frame.origin.x == 155 else {
        throw NSError(domain: "SearchPipelineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "msgLabel should be at x = 155 in NORMAL mode, got \(msgLabel.frame.origin.x)"])
    }

    // Press '/' to start search
    sendKey(tv, char: "/")

    guard doc.session?.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "SearchPipelineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected mode COMMAND after '/', got \(String(describing: doc.session?.modeString))"])
    }

    // Status bar prompt must start directly at bottom-left (x = 8)
    guard msgLabel.frame.origin.x == 8 else {
        throw NSError(domain: "SearchPipelineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "msgLabel should move to x = 8 during search prompt, got \(msgLabel.frame.origin.x)"])
    }

    // modeLabel must be hidden / cleared so it doesn't take bottom-left space
    guard modeLabel.isHidden || modeLabel.stringValue.isEmpty else {
        throw NSError(domain: "SearchPipelineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "modeLabel should be hidden or empty during search, isHidden=\(modeLabel.isHidden), text=\(modeLabel.stringValue)"])
    }

    // msgLabel should show '/' with monospaced bold font and textColor
    guard msgLabel.stringValue == "/" else {
        throw NSError(domain: "SearchPipelineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected msgLabel string '/' , got '\(msgLabel.stringValue)'"])
    }
    guard msgLabel.textColor == NSColor.textColor || msgLabel.textColor == NSColor.labelColor else {
        throw NSError(domain: "SearchPipelineTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected msgLabel textColor to be NSColor.textColor or labelColor, got \(String(describing: msgLabel.textColor))"])
    }
}

func testStreamingKeystrokesAndBackspace() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()
    guard let tv = doc.textView, let msgLabel = doc.messageLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    sendKey(tv, char: "/")
    for c in "term" {
        sendKey(tv, char: String(c))
    }

    guard msgLabel.stringValue == "/term" else {
        throw NSError(domain: "SearchPipelineTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected '/term', got '\(msgLabel.stringValue)'"])
    }
    guard msgLabel.frame.origin.x == 8 else {
        throw NSError(domain: "SearchPipelineTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "msgLabel should stay at x = 8 while streaming query"])
    }

    sendBackspace(tv)
    guard msgLabel.stringValue == "/ter" else {
        throw NSError(domain: "SearchPipelineTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected '/ter' after backspace, got '\(msgLabel.stringValue)'"])
    }
}

func testEscCancelsSearchPrompt() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()
    guard let tv = doc.textView, let msgLabel = doc.messageLabel, let modeLabel = doc.modeLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    sendKey(tv, char: "/")
    sendKey(tv, char: "x")
    guard doc.session?.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "SearchPipelineTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Should be in COMMAND mode"])
    }

    sendEscape(tv)

    guard doc.session?.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "SearchPipelineTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected NORMAL mode after Escape"])
    }
    guard !modeLabel.isHidden && (modeLabel.stringValue == "NORMAL" || modeLabel.stringValue == "-- NORMAL --") else {
        throw NSError(domain: "SearchPipelineTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "modeLabel should be visible with 'NORMAL'"])
    }
    guard msgLabel.frame.origin.x == 155 else {
        throw NSError(domain: "SearchPipelineTests", code: 18, userInfo: [NSLocalizedDescriptionKey: "msgLabel should reset to x = 155 on leaving COMMAND mode, got \(msgLabel.frame.origin.x)"])
    }
}

func testSearchExecutionAndCentering() throws {
    let initialText = "Header Line\nSecond Line\nThird Line\nFourth Line\nTarget Match\nSixth Line"
    guard let data = initialText.data(using: .utf8) else {
        throw NSError(domain: "SearchPipelineTests", code: 19, userInfo: [NSLocalizedDescriptionKey: "UTF-8 conversion failed"])
    }

    let doc = try VimMDDocument(type: "public.plain-text")
    try doc.read(from: data, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let msgLabel = doc.messageLabel, let modeLabel = doc.modeLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    sendKey(tv, char: "/")
    for c in "Target" {
        sendKey(tv, char: String(c))
    }
    sendReturn(tv)

    guard doc.session?.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "SearchPipelineTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected mode NORMAL after search execution"])
    }

    // Cursor jumps to the matched pattern: line 5, col 1
    let pos = doc.session!.cursorPosition
    guard pos.line == 5 && pos.byteCol == 1 else {
        throw NSError(domain: "SearchPipelineTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at Line 5, Col 1, got Line \(pos.line), Col \(pos.byteCol)"])
    }

    // Status bar shows '/Target'
    guard msgLabel.stringValue == "/Target" else {
        throw NSError(domain: "SearchPipelineTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected msgLabel '/Target', got '\(msgLabel.stringValue)'"])
    }

    // modeLabel restored
    guard !modeLabel.isHidden && (modeLabel.stringValue == "NORMAL" || modeLabel.stringValue == "-- NORMAL --") else {
        throw NSError(domain: "SearchPipelineTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "modeLabel should be restored to 'NORMAL'"])
    }
    guard msgLabel.frame.origin.x == 155 else {
        throw NSError(domain: "SearchPipelineTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "msgLabel should be reset to x = 155"])
    }

    // Selected range synced with caret
    let selectedRange = tv.selectedRange()
    let offset = doc.session!.cursorUtf16Offset
    guard selectedRange.location == offset else {
        throw NSError(domain: "SearchPipelineTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "TextView selectedRange location \(selectedRange.location) != session offset \(offset)"])
    }
}

func testPatternNotFoundWarning() throws {
    let initialText = "Alpha Beta Gamma"
    let doc = try VimMDDocument(type: "public.plain-text")
    try doc.read(from: initialText.data(using: .utf8)!, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let msgLabel = doc.messageLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    sendKey(tv, char: "/")
    for c in "Delta" {
        sendKey(tv, char: String(c))
    }
    sendReturn(tv)

    guard msgLabel.stringValue.contains("Pattern not found: Delta") else {
        throw NSError(domain: "SearchPipelineTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "Expected warning 'Pattern not found: Delta', got '\(msgLabel.stringValue)'"])
    }
    guard msgLabel.textColor == NSColor.systemOrange else {
        throw NSError(domain: "SearchPipelineTests", code: 29, userInfo: [NSLocalizedDescriptionKey: "Expected orange textColor for pattern not found warning"])
    }
}

func testNextAndPreviousNavigation() throws {
    let initialText = "apple banana\napple cherry\napple date"
    let doc = try VimMDDocument(type: "public.plain-text")
    try doc.read(from: initialText.data(using: .utf8)!, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let msgLabel = doc.messageLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    sendKey(tv, char: "/")
    for c in "apple" {
        sendKey(tv, char: String(c))
    }
    sendReturn(tv)

    guard doc.session!.cursorPosition.line == 1 else {
        throw NSError(domain: "SearchPipelineTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after initial search"])
    }

    // 'n' moves forward to line 2
    sendKey(tv, char: "n")
    guard doc.session!.cursorPosition.line == 2 else {
        throw NSError(domain: "SearchPipelineTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Expected line 2 after 'n', got \(doc.session!.cursorPosition.line)"])
    }
    guard msgLabel.stringValue == "/apple" else {
        throw NSError(domain: "SearchPipelineTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected '/apple' on status bar after 'n', got '\(msgLabel.stringValue)'"])
    }

    // 'n' moves forward to line 3
    sendKey(tv, char: "n")
    guard doc.session!.cursorPosition.line == 3 else {
        throw NSError(domain: "SearchPipelineTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected line 3 after 'n', got \(doc.session!.cursorPosition.line)"])
    }

    // 'N' moves backward to line 2
    sendKey(tv, char: "N")
    guard doc.session!.cursorPosition.line == 2 else {
        throw NSError(domain: "SearchPipelineTests", code: 35, userInfo: [NSLocalizedDescriptionKey: "Expected line 2 after 'N', got \(doc.session!.cursorPosition.line)"])
    }
    guard msgLabel.stringValue == "/apple" else {
        throw NSError(domain: "SearchPipelineTests", code: 36, userInfo: [NSLocalizedDescriptionKey: "Expected '/apple' on status bar after 'N', got '\(msgLabel.stringValue)'"])
    }

    // 'p' with clean yank buffer moves backward to line 1
    sendKey(tv, char: "p")
    guard doc.session!.cursorPosition.line == 1 else {
        throw NSError(domain: "SearchPipelineTests", code: 37, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after 'p' with clean yank buffer, got \(doc.session!.cursorPosition.line)"])
    }
    guard msgLabel.stringValue == "/apple" else {
        throw NSError(domain: "SearchPipelineTests", code: 38, userInfo: [NSLocalizedDescriptionKey: "Expected '/apple' on status bar after 'p', got '\(msgLabel.stringValue)'"])
    }
}

func testPWhenYankBufferHasContentPerformsPaste() throws {
    let initialText = "first line\nsecond line"
    let doc = try VimMDDocument(type: "public.plain-text")
    try doc.read(from: initialText.data(using: .utf8)!, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView else {
        throw NSError(domain: "SearchPipelineTests", code: 39, userInfo: [NSLocalizedDescriptionKey: "Missing text view"])
    }

    // Perform search
    sendKey(tv, char: "/")
    for c in "line" {
        sendKey(tv, char: String(c))
    }
    sendReturn(tv)

    // Now yank line 1 with 'yy'
    doc.session!.setCursor(line: 1, byteCol: 1)
    sendKey(tv, char: "y")
    sendKey(tv, char: "y")

    guard doc.session?.yankBuffer != nil else {
        throw NSError(domain: "SearchPipelineTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "yankBuffer should have content"])
    }

    // Now press 'p' -> must perform paste (increasing line count), not search backward!
    let prevLineCount = doc.session!.lineIndexTable.lineCount
    sendKey(tv, char: "p")
    let newLineCount = doc.session!.lineIndexTable.lineCount

    guard newLineCount > prevLineCount else {
        throw NSError(domain: "SearchPipelineTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected 'p' to paste when yankBuffer has content: prev=\(prevLineCount), new=\(newLineCount)"])
    }
}

func testNoPreviousSearchWarning() throws {
    let initialText = "Some arbitrary text"
    let doc = try VimMDDocument(type: "public.plain-text")
    try doc.read(from: initialText.data(using: .utf8)!, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let msgLabel = doc.messageLabel else {
        throw NSError(domain: "SearchPipelineTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Missing views"])
    }

    // Press 'n' without any prior search
    sendKey(tv, char: "n")
    guard msgLabel.stringValue.contains("E35: No previous regular expression") else {
        throw NSError(domain: "SearchPipelineTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected E35 warning on 'n' without search, got '\(msgLabel.stringValue)'"])
    }

    // Press 'N' without any prior search
    sendKey(tv, char: "N")
    guard msgLabel.stringValue.contains("E35: No previous regular expression") else {
        throw NSError(domain: "SearchPipelineTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Expected E35 warning on 'N' without search, got '\(msgLabel.stringValue)'"])
    }

    // Press '/<CR>' without any prior search
    sendKey(tv, char: "/")
    sendReturn(tv)
    guard msgLabel.stringValue.contains("E35: No previous regular expression") else {
        throw NSError(domain: "SearchPipelineTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Expected E35 warning on '/<CR>' without search, got '\(msgLabel.stringValue)'"])
    }
}

let tests = [
    ("testLiveSearchPromptUI", testLiveSearchPromptUI),
    ("testStreamingKeystrokesAndBackspace", testStreamingKeystrokesAndBackspace),
    ("testEscCancelsSearchPrompt", testEscCancelsSearchPrompt),
    ("testSearchExecutionAndCentering", testSearchExecutionAndCentering),
    ("testPatternNotFoundWarning", testPatternNotFoundWarning),
    ("testNextAndPreviousNavigation", testNextAndPreviousNavigation),
    ("testPWhenYankBufferHasContentPerformsPaste", testPWhenYankBufferHasContentPerformsPaste),
    ("testNoPreviousSearchWarning", testNoPreviousSearchWarning),
]

var passedCount = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passedCount += 1
    } else {
        exit(1)
    }
}
print("Result: \(passedCount)/\(tests.count) tests passed.")
