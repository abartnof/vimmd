import Foundation
import AppKit
import Views

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

func testHeaderDelimiterExtraction() throws {
    let resolver = MarkdownSyntaxResolver()
    let line = "## Main Title"
    let delimiters = resolver.extractDelimiters(from: line)

    guard delimiters.count == 1 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 1 header delimiter, got \(delimiters.count)"])
    }
    guard delimiters[0].type == .header(level: 2) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected level 2 header delimiter"])
    }
    guard delimiters[0].range.location == 0 && delimiters[0].range.length == 3 else { // "## "
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Header range mismatch: \(delimiters[0].range)"])
    }

    let concealed = resolver.concealedRanges(in: line)
    guard concealed.count == 1 && concealed[0].location == 0 && concealed[0].length == 3 else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Concealed ranges mismatch for header: \(concealed)"])
    }
}

func testEmphasisAndInlineCodeDelimiters() throws {
    let resolver = MarkdownSyntaxResolver()
    let line = "Text with **bold** and `code` words"
    let delimiters = resolver.extractDelimiters(from: line)

    // Should find bold delimiters and code delimiters
    guard delimiters.contains(where: { $0.type == .bold }) else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing bold delimiter"])
    }
    guard delimiters.contains(where: { $0.type == .inlineCode }) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing inlineCode delimiter"])
    }

    let concealed = resolver.concealedRanges(in: line)
    // Concealed should include opening '**', closing '**', opening '`', and closing '`'
    guard concealed.count >= 4 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected at least 4 concealed ranges, got \(concealed.count)"])
    }
}

func testLinkDelimiterExtraction() throws {
    let resolver = MarkdownSyntaxResolver()
    let line = "Visit [OpenAI](https://openai.com) now"
    let delimiters = resolver.extractDelimiters(from: line)

    guard delimiters.contains(where: { $0.type == .link }) else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing link delimiter"])
    }

    let concealed = resolver.concealedRanges(in: line)
    // Should conceal '[' and '](https://openai.com)'
    guard concealed.count == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 2 concealed ranges for link, got \(concealed.count)"])
    }
}

func testStyledAttributedStringConcealmentToggle() throws {
    let resolver = MarkdownSyntaxResolver()
    let line = "# Heading One"

    // When active editing line: raw unconcealed string
    let unconcealed = resolver.styledAttributedString(from: line, isCurrentEditingLine: true)
    guard unconcealed.string == line else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unconcealed string should equal raw string"])
    }

    // When inactive: concealed styled typography
    let concealed = resolver.styledAttributedString(from: line, isCurrentEditingLine: false)
    guard concealed.string == "Heading One" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Concealed string should strip delimiter, got '\(concealed.string)'"])
    }
}

func testViewportScrollCompensation() throws {
    let delta = MarkdownTextLayoutFragment.computeScrollCompensation(beforeHeight: 20.0, afterHeight: 35.0)
    guard delta == 15.0 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected delta 15.0, got \(delta)"])
    }
}

func testEmptyStringHandling() throws {
    let resolver = MarkdownSyntaxResolver()
    guard resolver.extractDelimiters(from: "").isEmpty else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected no delimiters for empty string"])
    }
    guard resolver.concealedRanges(in: "").isEmpty else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected no concealed ranges for empty string"])
    }
    guard resolver.styledAttributedString(from: "", isCurrentEditingLine: false).string.isEmpty else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected empty styled string"])
    }
}

func testMalformedMarkdown() throws {
    let resolver = MarkdownSyntaxResolver()
    let malformed = "This is `unclosed code and **unclosed bold and [incomplete link("
    let delimiters = resolver.extractDelimiters(from: malformed)
    let concealed = resolver.concealedRanges(in: malformed)

    let totalLen = (malformed as NSString).length
    for d in delimiters {
        guard d.range.location + d.range.length <= totalLen else {
            throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Delimiter out of bounds"])
        }
    }
    for r in concealed {
        guard r.location + r.length <= totalLen else {
            throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Concealed range out of bounds"])
        }
    }
}

func testItalicAndStrikethroughDelimiters() throws {
    let resolver = MarkdownSyntaxResolver()
    let line = "An *italic* word and _another_ plus ~~strikethrough~~"
    let delimiters = resolver.extractDelimiters(from: line)

    guard delimiters.contains(where: { $0.type == .italic }) else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing italic delimiter"])
    }
    guard delimiters.contains(where: { $0.type == .strikethrough }) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing strikethrough delimiter"])
    }

    let concealed = resolver.concealedRanges(in: line)
    // 2 for *italic*, 2 for _another_, 2 for ~~strikethrough~~ = 6 ranges
    guard concealed.count == 6 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 6 concealed ranges for italic/strike, got \(concealed.count)"])
    }
}

print("=== MarkdownSyntax Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testHeaderDelimiterExtraction", testHeaderDelimiterExtraction),
    ("testEmphasisAndInlineCodeDelimiters", testEmphasisAndInlineCodeDelimiters),
    ("testLinkDelimiterExtraction", testLinkDelimiterExtraction),
    ("testStyledAttributedStringConcealmentToggle", testStyledAttributedStringConcealmentToggle),
    ("testViewportScrollCompensation", testViewportScrollCompensation),
    ("testEmptyStringHandling", testEmptyStringHandling),
    ("testMalformedMarkdown", testMalformedMarkdown),
    ("testItalicAndStrikethroughDelimiters", testItalicAndStrikethroughDelimiters)
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
