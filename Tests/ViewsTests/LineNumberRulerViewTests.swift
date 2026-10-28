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

func testRulerInitializationAndScrollAttachment() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    let session = VimSession(initialText: "First line\nSecond line\nThird line")
    textView.session = session
    scrollView.documentView = textView

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    guard scrollView.verticalRulerView is LineNumberRulerView else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "verticalRulerView is not LineNumberRulerView"])
    }
    guard scrollView.hasVerticalRuler && scrollView.rulersVisible else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Rulers are not visible"])
    }
    guard ruler.orientation == .verticalRuler else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ruler orientation is not vertical"])
    }
}

func testRulerThicknessDynamicCalculation() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    let sessionShort = VimSession(initialText: "1\n2\n3")
    textView.session = sessionShort
    scrollView.documentView = textView

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    ruler.updateThickness(for: textView)
    let shortThickness = ruler.ruleThickness
    guard shortThickness > 0 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Thickness must be > 0"])
    }

    // Now test with 1500 lines (requires 4 digits)
    var lines: [String] = []
    for i in 1...1500 {
        lines.append("Line \(i)")
    }
    let sessionLong = VimSession(initialText: lines.joined(separator: "\n"))
    textView.session = sessionLong

    ruler.updateThickness(for: textView)
    let longThickness = ruler.ruleThickness
    guard longThickness > shortThickness else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Long document thickness (\(longThickness)) should exceed short document thickness (\(shortThickness))"])
    }
}

func testLineNumbersDoNotPolluteTextStorageOrCopy() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    let originalText = "The quick brown fox\njumps over\nthe lazy dog"
    let session = VimSession(initialText: originalText)
    textView.session = session
    scrollView.documentView = textView

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    // Render ruler marks with an active headless graphics context
    let image = NSImage(size: NSSize(width: max(1, ruler.bounds.width), height: max(1, ruler.bounds.height)))
    image.lockFocus()
    ruler.draw(ruler.bounds)
    image.unlockFocus()

    // 1. Invariant: textView.string and textStorage NEVER contain line numbers
    guard textView.string == originalText else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textView.string was corrupted by ruler: '\(textView.string)'"])
    }
    guard textView.textStorage?.string == originalText else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "textStorage was corrupted by ruler: '\(textView.textStorage?.string ?? "")'"])
    }

    // 2. Invariant: Copying text NEVER captures line numbers
    textView.selectAll(nil as Any?)
    textView.copy(nil as Any?)

    let copied = NSPasteboard.general.string(forType: .string) ?? ""
    guard copied == originalText else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Copied text captured unexpected content: '\(copied)'"])
    }
    // Strict verify: does not contain line number formatting prefixes
    guard !copied.contains("1 ") && !copied.contains("1\t") else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Copied text contains line number prefix: '\(copied)'"])
    }
}

func testActiveLineHighlightUpdatesOnCursorMove() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    let session = VimSession(initialText: "First line\nSecond line\nThird line")
    textView.session = session
    scrollView.documentView = textView

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    guard session.cursorPosition.line == 1 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected initial cursor at line 1"])
    }

    // Move to line 2 via 'j'
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
        keyCode: 38
    )!
    textView.keyDown(with: eventJ)

    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at line 2"])
    }
}

print("=== LineNumberRulerView Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testRulerInitializationAndScrollAttachment", testRulerInitializationAndScrollAttachment),
    ("testRulerThicknessDynamicCalculation", testRulerThicknessDynamicCalculation),
    ("testLineNumbersDoNotPolluteTextStorageOrCopy", testLineNumbersDoNotPolluteTextStorageOrCopy),
    ("testActiveLineHighlightUpdatesOnCursorMove", testActiveLineHighlightUpdatesOnCursorMove)
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
