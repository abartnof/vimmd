import Foundation
import AppKit
import Engine
import Views
import App

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

func testMarkdownHybridTypography() throws {
    let text = """
# Main Header
This is normal body text with `inline_code` and **bold** text.
| Header A | Header B |
| -------- | -------- |
| Value 1  | Value 2  |
"""
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
    textView.documentSyntaxType = .markdown
    let session = VimSession(initialText: text)
    textView.session = session

    guard let storage = textView.textStorage else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textStorage is nil"])
    }

    let fullString = storage.string as NSString

    // 1. Header 1: "# Main Header" should have bold system font of size 22
    let headerRange = fullString.range(of: "Main Header")
    guard headerRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "'Main Header' not found"])
    }
    guard let headerFont = storage.attribute(.font, at: headerRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Header font attribute missing"])
    }
    guard headerFont.pointSize == 22 else {
        throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected header font size 22, got \(headerFont.pointSize)"])
    }
    guard NSFontManager.shared.traits(of: headerFont).contains(.boldFontMask) else {
        throw NSError(domain: "TypographyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected header to be bold"])
    }

    // 2. Body text: "This is normal body text with " should have proportional systemFont of size 14
    let bodyRange = fullString.range(of: "This is normal body text with ")
    guard bodyRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Body text not found"])
    }
    guard let bodyFont = storage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Body font attribute missing"])
    }
    guard bodyFont.pointSize == 14 else {
        throw NSError(domain: "TypographyTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected body font size 14, got \(bodyFont.pointSize)"])
    }
    guard !bodyFont.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Body text must be proportional (SF Pro), not fixed pitch"])
    }

    // 3. Inline code span: "`inline_code`" should have monospaced font of size 13
    let codeRange = fullString.range(of: "inline_code")
    guard codeRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "'inline_code' not found"])
    }
    guard let codeFont = storage.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Code font attribute missing"])
    }
    guard codeFont.pointSize == 13 else {
        throw NSError(domain: "TypographyTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected code font size 13, got \(codeFont.pointSize)"])
    }
    guard codeFont.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected code span to have monospaced font"])
    }

    // 4. Markdown Table: "| Header A | Header B |" should be monospaced SF Mono 13pt
    let tableRange = fullString.range(of: "| Header A | Header B |")
    guard tableRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Table header not found"])
    }
    guard let tableFont = storage.attribute(.font, at: tableRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Table font attribute missing"])
    }
    guard tableFont.pointSize == 13 else {
        throw NSError(domain: "TypographyTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected table font size 13, got \(tableFont.pointSize)"])
    }
    guard tableFont.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected table row to have monospaced font"])
    }
}

func testMarkdownFrontmatterMonospaced() throws {
    let text = """
---
title: System Architecture
version: 2.1
author: VimMD
---
# Main Content
Regular body line.
"""
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
    textView.documentSyntaxType = .markdown
    let session = VimSession(initialText: text)
    textView.session = session

    guard let storage = textView.textStorage else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textStorage is nil"])
    }
    let fullString = storage.string as NSString

    // Frontmatter content should be monospaced 13pt
    let fmRange = fullString.range(of: "title: System Architecture")
    guard fmRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Frontmatter content not found"])
    }
    guard let fmFont = storage.attribute(.font, at: fmRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Frontmatter font missing"])
    }
    guard fmFont.pointSize == 13 && fmFont.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected frontmatter to be monospaced 13pt"])
    }

    // Body content after frontmatter should be proportional 14pt
    let bodyRange = fullString.range(of: "Regular body line.")
    guard bodyRange.location != NSNotFound else {
        throw NSError(domain: "TypographyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Body line not found"])
    }
    guard let bodyFont = storage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont else {
        throw NSError(domain: "TypographyTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Body font missing"])
    }
    guard bodyFont.pointSize == 14 && !bodyFont.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected body text to be proportional 14pt"])
    }
}

