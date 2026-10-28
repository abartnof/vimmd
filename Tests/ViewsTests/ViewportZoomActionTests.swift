import Foundation
import AppKit
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

func testZoomInZoomOutActualSizeActions() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.5
    scrollView.maxMagnification = 3.0
    scrollView.magnification = 1.0

    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let session = VimSession(initialText: "Hello Zoom")
    textView.session = session
    scrollView.documentView = textView

    // Test zoomIn
    textView.zoomIn(nil)
    guard abs(scrollView.magnification - 1.1) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.1 after zoomIn, got \(scrollView.magnification)"])
    }

    textView.zoomIn(nil)
    guard abs(scrollView.magnification - 1.2) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.2 after second zoomIn, got \(scrollView.magnification)"])
    }

    // Test zoomOut
    textView.zoomOut(nil)
    guard abs(scrollView.magnification - 1.1) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.1 after zoomOut, got \(scrollView.magnification)"])
    }

    // Test actualSize
    textView.actualSize(nil)
    guard abs(scrollView.magnification - 1.0) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.0 after actualSize, got \(scrollView.magnification)"])
    }

    // Test clamping max 3.0
    scrollView.magnification = 2.95
    textView.zoomIn(nil)
    guard abs(scrollView.magnification - 3.0) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 3.0 clamped, got \(scrollView.magnification)"])
    }

    // Test clamping min 0.5
    scrollView.magnification = 0.55
    textView.zoomOut(nil)
    guard abs(scrollView.magnification - 0.5) < 0.001 else {
        throw NSError(domain: "ViewportZoomActionTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 0.5 clamped, got \(scrollView.magnification)"])
    }
}

func testZoomKeyShortcutsInTextView() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.5
    scrollView.maxMagnification = 3.0
    scrollView.magnification = 1.0

    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let session = VimSession(initialText: "Shortcut Zoom")
    textView.session = session
    scrollView.documentView = textView

    // Simulate Cmd+=
    if let eventCmdPlus = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "=",
        charactersIgnoringModifiers: "=",
        isARepeat: false,
        keyCode: 24
    ) {
        textView.keyDown(with: eventCmdPlus)
        guard abs(scrollView.magnification - 1.1) < 0.001 else {
            throw NSError(domain: "ViewportZoomActionTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.1 after Cmd+=, got \(scrollView.magnification)"])
        }
    }

    // Simulate Cmd+-
    if let eventCmdMinus = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "-",
        charactersIgnoringModifiers: "-",
        isARepeat: false,
        keyCode: 27
    ) {
        textView.keyDown(with: eventCmdMinus)
        guard abs(scrollView.magnification - 1.0) < 0.001 else {
            throw NSError(domain: "ViewportZoomActionTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.0 after Cmd+-, got \(scrollView.magnification)"])
        }
    }

    // Zoom to 1.3
    scrollView.magnification = 1.3

    // Simulate Cmd+0
    if let eventCmdZero = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "0",
        charactersIgnoringModifiers: "0",
        isARepeat: false,
        keyCode: 29
    ) {
        textView.keyDown(with: eventCmdZero)
        guard abs(scrollView.magnification - 1.0) < 0.001 else {
            throw NSError(domain: "ViewportZoomActionTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.0 after Cmd+0, got \(scrollView.magnification)"])
        }
    }
}

let tests = [
    ("testZoomInZoomOutActualSizeActions", testZoomInZoomOutActualSizeActions),
    ("testZoomKeyShortcutsInTextView", testZoomKeyShortcutsInTextView),
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
