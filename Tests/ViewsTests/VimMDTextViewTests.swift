import Foundation
import AppKit
import Views
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

func testTextViewSessionBindingAndDeltaSync() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Original Content")
    textView.session = session

    guard textView.string == "Original Content" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "TextView text did not initialize from session: '\(textView.string)'"])
    }

    // Apply delta from Ex command or session
    session.executeEx(":%s/Original/Updated/g")
    guard textView.string == "Updated Content" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView did not reflect delta update: '\(textView.string)'"])
    }
}

func testTextViewNormalModeInterception() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "First Line\nSecond Line")
    textView.session = session

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Normal mode"])
    }

    // Simulate keyDown in normal mode: 'j' moves down to line 2
    let eventJ = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "j",
        charactersIgnoringModifiers: "j",
        isARepeat: false,
        keyCode: 38 // 'j'
    )!
    textView.keyDown(with: eventJ)

    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cursor did not advance to line 2, got \(session.cursorPosition)"])
    }
    guard textView.selectedRange().location == session.cursorUtf16Offset else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Caret location mismatch, got \(textView.selectedRange().location), expected \(session.cursorUtf16Offset)"])
    }
}

func testTextViewInsertModeTextInputClient() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Start ")
    textView.session = session

    // Switch to insert mode via 'A' (append)
    session.feedKeys("A")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Insert mode"])
    }

    // Test NSTextInputClient insertText
    textView.insertText("Added", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard session.serializeBuffer() == "Start Added" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "InsertText failed to route to session, got '\(session.serializeBuffer())'"])
    }

    // Test Escape key returning to Normal mode
    let eventEsc = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53 // Esc
    )!
    textView.keyDown(with: eventEsc)

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected mode to return to NORMAL after Esc"])
    }
}

func testImeMarkedTextLifecycle() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    guard !textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Should not have marked text initially"])
    }

    textView.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    guard textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected marked text to be active"])
    }
    guard textView.markedRange().length == 3 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected marked length 3, got \(textView.markedRange().length)"])
    }

    textView.unmarkText()
    guard !textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected no marked text after unmarkText"])
    }
}

func testAttributedSubstring() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.string = "Alpha Beta Gamma"

    var actualRange = NSRange(location: 0, length: 0)
    let substring = textView.attributedSubstring(forProposedRange: NSRange(location: 6, length: 4), actualRange: &actualRange)

    guard substring?.string == "Beta" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected substring 'Beta', got '\(String(describing: substring?.string))'"])
    }
    guard actualRange == NSRange(location: 6, length: 4) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Actual range mismatch: \(actualRange)"])
    }
}

func testVisualModeKeyInterception() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Selectable Text")
    textView.session = session

    session.feedKeys("v")
    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Visual mode"])
    }

    let eventL = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "l",
        charactersIgnoringModifiers: "l",
        isARepeat: false,
        keyCode: 37
    )!
    textView.keyDown(with: eventL)

    guard session.cursorPosition.byteCol == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Visual mode cursor col expected 2, got \(session.cursorPosition.byteCol)"])
    }

    let eventEsc = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
    )!
    textView.keyDown(with: eventEsc)

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected return to Normal mode after Esc"])
    }
}

func testNilSessionSafety() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    // session is nil
    textView.synchronizeCaretWithSession()
    textView.applyDelta(startLine: 1, deletedCount: 0, newLines: ["Safe"])
    textView.insertText("No crash", replacementRange: NSRange(location: 0, length: 0))

    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )!
    textView.keyDown(with: event)
    // Passes if no crash
}

func testTextViewOpenLineMutations() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Line 1\nLine 2")
    textView.session = session

    // 'o' opens line below line 1
    session.feedKeys("oInserted Below\u{1b}")
    guard textView.string == "Line 1\nInserted Below\nLine 2" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed 'o' insertion sync, got: '\(textView.string)'"])
    }

    // 'O' opens line above line 1
    session.feedKeys("gg")
    session.feedKeys("OTop Header\u{1b}")
    guard textView.string == "Top Header\nLine 1\nInserted Below\nLine 2" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed 'O' insertion sync, got: '\(textView.string)'"])
    }
}

print("=== VimMDTextView Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testTextViewSessionBindingAndDeltaSync", testTextViewSessionBindingAndDeltaSync),
    ("testTextViewNormalModeInterception", testTextViewNormalModeInterception),
    ("testTextViewInsertModeTextInputClient", testTextViewInsertModeTextInputClient),
    ("testImeMarkedTextLifecycle", testImeMarkedTextLifecycle),
    ("testAttributedSubstring", testAttributedSubstring),
    ("testVisualModeKeyInterception", testVisualModeKeyInterception),
    ("testNilSessionSafety", testNilSessionSafety),
    ("testTextViewOpenLineMutations", testTextViewOpenLineMutations)
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
