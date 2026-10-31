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

func testSpreadsheetRowHoverAndClickToCopy() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    let csv = "Name,Department,Salary\nAlice,Engineering,150k\nBob,Design,120k\nCarol,Product,130k\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    ruler.clientView = textView
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    // 1. Cursor check: Hovering over LineNumberRulerView in spreadsheets returns rightwardArrowCursor
    let cur = ruler.cursorForPoint(NSPoint(x: 10, y: 30))
    guard cur == VimMDTextView.rightwardArrowCursor else {
        throw NSError(domain: "ViewsTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected rightwardArrowCursor over ruler in spreadsheet, got \(String(describing: cur))"])
    }

    // When NOT tabular document, cursor should be nil (default)
    textView.documentSyntaxType = .plainText
    let curPlain = ruler.cursorForPoint(NSPoint(x: 10, y: 30))
    guard curPlain == nil else {
        throw NSError(domain: "ViewsTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor for non-tabular document, got \(String(describing: curPlain))"])
    }
    textView.documentSyntaxType = .csv

    // 2. Click to copy: Click row 2 (which is Bob's row, 0-indexed row 2, line 3)
    guard let row2Rect = textView.rowRect(for: 2) else {
        throw NSError(domain: "ViewsTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to get rowRect for row 2"])
    }
    let rulerPt = ruler.convert(NSPoint(x: 0, y: row2Rect.midY), from: textView)

    var feedbackReceived: String?
    textView.onFlashFeedback = { msg in
        feedbackReceived = msg
    }

    NSPasteboard.general.clearContents()
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: ruler.convert(rulerPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDown(with: event)

    let copied = NSPasteboard.general.string(forType: .string)
    guard copied == "Bob,Design,120k" else {
        throw NSError(domain: "ViewsTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected copied 'Bob,Design,120k', got '\(String(describing: copied))'"])
    }
    guard let feedback = feedbackReceived, feedback.contains("Row 3") else {
        throw NSError(domain: "ViewsTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected feedback mentioning Row 3, got \(String(describing: feedbackReceived))"])
    }
    guard textView.transientFlashRect != nil else {
        throw NSError(domain: "ViewsTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected transientFlashRect to be set for flash feedback"])
    }
}

print("=== LineNumberRulerView Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testRulerInitializationAndScrollAttachment", testRulerInitializationAndScrollAttachment),
    ("testRulerThicknessDynamicCalculation", testRulerThicknessDynamicCalculation),
    ("testLineNumbersDoNotPolluteTextStorageOrCopy", testLineNumbersDoNotPolluteTextStorageOrCopy),
    ("testActiveLineHighlightUpdatesOnCursorMove", testActiveLineHighlightUpdatesOnCursorMove),
    ("testSpreadsheetRowHoverAndClickToCopy", testSpreadsheetRowHoverAndClickToCopy)
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
