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

// 1. Unclosed quote at EOF in CSV
func testUnclosedQuoteAtEOFCSV() throws {
    let csv = "ColA,ColB\nvalA,\"valB\nvalC,valD"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard diags.contains(where: {
        $0.severity == .warning &&
        $0.message == "Unclosed quote at line 2; rows swallowed to EOF" &&
        $0.line == 2
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected unclosed quote warning at line 2, got: \(diags)"])
    }
}

// 2. Unclosed quote at EOF in TSV
func testUnclosedQuoteAtEOFTSV() throws {
    let tsv = "ColA\tColB\nvalA\t\"valB\nvalC\tvalD"
    let diags = DocumentDiagnosticEngine.analyze(text: tsv, isTabular: true, isTSV: true, isMarkdown: false)
    guard diags.contains(where: {
        $0.severity == .warning &&
        $0.message == "Unclosed quote at line 2; rows swallowed to EOF" &&
        $0.line == 2
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected unclosed quote warning in TSV at line 2, got: \(diags)"])
    }
}

// 3. Properly closed multiline quote does not trigger warning
func testClosedMultilineQuoteCSV() throws {
    let csv = "ColA,ColB\nvalA,\"multi\nline\nval\"\nvalC,valD"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard !diags.contains(where: { $0.message.contains("Unclosed quote") }) else {
        throw NSError(domain: "DiagnosticTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected unclosed quote warning for closed quotes: \(diags)"])
    }
}

// 4. Inconsistent column overflow in CSV
func testInconsistentColumnOverflowCSV() throws {
    let csv = "HeaderA,HeaderB\nValA,ValB,ExtraVal"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard diags.contains(where: {
        $0.severity == .warning &&
        $0.message == "Inconsistent columns (Header: 2, Line 2: 3)" &&
        $0.line == 2
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected inconsistent columns warning at line 2, got: \(diags)"])
    }
}

// 5. Inconsistent column overflow in TSV
func testInconsistentColumnOverflowTSV() throws {
    let tsv = "H1\tH2\tH3\nV1\tV2\tV3\tV4"
    let diags = DocumentDiagnosticEngine.analyze(text: tsv, isTabular: true, isTSV: true, isMarkdown: false)
    guard diags.contains(where: {
        $0.severity == .warning &&
        $0.message == "Inconsistent columns (Header: 3, Line 2: 4)" &&
        $0.line == 2
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected inconsistent columns warning in TSV at line 2, got: \(diags)"])
    }
}

// 6. Header with < 2 columns does not trigger column overflow
func testSingleColumnHeaderNoOverflowWarning() throws {
    let csv = "SingleColumn\nVal1,Val2,Val3"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard !diags.contains(where: { $0.message.contains("Inconsistent columns") }) else {
        throw NSError(domain: "DiagnosticTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Single column header should not trigger overflow warning: \(diags)"])
    }
}

// 7. Rows with fewer columns (ragged rows) do NOT trigger warning
func testRaggedRowsFewerColumnsNoWarning() throws {
    let csv = "HeaderA,HeaderB,HeaderC\nValA,ValB\nValA"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard !diags.contains(where: { $0.message.contains("Inconsistent columns") }) else {
        throw NSError(domain: "DiagnosticTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Fewer columns should not trigger overflow warning: \(diags)"])
    }
}

// 8. Semicolon delimiter mismatch in CSV
func testSemicolonDelimiterMismatchCSV() throws {
    let csv = "ID;Name;Age;Country\n1;Alice;30;US\n2;Bob;25;UK"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard diags.contains(where: {
        $0.severity == .notice &&
        $0.message == "Semicolon-delimited CSV detected; columns not parsed with commas" &&
        $0.line == 1
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected semicolon delimiter notice, got: \(diags)"])
    }
}

// 9. TSV with semicolons does not trigger semicolon notice
func testTSVWithSemicolonsNoNotice() throws {
    let tsv = "ColA\tColB\nval;1\tval;2"
    let diags = DocumentDiagnosticEngine.analyze(text: tsv, isTabular: true, isTSV: true, isMarkdown: false)
    guard !diags.contains(where: { $0.message.contains("Semicolon-delimited") }) else {
        throw NSError(domain: "DiagnosticTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "TSV should not trigger semicolon notice: \(diags)"])
    }
}

// 10. CSV with commas and semicolons does not trigger notice
func testCSVWithCommasAndSemicolonsNoNotice() throws {
    let csv = "ColA;Part,ColB\nval1;x,val2"
    let diags = DocumentDiagnosticEngine.analyze(text: csv, isTabular: true, isTSV: false, isMarkdown: false)
    guard !diags.contains(where: { $0.message.contains("Semicolon-delimited") }) else {
        throw NSError(domain: "DiagnosticTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "CSV with commas should not trigger semicolon notice: \(diags)"])
    }
}

// 11. Lossy UTF-8 or null bytes
func testLossyUTF8OrNullBytes() throws {
    let textWithNull = "Line 1\nHello\0World\nLine 3"
    let diags1 = DocumentDiagnosticEngine.analyze(text: textWithNull, isTabular: false, isTSV: false, isMarkdown: true)
    guard diags1.contains(where: {
        $0.severity == .warning &&
        $0.message == "Invalid UTF-8 bytes or null characters detected"
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected null bytes warning, got: \(diags1)"])
    }

    let textWithReplacement = "Line 1\nInvalid \u{FFFD} byte\nLine 3"
    let diags2 = DocumentDiagnosticEngine.analyze(text: textWithReplacement, isTabular: true, isTSV: false, isMarkdown: false)
    guard diags2.contains(where: {
        $0.severity == .warning &&
        $0.message == "Invalid UTF-8 bytes or null characters detected"
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected replacement char warning, got: \(diags2)"])
    }
}

// 12. Runaway unclosed code fence in Markdown (> 25 lines to EOF)
func testRunawayUnclosedCodeFenceMarkdown() throws {
    var lines = ["# Heading", "```swift"]
    for i in 1...28 {
        lines.append("let x\(i) = \(i)")
    }
    let md = lines.joined(separator: "\n")
    let diags = DocumentDiagnosticEngine.analyze(text: md, isTabular: false, isTSV: false, isMarkdown: true)
    guard diags.contains(where: {
        $0.severity == .notice &&
        $0.message == "Unclosed code block starting at line 2" &&
        $0.line == 2
    }) else {
        throw NSError(domain: "DiagnosticTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected unclosed code block notice at line 2, got: \(diags)"])
    }
}

// 13. Properly closed code fence in Markdown (> 25 lines) does not trigger notice
func testClosedCodeFenceMarkdownNoNotice() throws {
    var lines = ["# Heading", "```swift"]
    for i in 1...28 {
        lines.append("let x\(i) = \(i)")
    }
    lines.append("```")
    lines.append("Trailing text")
    let md = lines.joined(separator: "\n")
    let diags = DocumentDiagnosticEngine.analyze(text: md, isTabular: false, isTSV: false, isMarkdown: true)
    guard !diags.contains(where: { $0.message.contains("Unclosed code block") }) else {
        throw NSError(domain: "DiagnosticTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Closed code fence should not trigger notice: \(diags)"])
    }
}

// 14. Short unclosed code fence (<= 25 lines to EOF) does not trigger notice
func testShortUnclosedCodeFenceNoNotice() throws {
    var lines = ["# Heading", "```swift"]
    for i in 1...10 {
        lines.append("let x\(i) = \(i)")
    }
    let md = lines.joined(separator: "\n")
    let diags = DocumentDiagnosticEngine.analyze(text: md, isTabular: false, isTSV: false, isMarkdown: true)
    guard !diags.contains(where: { $0.message.contains("Unclosed code block") }) else {
        throw NSError(domain: "DiagnosticTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Short code fence should not trigger notice: \(diags)"])
    }
}

// 15. Trivial quirks in normal Markdown (bold, lists, etc.) do NOT trigger any warnings
func testCleanMarkdownNoDiagnostics() throws {
    let md = """
    # Sample Document
    This is **bold** and *italic* text.
    - Item 1
    - Item 2, with comma
    1. First
    2. Second
    `inline code` is fine.
    """
    let diags = DocumentDiagnosticEngine.analyze(text: md, isTabular: false, isTSV: false, isMarkdown: true)
    guard diags.isEmpty else {
        throw NSError(domain: "DiagnosticTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected zero diagnostics for clean markdown, got: \(diags)"])
    }
}

let tests: [(String, () throws -> Void)] = [
    ("testUnclosedQuoteAtEOFCSV", testUnclosedQuoteAtEOFCSV),
    ("testUnclosedQuoteAtEOFTSV", testUnclosedQuoteAtEOFTSV),
    ("testClosedMultilineQuoteCSV", testClosedMultilineQuoteCSV),
    ("testInconsistentColumnOverflowCSV", testInconsistentColumnOverflowCSV),
    ("testInconsistentColumnOverflowTSV", testInconsistentColumnOverflowTSV),
    ("testSingleColumnHeaderNoOverflowWarning", testSingleColumnHeaderNoOverflowWarning),
    ("testRaggedRowsFewerColumnsNoWarning", testRaggedRowsFewerColumnsNoWarning),
    ("testSemicolonDelimiterMismatchCSV", testSemicolonDelimiterMismatchCSV),
    ("testTSVWithSemicolonsNoNotice", testTSVWithSemicolonsNoNotice),
    ("testCSVWithCommasAndSemicolonsNoNotice", testCSVWithCommasAndSemicolonsNoNotice),
    ("testLossyUTF8OrNullBytes", testLossyUTF8OrNullBytes),
    ("testRunawayUnclosedCodeFenceMarkdown", testRunawayUnclosedCodeFenceMarkdown),
    ("testClosedCodeFenceMarkdownNoNotice", testClosedCodeFenceMarkdownNoNotice),
    ("testShortUnclosedCodeFenceNoNotice", testShortUnclosedCodeFenceNoNotice),
    ("testCleanMarkdownNoDiagnostics", testCleanMarkdownNoDiagnostics)
]

print("=== DocumentDiagnosticEngineTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passed += 1
    }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count {
    exit(1)
}
