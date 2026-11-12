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
    return NSError(domain: "MarkdownLineWrappingTests", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
}

/// Verifies that for a markdown document with wrapLines == true, long lines wrap within
/// the viewport width without requiring horizontal scrolling, and that
/// usedRect(for: textContainer).width <= contentWidth (accounting for ruler gutter).
func testMarkdownWrappingConstrainedToViewportWidthWithRuler() throws {
    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()

    guard doc.wrapLines == true else {
        throw fail(1, "Markdown document wrapLines should default to true")
    }

    doc.makeWindowControllers()
    guard let tv = doc.textView,
          let sv = doc.scrollView else {
        throw fail(2, "Window, text view, and scroll view must be configured")
    }

    let longProse = "This is a very long line in markdown that contains many words without manual newlines. " +
        String(repeating: "The quick brown fox jumps over the lazy dog and continues running across the fields. ", count: 20)
    let data = longProse.data(using: .utf8)!
    try doc.read(from: data, ofType: "net.daringfireball.markdown")

    let rulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let viewportWidth = sv.contentSize.width - rulerThickness

    guard let textContainer = tv.textContainer, let layoutManager = tv.layoutManager else {
        throw fail(3, "TextContainer and LayoutManager must exist")
    }

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)

    print("   viewportWidth: \(viewportWidth), tv.frame.width: \(tv.frame.width), usedRect.width: \(usedRect.width)")

    if tv.frame.width > viewportWidth + 0.5 {
        throw fail(4, "TextView frame width (\(tv.frame.width)) must not exceed viewport width (\(viewportWidth))")
    }

    if textContainer.containerSize.width > viewportWidth + 0.5 {
        throw fail(5, "TextContainer width (\(textContainer.containerSize.width)) must not exceed viewport width (\(viewportWidth))")
    }

    if usedRect.width > viewportWidth + 0.5 {
        throw fail(6, "Used rect width (\(usedRect.width)) must wrap within viewport width (\(viewportWidth))")
    }

    if sv.hasHorizontalScroller {
        throw fail(7, "Horizontal scroller must remain disabled when wrapLines == true for Markdown")
    }
}

/// Verifies that toggling wrapLines off and on, or resizing the window, restores and preserves
/// the viewport constraint.
func testMarkdownWrappingToggleAndResizePreservesConstraint() throws {
    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()
    doc.makeWindowControllers()

    guard let win = doc.windowControllers.first?.window,
          let tv = doc.textView,
          let sv = doc.scrollView,
          let textContainer = tv.textContainer,
          let layoutManager = tv.layoutManager else {
        throw fail(10, "Document views must exist")
    }

    let longProse = "Markdown toggle wrap lines verification text: " + String(repeating: "word wrap test content ", count: 30)
    try doc.read(from: longProse.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    // 1. Toggle wrap off
    tv.toggleWrapLines()
    guard tv.wrapLines == false else { throw fail(11, "wrapLines should be false") }
    guard sv.hasHorizontalScroller == true else { throw fail(12, "horizontal scroller should be enabled when unwrapped") }

    // 2. Toggle wrap back on
    tv.toggleWrapLines()
    guard tv.wrapLines == true else { throw fail(13, "wrapLines should be true") }
    guard sv.hasHorizontalScroller == false else { throw fail(14, "horizontal scroller should be disabled when wrapped") }

    let rulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let viewportWidth = sv.contentSize.width - rulerThickness

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)

    if usedRect.width > viewportWidth + 0.5 {
        throw fail(15, "After toggle on, used rect width (\(usedRect.width)) must wrap within viewport width (\(viewportWidth))")
    }

    // 3. Resize window from 800 to 600 width
    win.setFrame(NSRect(x: 100, y: 100, width: 600, height: 400), display: true)
    let newRulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let newViewportWidth = sv.contentSize.width - newRulerThickness

    layoutManager.ensureLayout(for: textContainer)
    let resizedUsedRect = layoutManager.usedRect(for: textContainer)

    if resizedUsedRect.width > newViewportWidth + 0.5 {
        throw fail(16, "After window resize to 600, used rect width (\(resizedUsedRect.width)) must wrap within new viewport width (\(newViewportWidth))")
    }
}

