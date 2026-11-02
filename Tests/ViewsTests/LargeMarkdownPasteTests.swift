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
    return NSError(domain: "LargeMarkdownPasteTests", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
}

func generateLargeMarkdownSnippet(linesCount: Int = 500) -> String {
    var lines: [String] = []
    lines.append("# Main Document Title")
    lines.append("A general introduction to the document with **bold introductory text** and `inline code`.")
    lines.append("")
    for i in 1...linesCount {
        if i % 25 == 0 {
            lines.append("## Section \(i / 25): Detailed Analysis")
            lines.append("")
        } else if i % 10 == 0 {
            lines.append("```swift")
            lines.append("func executeStep\(i)() -> Bool {")
            lines.append("    print(\"Processing step \(i)...\")")
            lines.append("    return true")
            lines.append("}")
            lines.append("```")
            lines.append("")
        } else if i % 5 == 0 {
            lines.append("- Task item \(i): [Reference Link](https://example.com/item/\(i)) with *italic note* and ~~old value~~")
        } else {
            lines.append("Paragraph \(i): The rapid execution of batched markdown text insertion preserves typing throughput and prevents beachball stalls on large clipboards.")
        }
    }
    return lines.joined(separator: "\n")
}

func testLargeMarkdownPasteInInsertModePerformanceAndCorrectness() throws {
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .markdown
    let session = VimSession(initialText: "")
    tv.session = session
    scrollView.documentView = tv
    window.contentView = scrollView

    // Enter insert mode
    session.feedKeys("i")
    guard session.mode == VIM_MODE_INSERT else {
        throw fail(1, "Expected session to be in INSERT mode")
    }

    let markdownSnippet = generateLargeMarkdownSnippet(linesCount: 400)
    let byteCount = markdownSnippet.utf8.count
    print("   Snippet byte size: \(byteCount) bytes")

    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(markdownSnippet, forType: .string)

    let start = DispatchTime.now()
    tv.paste(nil)
    let end = DispatchTime.now()

    let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
    print("   Paste elapsed time (Insert Mode): \(elapsedMs) ms")

    // Check performance threshold (< 300 ms for unit tests)
    if elapsedMs > 300.0 {
        throw fail(2, "Insert mode paste took \(elapsedMs) ms, which exceeds the 300 ms limit (beachball risk)")
    }

    // Check correctness: content length and string equality
    let resultString = tv.string
    if resultString != markdownSnippet {
        throw fail(3, "Pasted content does not match source snippet! Expected length \(markdownSnippet.count), got \(resultString.count)")
    }

    // Check syntax attributes exist in textStorage
    guard let storage = tv.textStorage else {
        throw fail(4, "TextStorage must exist")
    }

    // Verify H1 header attribute on first line
    var effectiveRange = NSRange(location: 0, length: 0)
    let firstLineAttrs = storage.attributes(at: 2, effectiveRange: &effectiveRange)
    guard let font = firstLineAttrs[.font] as? NSFont, font.pointSize >= 18.0 else {
        throw fail(5, "Expected header font size >= 18 for '# Main Document Title', got \(String(describing: firstLineAttrs[.font]))")
    }
}

func testLargeMarkdownPasteInNormalModePerformanceAndCorrectness() throws {
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .markdown
    let session = VimSession(initialText: "")
    tv.session = session
    scrollView.documentView = tv
    window.contentView = scrollView

    guard session.mode == VIM_MODE_NORMAL else {
        throw fail(10, "Expected session to be in NORMAL mode")
    }

    let markdownSnippet = generateLargeMarkdownSnippet(linesCount: 400)
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(markdownSnippet, forType: .string)

    let start = DispatchTime.now()
    tv.paste(nil)
    let end = DispatchTime.now()

    let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
    print("   Paste elapsed time (Normal Mode): \(elapsedMs) ms")

    if elapsedMs > 300.0 {
        throw fail(11, "Normal mode paste took \(elapsedMs) ms, which exceeds the 300 ms limit")
    }

    let resultString = tv.string
    if !resultString.contains("## Section 1: Detailed Analysis") {
        throw fail(12, "Pasted content in normal mode missing expected content")
    }
}

let tests: [(String, () throws -> Void)] = [
    ("testLargeMarkdownPasteInInsertModePerformanceAndCorrectness", testLargeMarkdownPasteInInsertModePerformanceAndCorrectness),
    ("testLargeMarkdownPasteInNormalModePerformanceAndCorrectness", testLargeMarkdownPasteInNormalModePerformanceAndCorrectness)
]

print("=== LargeMarkdownPasteTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) { passed += 1 }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count { exit(1) }
