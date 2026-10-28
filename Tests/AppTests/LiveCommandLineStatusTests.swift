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

func testSessionCommandLineBufferLiveUpdate() throws {
    let session = VimSession(initialText: "First line\nSecond line")

    guard session.commandLineBuffer.isEmpty else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "commandLineBuffer should initially be empty"])
    }

    // Enter Ex mode with ':'
    session.feedKeys(":")
    guard session.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected mode COMMAND, got \(session.modeString)"])
    }
    guard session.commandLineBuffer == ":" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected ':', got '\(session.commandLineBuffer)'"])
    }

    // Type 'w'
    session.feedKeys("w")
    guard session.commandLineBuffer == ":w" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected ':w', got '\(session.commandLineBuffer)'"])
    }

    // Type 'q'
    session.feedKeys("q")
    guard session.commandLineBuffer == ":wq" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected ':wq', got '\(session.commandLineBuffer)'"])
    }

    // Backspace
    session.feedKeys("\u{7f}")
    guard session.commandLineBuffer == ":w" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected ':w' after backspace, got '\(session.commandLineBuffer)'"])
    }

    // Escape
    session.feedKeys("\u{1b}")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected mode NORMAL after Escape, got \(session.modeString)"])
    }
    guard session.commandLineBuffer.isEmpty else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "commandLineBuffer should be empty after Escape"])
    }

    // Enter Search mode with '/'
    session.feedKeys("/")
    guard session.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected mode COMMAND for search, got \(session.modeString)"])
    }
    guard session.commandLineBuffer == "/" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected '/', got '\(session.commandLineBuffer)'"])
    }

    session.feedKeys("test")
    guard session.commandLineBuffer == "/test" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected '/test', got '\(session.commandLineBuffer)'"])
    }

    session.feedKeys("\u{1b}")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected mode NORMAL after search Escape, got \(session.modeString)"])
    }
}

func testDocumentStatusDisplayRendersLiveCommand() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()

    guard let msgLabel = doc.messageLabel else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "doc.messageLabel is nil"])
    }

    guard let textView = doc.textView else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "doc.textView is nil"])
    }

    // Simulate typing ':' via textView
    textView.keyDown(with: NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: ":",
        charactersIgnoringModifiers: ":",
        isARepeat: false,
        keyCode: 41
    )!)

    guard doc.session?.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected mode COMMAND"])
    }
    guard msgLabel.stringValue == ":" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected ':', got '\(msgLabel.stringValue)'"])
    }
    guard msgLabel.textColor == NSColor.labelColor else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected textColor to be labelColor, got \(msgLabel.textColor)"])
    }

    // Type '%s/foo/bar/g'
    for char in "%s/foo/bar/g" {
        textView.keyDown(with: NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: String(char),
            charactersIgnoringModifiers: String(char),
            isARepeat: false,
            keyCode: 0
        )!)
    }

    guard msgLabel.stringValue == ":%s/foo/bar/g" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 18, userInfo: [NSLocalizedDescriptionKey: "Expected ':%s/foo/bar/g', got '\(msgLabel.stringValue)'"])
    }

    // Backspace 3 times
    for _ in 0..<3 {
        textView.keyDown(with: NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7f}",
            charactersIgnoringModifiers: "\u{7f}",
            isARepeat: false,
            keyCode: 51
        )!)
    }

    guard msgLabel.stringValue == ":%s/foo/ba" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 19, userInfo: [NSLocalizedDescriptionKey: "Expected ':%s/foo/ba' after backspaces, got '\(msgLabel.stringValue)'"])
    }

    // Escape exits command mode
    textView.keyDown(with: NSEvent.keyEvent(
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
    )!)

    guard doc.session?.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected mode NORMAL after Escape"])
    }
    guard msgLabel.stringValue != ":%s/foo/ba" else {
        throw NSError(domain: "LiveCommandLineStatusTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected status bar to clear live command after Escape"])
    }
}

let tests = [
    ("testSessionCommandLineBufferLiveUpdate", testSessionCommandLineBufferLiveUpdate),
    ("testDocumentStatusDisplayRendersLiveCommand", testDocumentStatusDisplayRendersLiveCommand),
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