/// Verifies that headers, bold text, links, and inline code wrap softly without spilling.
func testMarkdownHeadersAndInlineElementsWrapSoftly() throws {
    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()
    doc.makeWindowControllers()

    guard let tv = doc.textView,
          let sv = doc.scrollView,
          let textContainer = tv.textContainer,
          let layoutManager = tv.layoutManager else {
        throw fail(20, "Document views must exist")
    }

    let markdownElements = """
    # This is an extremely long H1 header in markdown that has dozens and dozens of words so that it is guaranteed to exceed standard viewport bounds

    ## Another long H2 header with **bold title text** and [link target](https://example.com/very/long/path/for/documentation) that should wrap properly

    A paragraph with **bold words**, *italic words*, `monospaced code phrases`, and ~~strikethrough text~~ repeating: \(String(repeating: "styled markdown inline text ", count: 25))
    """

    try doc.read(from: markdownElements.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    let rulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let viewportWidth = sv.contentSize.width - rulerThickness

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)

    if usedRect.width > viewportWidth + 0.5 {
        throw fail(21, "Markdown elements used rect width (\(usedRect.width)) must wrap within viewport (\(viewportWidth))")
    }
}

/// Verifies that widening the window from narrow (600) to wide (1100) with wrapLines == true
/// expands tv.frame.width and textContainer.containerSize.width and reflows wrapped text.
func testMarkdownWrappingExpandsWhenWindowWidened() throws {
    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()
    doc.makeWindowControllers()

    guard let win = doc.windowControllers.first?.window,
          let tv = doc.textView,
          let sv = doc.scrollView,
          let textContainer = tv.textContainer,
          let layoutManager = tv.layoutManager else {
        throw fail(30, "Document views must exist")
    }

    let longProse = String(repeating: "The quick brown fox jumps over the lazy dog across wide meadows. ", count: 30)
    try doc.read(from: longProse.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    // Narrow window first
    win.setFrame(NSRect(x: 100, y: 100, width: 600, height: 400), display: true)
    layoutManager.ensureLayout(for: textContainer)
    let narrowUsedRect = layoutManager.usedRect(for: textContainer)

    // Widen window to 1100
    win.setFrame(NSRect(x: 100, y: 100, width: 1100, height: 400), display: true)
    let rulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let wideViewportWidth = sv.contentSize.width - rulerThickness
    let expectedContainerWidth = max(0, wideViewportWidth - tv.textContainerInset.width * 2)

    layoutManager.ensureLayout(for: textContainer)
    let wideUsedRect = layoutManager.usedRect(for: textContainer)

    if abs(tv.frame.width - wideViewportWidth) > 1.0 {
        throw fail(31, "After widening to 1100, tv.frame.width (\(tv.frame.width)) should expand to wideViewportWidth (\(wideViewportWidth))")
    }
    if abs(textContainer.containerSize.width - expectedContainerWidth) > 1.0 {
        throw fail(32, "After widening to 1100, textContainer.containerSize.width (\(textContainer.containerSize.width)) should expand to \(expectedContainerWidth)")
    }
    if wideUsedRect.width > wideViewportWidth + 0.5 {
        throw fail(33, "Wide usedRect.width (\(wideUsedRect.width)) must fit within wideViewportWidth (\(wideViewportWidth))")
    }
    if wideUsedRect.height >= narrowUsedRect.height {
        throw fail(34, "Reflowed wide text height (\(wideUsedRect.height)) should be less than narrow height (\(narrowUsedRect.height))")
    }
}

/// Verifies that toggling wrapLines = false on a Markdown document with large headers
/// updates tv.frame.width immediately from ensureLayout and sets tv.frame.height >= usedRect.height.
func testMarkdownUnwrappedHeightAndWidthWithLargeHeaders() throws {
    let savedPref = UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        if let saved = savedPref {
            UserDefaults.standard.set(saved, forKey: VimMDDocument.wrapLinesPreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
        }
    }

    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()
    doc.makeWindowControllers()

    guard let win = doc.windowControllers.first?.window,
          let tv = doc.textView,
          let textContainer = tv.textContainer,
          let layoutManager = tv.layoutManager else {
        throw fail(40, "Document views must exist")
    }

    win.setFrame(NSRect(x: 100, y: 100, width: 600, height: 400), display: true)

    let longHeader = "# Header " + String(repeating: "WideHeaderToken ", count: 25)
    let headers = (1...40).map { "# Heading Line \($0) with extra words" }.joined(separator: "\n")
    let markdown = longHeader + "\n" + headers
    try doc.read(from: markdown.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    // Ensure wrapped layout is computed first
    layoutManager.ensureLayout(for: textContainer)

    // Toggle wrap off
    tv.toggleWrapLines()
    guard tv.wrapLines == false else { throw fail(41, "wrapLines should be false") }

    let frameAfterToggleWidth = tv.frame.width
    let frameAfterToggleHeight = tv.frame.height

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)
    let expectedMinHeight = ceil(usedRect.height + tv.textContainerInset.height * 2)
    let expectedMinWidth = usedRect.width + tv.textContainerInset.width * 2

    if frameAfterToggleHeight < expectedMinHeight - 0.5 {
        throw fail(42, "Unwrapped tv.frame.height (\(frameAfterToggleHeight)) must be >= usedRect height + insets (\(expectedMinHeight))")
    }
    if frameAfterToggleWidth < expectedMinWidth - 0.5 {
        throw fail(43, "Unwrapped tv.frame.width (\(frameAfterToggleWidth)) must immediately cover usedRect width + insets (\(expectedMinWidth))")
    }
}

/// Verifies that changing magnification (e.g. 2.0x) with wrapLines == true reflows
/// textContainer.containerSize.width and tv.frame.width to the scaled viewport width.
func testMarkdownMagnificationReflowsWrappedText() throws {
    let doc = VimMDDocument()
    doc.fileType = "net.daringfireball.markdown"
    doc.configureWrapLinesPolicy()
    doc.makeWindowControllers()

    guard let tv = doc.textView,
          let sv = doc.scrollView,
          let textContainer = tv.textContainer,
          let layoutManager = tv.layoutManager else {
        throw fail(50, "Document views must exist")
    }
    guard tv.wrapLines == true else {
        throw fail(54, "wrapLines should be true for Markdown magnification test")
    }

    let longProse = String(repeating: "Zoom magnification reflow verification words in markdown prose. ", count: 25)
    try doc.read(from: longProse.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    doc.applyMagnificationScale(2.0)

    let mag = sv.magnification
    let rulerThickness = (sv.rulersVisible && sv.hasVerticalRuler) ? (sv.verticalRulerView?.ruleThickness ?? 0.0) : 0.0
    let scaledViewportWidth = sv.contentView.bounds.width - (rulerThickness / mag)

    layoutManager.ensureLayout(for: textContainer)
    let usedRect = layoutManager.usedRect(for: textContainer)

    if abs(tv.frame.width - scaledViewportWidth) > 1.0 {
        throw fail(51, "At 2.0x magnification, tv.frame.width (\(tv.frame.width)) should match scaledViewportWidth (\(scaledViewportWidth))")
    }
    if textContainer.containerSize.width > scaledViewportWidth + 0.5 {
        throw fail(52, "At 2.0x magnification, textContainer.containerSize.width (\(textContainer.containerSize.width)) must not exceed scaledViewportWidth (\(scaledViewportWidth))")
    }
    if usedRect.width > scaledViewportWidth + 0.5 {
        throw fail(53, "At 2.0x magnification, usedRect.width (\(usedRect.width)) must wrap within scaledViewportWidth (\(scaledViewportWidth))")
    }
}

let tests: [(String, () throws -> Void)] = [
    ("testMarkdownWrappingConstrainedToViewportWidthWithRuler", testMarkdownWrappingConstrainedToViewportWidthWithRuler),
    ("testMarkdownWrappingToggleAndResizePreservesConstraint", testMarkdownWrappingToggleAndResizePreservesConstraint),
    ("testMarkdownHeadersAndInlineElementsWrapSoftly", testMarkdownHeadersAndInlineElementsWrapSoftly),
    ("testMarkdownWrappingExpandsWhenWindowWidened", testMarkdownWrappingExpandsWhenWindowWidened),
    ("testMarkdownUnwrappedHeightAndWidthWithLargeHeaders", testMarkdownUnwrappedHeightAndWidthWithLargeHeaders),
    ("testMarkdownMagnificationReflowsWrappedText", testMarkdownMagnificationReflowsWrappedText)
]

print("=== MarkdownLineWrappingTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) { passed += 1 }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count { exit(1) }
