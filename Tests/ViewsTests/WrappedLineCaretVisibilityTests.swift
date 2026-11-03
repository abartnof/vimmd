import Foundation
import AppKit
import Engine
import Views
import App
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

func fail(_ code: Int, _ msg: String) -> NSError {
    return NSError(domain: "WrappedCaretTests", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
}

func sendKey(_ tv: VimMDTextView, char: String, keyCode: UInt16 = 0) {
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0, context: nil,
        characters: char, charactersIgnoringModifiers: char, isARepeat: false, keyCode: keyCode
    )!
    tv.keyDown(with: event)
}

final class ProseContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let tv: VimMDTextView
    let session: VimSession

    init(text: String, wrap: Bool) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !wrap
        tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.minSize = NSSize(width: 0, height: 600)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.documentSyntaxType = .markdown
        session = VimSession(initialText: text)
        tv.session = session
        scrollView.documentView = tv
        window.contentView = scrollView
        tv.wrapLines = wrap
        window.makeFirstResponder(tv)
        tv.updateSyntaxStyling(force: true)
        tv.updateFrameHeightToFitText()
        tv.resetScrollToTopLeft()
    }

    func caretRectIsVisible() -> (Bool, NSRect, NSRect) {
        let caret = tv.insertionBaseRect(at: tv.selectedRange().location)
        let visible = tv.visibleRect
        return (visible.intersects(caret) && caret.minY >= visible.minY - 0.5 && caret.maxY <= visible.maxY + 0.5, caret, visible)
    }
}

// 1. Wrapped single-line long paragraph: `$` keeps the caret on-screen
func testWrappedLongParagraphEndCaretVisible() throws {
    let words = (0..<4000).map { "word\($0)" }.joined(separator: " ")
    let ctx = ProseContext(text: words, wrap: true)
    sendKey(ctx.tv, char: "$")
    guard ctx.session.cursorPosition.line == 1, ctx.session.cursorPosition.byteCol > 1000 else {
        throw fail(1, "cursor did not reach end of line 1: \(ctx.session.cursorPosition)")
    }
    let (ok, caret, visible) = ctx.caretRectIsVisible()
    guard ok else { throw fail(2, "caret \(caret) not within visible \(visible)") }
    guard ctx.scrollView.contentView.bounds.origin.y > 0 else { throw fail(3, "expected scrolled down for wrapped line") }
}

// 2. Minified single-line file (no wrap, no spaces): caret stays visible, y never negative
func testMinifiedSingleLineCaretVisible() throws {
    let minified = String(repeating: "{\"a\":1,\"b\":[2,3]}", count: 2500)
    let ctx = ProseContext(text: minified, wrap: false)
    sendKey(ctx.tv, char: "$")
    let (ok, caret, visible) = ctx.caretRectIsVisible()
    guard ok else { throw fail(4, "caret \(caret) not within visible \(visible)") }
    guard ctx.scrollView.contentView.bounds.origin.y >= 0 else { throw fail(5, "negative y") }
}

// 3. Wrapped paragraph: `w` deep into the first line keeps the caret visible
func testWrappedLongParagraphWordMotionCaretVisible() throws {
    let words = (0..<4000).map { "word\($0)" }.joined(separator: " ")
    let ctx = ProseContext(text: words, wrap: true)
    for _ in 0..<1500 { sendKey(ctx.tv, char: "w") }
    let (ok, caret, visible) = ctx.caretRectIsVisible()
    guard ok else { throw fail(6, "caret \(caret) not within visible \(visible)") }
}

// 4. Visual selection in Row 1 of a sheet keeps Row 1 visible below horizontal ruler
func testVisualModeRow1Visible() throws {
    let ctx = SheetContext()
    ctx.tv.positionCaret(atRow: 0, column: 1)
    for _ in 0..<50 { sendKey(ctx.tv, char: "j") }
    sendKey(ctx.tv, char: "v")
    for _ in 0..<50 { sendKey(ctx.tv, char: "k") }
    guard ctx.session.cursorPosition.line == 1 else { throw fail(7, "expected line 1, got \(ctx.session.cursorPosition.line)") }
    let expectedY = -(ctx.scrollView.horizontalRulerView?.ruleThickness ?? 0)
    let y = ctx.scrollView.contentView.bounds.origin.y
    guard abs(y - expectedY) < 0.001 else { throw fail(8, "visual mode clip y = \(y), expected \(expectedY)") }
}

final class SheetContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let tv: VimMDTextView
    let session: VimSession

    init() {
        let csv = (["HeaderA,HeaderB,HeaderC,HeaderD"] + (1...60).map { "R\($0)A,R\($0)B,R\($0)C,R\($0)D" }).joined(separator: "\n") + "\n"
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.documentSyntaxType = .csv
        tv.isTabularDocument = true
        session = VimSession(initialText: csv)
        tv.session = session
        scrollView.documentView = tv
        let lineRuler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        lineRuler.clientView = tv
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = lineRuler
        scrollView.rulersVisible = true
        lineRuler.updateThickness(for: tv)
        let colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
        colRuler.clientView = tv
        scrollView.hasHorizontalRuler = true
        scrollView.horizontalRulerView = colRuler
        window.contentView = scrollView
        window.makeFirstResponder(tv)
        tv.updateSyntaxStyling(force: true)
        tv.updateFrameHeightToFitText()
        tv.resetScrollToTopLeft()
    }
}

let tests: [(String, () throws -> Void)] = [
    ("testWrappedLongParagraphEndCaretVisible", testWrappedLongParagraphEndCaretVisible),
    ("testMinifiedSingleLineCaretVisible", testMinifiedSingleLineCaretVisible),
    ("testWrappedLongParagraphWordMotionCaretVisible", testWrappedLongParagraphWordMotionCaretVisible),
    ("testVisualModeRow1Visible", testVisualModeRow1Visible)
]

print("=== WrappedLineCaretVisibilityTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) { passed += 1 }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count { exit(1) }