func testPlainTextMonospacedAcrossAllContent() throws {
    let plainContent = """
# Header Line
* List item with **bold** text
`code span`
Just standard plain text.
"""
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
    textView.documentSyntaxType = .plainText
    let session = VimSession(initialText: plainContent)
    textView.session = session

    guard let storage = textView.textStorage else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textStorage is nil"])
    }

    guard storage.length > 0 else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Storage is empty"])
    }

    // Verify 100% of characters have NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) and textColor
    var index = 0
    while index < storage.length {
        var effectiveRange = NSRange(location: 0, length: 0)
        let attrs = storage.attributes(at: index, effectiveRange: &effectiveRange)

        guard let font = attrs[.font] as? NSFont else {
            throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing font at index \(index)"])
        }
        guard font.pointSize == 13 else {
            throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected font size 13 at index \(index), got \(font.pointSize)"])
        }
        guard font.isFixedPitch else {
            throw NSError(domain: "TypographyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Font at index \(index) must be fixed-pitch (SF Mono)"])
        }
        guard !NSFontManager.shared.traits(of: font).contains(.boldFontMask) else {
            throw NSError(domain: "TypographyTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Plain text must not have bold traits at index \(index)"])
        }

        if let fg = attrs[.foregroundColor] as? NSColor {
            guard fg == NSColor.textColor else {
                throw NSError(domain: "TypographyTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "ForegroundColor at index \(index) is \(fg), expected textColor"])
            }
        }

        index = effectiveRange.location + effectiveRange.length
    }
}

func testCodeFormatsMonospaced() throws {
    let codeFiles: [(String, String, String)] = [
        ("deploy.sh", "public.shell-script", "#!/bin/bash\necho 'Deploying...'\nif [ $? -eq 0 ]; then\n  exit 0\nfi"),
        ("config.json", "public.json", "{\n  \"port\": 8080,\n  \"name\": \"vimmd\"\n}"),
        ("script.py", "public.python-script", "def run():\n    # python comment\n    return True"),
        ("main.c", "public.c-source", "#include <stdio.h>\nint main() { return 0; }"),
        ("Main.swift", "public.swift-source", "import Foundation\nprint(\"Hello, world!\")"),
        ("values.yaml", "public.yaml", "replicaCount: 3\nimage:\n  repository: vimmd")
    ]

    for (filename, fileType, content) in codeFiles {
        let doc = VimMDDocument()
        doc.fileURL = URL(fileURLWithPath: "/tmp/\(filename)")
        doc.fileType = fileType

        guard doc.documentSyntaxType == .plainText else {
            throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected .plainText for \(filename), got \(doc.documentSyntaxType)"])
        }

        let data = content.data(using: .utf8)!
        try doc.read(from: data, ofType: fileType)
        doc.makeWindowControllers()

        guard let tv = doc.textView else {
            throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView nil for \(filename)"])
        }
        guard tv.documentSyntaxType == .plainText else {
            throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected tv.documentSyntaxType == .plainText for \(filename), got \(tv.documentSyntaxType)"])
        }

        guard let storage = tv.textStorage else {
            throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "textStorage nil for \(filename)"])
        }

        // Verify all characters are SF Mono 13pt
        var idx = 0
        while idx < storage.length {
            var range = NSRange(location: 0, length: 0)
            let attrs = storage.attributes(at: idx, effectiveRange: &range)
            guard let font = attrs[.font] as? NSFont else {
                throw NSError(domain: "TypographyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Font missing in \(filename) at index \(idx)"])
            }
            guard font.pointSize == 13 && font.isFixedPitch else {
                throw NSError(domain: "TypographyTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected 13pt fixed-pitch font in \(filename) at index \(idx)"])
            }
            idx = range.location + range.length
        }
    }
}

