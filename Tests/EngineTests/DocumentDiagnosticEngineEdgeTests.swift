import Foundation
import Engine

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

func fail(_ msg: String) -> NSError {
    return NSError(domain: "DiagEdgeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

func csv(_ t: String) -> [DocumentDiagnostic] {
    DocumentDiagnosticEngine.analyze(text: t, isTabular: true, isTSV: false, isMarkdown: false)
}
func md(_ t: String) -> [DocumentDiagnostic] {
    DocumentDiagnosticEngine.analyze(text: t, isTabular: false, isTSV: false, isMarkdown: true)
}
func expectEmpty(_ d: [DocumentDiagnostic], _ what: String) throws {
    guard d.isEmpty else { throw fail("\(what): expected no diagnostics, got \(d)") }
}
func mdWithFence(remaining: Int, trailingNewline: Bool, fence: String = "```") -> String {
    var lines = ["# T", fence]
    for i in 0..<remaining { lines.append("code \(i)") }
    return lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
}
func hasFenceNotice(_ d: [DocumentDiagnostic]) -> Bool {
    d.contains { $0.message.hasPrefix("Unclosed code block") }
}

// --- Line endings ---
func testCRLFClean() throws { try expectEmpty(csv("a,b\r\n1,2\r\n3,4\r\n"), "CRLF clean") }
func testLoneCRClean() throws { try expectEmpty(csv("a,b\r1,2\r3,4\r"), "lone CR clean") }
func testCRLFOverflowLine() throws {
    let d = csv("a,b\r\n1,2\r\n3,4,5\r\n")
    guard d.first?.message == "Inconsistent columns (Header: 2, Line 3: 3)", d.first?.line == 3 else { throw fail("CRLF overflow: \(d)") }
}
func testLoneCROverflowLine() throws {
    let d = csv("a,b\r1,2\r3,4,5\r")
    guard d.first?.message == "Inconsistent columns (Header: 2, Line 3: 3)" else { throw fail("lone CR overflow: \(d)") }
}
func testCRLFUnclosedQuote() throws {
    let d = csv("a,b\r\n1,\"x\r\n2,3\r\n")
    guard d.contains(where: { $0.message == "Unclosed quote at line 2; rows swallowed to EOF" }) else { throw fail("CRLF unclosed: \(d)") }
}

// --- Quoting ---
func testOverflowLineAfterMultilineQuotedCell() throws {
    // Record 2 spans physical lines 2-4; overflow record starts at physical line 5.
    let d = csv("a,b\n1,\"x\ny\nz\"\n3,4,5\n")
    guard d.contains(where: { $0.message == "Inconsistent columns (Header: 2, Line 5: 3)" && $0.line == 5 }) else { throw fail("multiline line num: \(d)") }
    guard !d.contains(where: { $0.message.contains("Unclosed") }) else { throw fail("false unclosed: \(d)") }
}
func testEscapedQuotesInsideMultilineCell() throws {
    try expectEmpty(csv("a,b\n1,\"he said \"\"hi\"\"\nthen \"\"left\"\"\"\n2,3\n"), "escaped quotes multiline")
}
func testQuotedFieldWithCommasNoOverflow() throws {
    try expectEmpty(csv("a,b\n\"x,y,z\",2\n"), "quoted commas")
}

// --- BOM ---
func testBOMCleanCSV() throws { try expectEmpty(csv("\u{FEFF}a,b\n1,2\n"), "BOM clean") }
func testBOMQuotedFirstHeader() throws {
    // Header is 2 columns ("a,b" and c); a data row with 2 columns must not overflow.
    try expectEmpty(csv("\u{FEFF}\"a,b\",c\n1,2\n"), "BOM quoted header")
}
func testBOMQuotedFirstHeaderOverflowStillDetected() throws {
    let d = csv("\u{FEFF}\"a,b\",c\n1,2,3\n")
    guard d.contains(where: { $0.message == "Inconsistent columns (Header: 2, Line 2: 3)" }) else { throw fail("BOM overflow: \(d)") }
}
func testBOMSemicolonNotice() throws {
    let d = csv("\u{FEFF}a;b;c\n1;2;3\n")
    guard d.contains(where: { $0.message.hasPrefix("Semicolon-delimited") }) else { throw fail("BOM semicolon: \(d)") }
}
func testBOMQuotedHeaderNoUnclosedQuote() throws {
    try expectEmpty(csv("\u{FEFF}\"a\",\"b\"\n1,2\n"), "BOM quoted header unclosed")
}

// --- Fence boundaries ---
func testFenceExactly25NoNewlineNoNotice() throws { guard !hasFenceNotice(md(mdWithFence(remaining: 25, trailingNewline: false))) else { throw fail("25 no NL") } }
func testFenceExactly25WithNewlineNoNotice() throws { guard !hasFenceNotice(md(mdWithFence(remaining: 25, trailingNewline: true))) else { throw fail("25 with NL") } }
func testFence26NoNewlineNotice() throws { guard hasFenceNotice(md(mdWithFence(remaining: 26, trailingNewline: false))) else { throw fail("26 no NL") } }
func testFence26WithNewlineNotice() throws { guard hasFenceNotice(md(mdWithFence(remaining: 26, trailingNewline: true))) else { throw fail("26 with NL") } }
func testFenceNoticeSeverityIsNotice() throws {
    let d = md(mdWithFence(remaining: 30, trailingNewline: true))
    guard d.first?.severity == .notice, d.first?.line == 2 else { throw fail("severity: \(d)") }
}

// --- Fence variants ---
func testTildeFenceUnclosedNotice() throws { guard hasFenceNotice(md(mdWithFence(remaining: 30, trailingNewline: false, fence: "~~~"))) else { throw fail("tilde") } }
func testTildeFenceClosedByTildeNoNotice() throws {
    try expectEmpty(md(mdWithFence(remaining: 30, trailingNewline: false, fence: "~~~") + "\n~~~\ntext"), "tilde closed")
}
func testBacktickNotClosedByTilde() throws {
    guard hasFenceNotice(md(mdWithFence(remaining: 30, trailingNewline: false) + "\n~~~")) else { throw fail("backtick closed by tilde") }
}
func testIndent4IsNotAFence() throws {
    var lines = ["# T", "    ```swift"]
    for i in 0..<40 { lines.append("    code \(i)") }
    try expectEmpty(md(lines.joined(separator: "\n")), "indent-4 fence")
}
func testIndent3IsAFence() throws {
    guard hasFenceNotice(md(mdWithFence(remaining: 30, trailingNewline: false, fence: "   ```"))) else { throw fail("indent-3") }
}
func testMismatchedLengthDoesNotClose() throws {
    // 4-backtick opener is not closed by a 3-backtick line.
    guard hasFenceNotice(md(mdWithFence(remaining: 30, trailingNewline: false, fence: "````") + "\n```")) else { throw fail("shorter closer") }
}
func testLongerCloserCloses() throws {
    try expectEmpty(md(mdWithFence(remaining: 30, trailingNewline: false, fence: "```") + "\n`````\nend"), "longer closer")
}
func testInlineBackticksNoNotice() throws {
    var lines = ["Use ```code``` inline and `x` here."]
    for i in 0..<40 { lines.append("line \(i)") }
    try expectEmpty(md(lines.joined(separator: "\n")), "inline backticks")
}
func testFenceMarkersInFrontmatterIgnored() throws {
    var lines = ["---", "title: x", "```", "---", "# Body"]
    for i in 0..<40 { lines.append("para \(i)") }
    try expectEmpty(md(lines.joined(separator: "\n")), "frontmatter fence")
}
func testFenceAfterFrontmatterStillDetected() throws {
    var lines = ["---", "title: x", "---", "```"]
    for i in 0..<40 { lines.append("code \(i)") }
    let d = md(lines.joined(separator: "\n"))
    guard d.contains(where: { $0.line == 4 && $0.message == "Unclosed code block starting at line 4" }) else { throw fail("after frontmatter: \(d)") }
}

// --- Zero-noise markdown ---
func testUnclosedBoldNoDiagnostic() throws { try expectEmpty(md("This is **bold and never closed\nnext line\n"), "unclosed bold") }
func testTrivialMarkdownNoDiagnostics() throws {
    try expectEmpty(md("# H\n\n* a, b\n* _c\n> quote [link(\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n<div>\n"), "trivial markdown")
}
func testNoCSVDiagnosticsForMarkdownText() throws { try expectEmpty(md("a,b\n1,2,3\n\"unclosed\n"), "md not tabular") }

// --- Performance ---
func testPerformance15kRows() throws {
    var rows = ["id,name,desc,value"]
    for i in 0..<15000 { rows.append("\(i),name\(i),\"some, quoted text \(i)\",\(i * 3)") }
    let text = rows.joined(separator: "\n")
    guard text.count > 500_000 else { throw fail("fixture too small: \(text.count)") }
    let start = Date()
    let d = csv(text)
    let elapsed = Date().timeIntervalSince(start)
    try expectEmpty(d, "perf clean")
    guard elapsed < 1.0 else { throw fail("csv analysis took \(elapsed)s") }
}
func testPerformanceLargeMarkdown() throws {
    var lines: [String] = []
    for i in 0..<15000 { lines.append("Line \(i) of prose with some words and `inline` code and more text") }
    let text = lines.joined(separator: "\n")
    let start = Date()
    let d = md(text)
    let elapsed = Date().timeIntervalSince(start)
    try expectEmpty(d, "perf md clean")
    guard elapsed < 1.0 else { throw fail("md analysis took \(elapsed)s") }
}

let tests: [(String, () throws -> Void)] = [
    ("testCRLFClean", testCRLFClean), ("testLoneCRClean", testLoneCRClean),
    ("testCRLFOverflowLine", testCRLFOverflowLine), ("testLoneCROverflowLine", testLoneCROverflowLine),
    ("testCRLFUnclosedQuote", testCRLFUnclosedQuote),
    ("testOverflowLineAfterMultilineQuotedCell", testOverflowLineAfterMultilineQuotedCell),
    ("testEscapedQuotesInsideMultilineCell", testEscapedQuotesInsideMultilineCell),
    ("testQuotedFieldWithCommasNoOverflow", testQuotedFieldWithCommasNoOverflow),
    ("testBOMCleanCSV", testBOMCleanCSV), ("testBOMQuotedFirstHeader", testBOMQuotedFirstHeader),
    ("testBOMQuotedFirstHeaderOverflowStillDetected", testBOMQuotedFirstHeaderOverflowStillDetected),
    ("testBOMSemicolonNotice", testBOMSemicolonNotice),
    ("testBOMQuotedHeaderNoUnclosedQuote", testBOMQuotedHeaderNoUnclosedQuote),
    ("testFenceExactly25NoNewlineNoNotice", testFenceExactly25NoNewlineNoNotice),
    ("testFenceExactly25WithNewlineNoNotice", testFenceExactly25WithNewlineNoNotice),
    ("testFence26NoNewlineNotice", testFence26NoNewlineNotice),
    ("testFence26WithNewlineNotice", testFence26WithNewlineNotice),
    ("testFenceNoticeSeverityIsNotice", testFenceNoticeSeverityIsNotice),
    ("testTildeFenceUnclosedNotice", testTildeFenceUnclosedNotice),
    ("testTildeFenceClosedByTildeNoNotice", testTildeFenceClosedByTildeNoNotice),
    ("testBacktickNotClosedByTilde", testBacktickNotClosedByTilde),
    ("testIndent4IsNotAFence", testIndent4IsNotAFence), ("testIndent3IsAFence", testIndent3IsAFence),
    ("testMismatchedLengthDoesNotClose", testMismatchedLengthDoesNotClose),
    ("testLongerCloserCloses", testLongerCloserCloses),
    ("testInlineBackticksNoNotice", testInlineBackticksNoNotice),
    ("testFenceMarkersInFrontmatterIgnored", testFenceMarkersInFrontmatterIgnored),
    ("testFenceAfterFrontmatterStillDetected", testFenceAfterFrontmatterStillDetected),
    ("testUnclosedBoldNoDiagnostic", testUnclosedBoldNoDiagnostic),
    ("testTrivialMarkdownNoDiagnostics", testTrivialMarkdownNoDiagnostics),
    ("testNoCSVDiagnosticsForMarkdownText", testNoCSVDiagnosticsForMarkdownText),
    ("testPerformance15kRows", testPerformance15kRows),
    ("testPerformanceLargeMarkdown", testPerformanceLargeMarkdown)
]

print("=== DocumentDiagnosticEngineEdgeTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) { passed += 1 }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count { exit(1) }