func testSyntaxTypeDetectionMapping() throws {
    // Markdown
    let mdURL = URL(fileURLWithPath: "/path/to/doc.md")
    let markdownURL = URL(fileURLWithPath: "/path/to/doc.markdown")
    guard VimMDDocument.syntaxType(for: mdURL, fileType: nil as String?) == .markdown else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: ".md URL syntaxType mismatch"])
    }
    guard VimMDDocument.syntaxType(for: markdownURL, fileType: nil as String?) == .markdown else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: ".markdown URL syntaxType mismatch"])
    }
    guard VimMDDocument.syntaxType(for: nil as URL?, fileType: "net.daringfireball.markdown") == .markdown else {
        throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "net.daringfireball.markdown syntaxType mismatch"])
    }

    // CSV
    let csvURL = URL(fileURLWithPath: "/path/to/data.csv")
    guard VimMDDocument.syntaxType(for: csvURL, fileType: nil as String?) == .csv else {
        throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: ".csv URL syntaxType mismatch"])
    }
    guard VimMDDocument.syntaxType(for: nil as URL?, fileType: "public.comma-separated-values-text") == .csv else {
        throw NSError(domain: "TypographyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "CSV typeName syntaxType mismatch"])
    }

    // TSV
    let tsvURL = URL(fileURLWithPath: "/path/to/data.tsv")
    guard VimMDDocument.syntaxType(for: tsvURL, fileType: nil as String?) == .tsv else {
        throw NSError(domain: "TypographyTests", code: 6, userInfo: [NSLocalizedDescriptionKey: ".tsv URL syntaxType mismatch"])
    }
    guard VimMDDocument.syntaxType(for: nil as URL?, fileType: "public.tab-separated-values-text") == .tsv else {
        throw NSError(domain: "TypographyTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "TSV typeName syntaxType mismatch"])
    }

    // Plain text and code formats
    let plainURLs = [
        URL(fileURLWithPath: "/path/to/file.txt"),
        URL(fileURLWithPath: "/path/to/file.sh"),
        URL(fileURLWithPath: "/path/to/file.json"),
        URL(fileURLWithPath: "/path/to/file.py"),
        URL(fileURLWithPath: "/path/to/file.c"),
        URL(fileURLWithPath: "/path/to/file.swift"),
        URL(fileURLWithPath: "/path/to/file.yaml")
    ]
    for url in plainURLs {
        guard VimMDDocument.syntaxType(for: url, fileType: nil as String?) == .plainText else {
            throw NSError(domain: "TypographyTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected .plainText for \(url.path)"])
        }
    }

    // Untitled document
    guard VimMDDocument.syntaxType(for: nil as URL?, fileType: nil as String?) == .plainText else {
        throw NSError(domain: "TypographyTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected .plainText for untitled document"])
    }
}

func testDynamicSwitchingDocumentSyntaxType() throws {
    let content = "# Header 1\nBody text"
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    let session = VimSession(initialText: content)
    textView.session = session
    textView.documentSyntaxType = .markdown

    guard let storage = textView.textStorage else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textStorage nil"])
    }

    // In markdown, header should be size 22
    let fontMd = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let fMd = fontMd, fMd.pointSize == 22 else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header in markdown mode"])
    }

    // Switch to plainText
    textView.documentSyntaxType = .plainText

    // In plainText, entire buffer must be 13pt fixed-pitch
    let fontPlain = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let fPlain = fontPlain, fPlain.pointSize == 13 && fPlain.isFixedPitch else {
        throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 13pt fixed-pitch after switching to plainText"])
    }

    // Switch back to markdown
    textView.documentSyntaxType = .markdown
    let fontMdRestored = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let fMdRestored = fontMdRestored, fMdRestored.pointSize == 22 else {
        throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header restored in markdown mode"])
    }
}

func testTypingInPlainTextRetainsMonospace() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    textView.documentSyntaxType = .plainText
    let session = VimSession(initialText: "Initial content")
    textView.session = session

    guard textView.font?.isFixedPitch == true && textView.font?.pointSize == 13 else {
        throw NSError(domain: "TypographyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected default font to be 13pt monospaced"])
    }

    // Apply delta simulating insert mode typing: replace line 1 with "# New Line"
    textView.applyDelta(startLine: 1, deletedCount: 1, newLines: ["# New Header Line"])

    guard let storage = textView.textStorage else {
        throw NSError(domain: "TypographyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "textStorage nil"])
    }

    // Verify 100% of characters remain 13pt monospaced with textColor
    var idx = 0
    while idx < storage.length {
        var range = NSRange(location: 0, length: 0)
        let attrs = storage.attributes(at: idx, effectiveRange: &range)
        guard let font = attrs[.font] as? NSFont else {
            throw NSError(domain: "TypographyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Font missing at index \(idx)"])
        }
        guard font.pointSize == 13 && font.isFixedPitch else {
            throw NSError(domain: "TypographyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected 13pt monospaced font at index \(idx), got \(font)"])
        }
        idx = range.location + range.length
    }
}

print("=== Typography Hierarchy Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testMarkdownHybridTypography", testMarkdownHybridTypography),
    ("testMarkdownFrontmatterMonospaced", testMarkdownFrontmatterMonospaced),
    ("testPlainTextMonospacedAcrossAllContent", testPlainTextMonospacedAcrossAllContent),
    ("testCodeFormatsMonospaced", testCodeFormatsMonospaced),
    ("testSyntaxTypeDetectionMapping", testSyntaxTypeDetectionMapping),
    ("testDynamicSwitchingDocumentSyntaxType", testDynamicSwitchingDocumentSyntaxType),
    ("testTypingInPlainTextRetainsMonospace", testTypingInPlainTextRetainsMonospace)
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
