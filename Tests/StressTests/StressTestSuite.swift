import Foundation
import AppKit
import Engine
import Views
import App
import CBridge

// ============================================================================
// STRESS TEST BENCHMARK HARNESS & METRICS COLLECTOR
// ============================================================================

public struct BenchmarkResult {
    public let name: String
    public let elapsedMs: Double
    public let budgetMs: Double
    public let passed: Bool
    public let detail: String
}

public final class StressBenchmarkRunner {
    public static let shared = StressBenchmarkRunner()

    public private(set) var results: [BenchmarkResult] = []

    public func benchmark(
        name: String,
        budgetMs: Double,
        detail: String = "",
        block: () throws -> Void
    ) -> Bool {
        print("\n[STRESS BENCHMARK] Starting: \(name)")
        print("  Budget: < \(String(format: "%.1f", budgetMs)) ms")

        let startTime = DispatchTime.now()
        var testError: Error? = nil

        do {
            try block()
        } catch {
            testError = error
        }

        let endTime = DispatchTime.now()
        let elapsedNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let elapsedMs = Double(elapsedNanos) / 1_000_000.0

        let withinBudget = elapsedMs <= budgetMs
        let testPassed = (testError == nil) && withinBudget

        let statusStr = testPassed ? "PASS" : "FAIL"
        print("  Elapsed: \(String(format: "%.2f", elapsedMs)) ms [\(statusStr)]")

        if let error = testError {
            print("  Error: \(error)")
        } else if !withinBudget {
            print("  Regression: Elapsed time \(String(format: "%.2f", elapsedMs)) ms exceeded budget of \(String(format: "%.1f", budgetMs)) ms")
        }

        results.append(BenchmarkResult(
            name: name,
            elapsedMs: elapsedMs,
            budgetMs: budgetMs,
            passed: testPassed,
            detail: detail
        ))

        return testPassed
    }

    public func printSummaryReport() {
        print("\n" + String(repeating: "=", count: 80))
        print("                VIMMD STRESS & PERFORMANCE BUDGET REPORT                ")
        print(String(repeating: "=", count: 80))

        let total = results.count
        let passed = results.filter { $0.passed }.count
        let failed = total - passed

        for res in results {
            let icon = res.passed ? "  [✓] " : "  [✗] "
            let timeInfo = "\(String(format: "%6.2f", res.elapsedMs)) ms / budget < \(String(format: "%5.1f", res.budgetMs)) ms"
            print("\(icon)\(res.name.padding(toLength: 46, withPad: " ", startingAt: 0)) \(timeInfo)")
            if !res.detail.isEmpty {
                print("      Note: \(res.detail)")
            }
        }

        print(String(repeating: "-", count: 80))
        print("Total Stress Benchmarks: \(total)")
        print("Passed:                  \(passed) (\(String(format: "%.1f", Double(passed) / Double(max(1, total)) * 100.0))%)")
        print("Failed / Over Budget:    \(failed)")
        print(String(repeating: "=", count: 80) + "\n")
    }
}

func stressFail(_ message: String) -> NSError {
    return NSError(domain: "StressTestSuite", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
}

// ============================================================================
// HELPER FACTORIES
// ============================================================================

func createTestWindow(width: CGFloat = 800, height: CGFloat = 600) -> (NSWindow, VimMDTextView) {
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: width, height: height),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    scrollView.documentView = tv
    window.contentView = scrollView
    return (window, tv)
}

// ============================================================================
// DIMENSION 1: FILE VOLUME & SCALE (10,000+ LINES)
// ============================================================================

func testDimension1_MarkdownVolumeLoadAndIndex() throws {
    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 1.1: 10,000-Line Markdown Load & Index",
        budgetMs: 250.0,
        detail: "10k lines with mixed headers, task lists, code fences, and paragraphs"
    ) {
        var lines: [String] = []
        lines.reserveCapacity(10_000)

        for i in 1...10_000 {
            if i % 100 == 1 {
                lines.append("# Section \(i / 100): Volume Scaling Test Document")
            } else if i % 50 == 0 {
                lines.append("## Subsection \(i): Sub-heading for Line Scale")
            } else if i % 20 == 0 {
                lines.append("- [x] Completed task checklist item \(i) with **bold status**")
            } else if i % 10 == 0 {
                lines.append("```swift\nlet val\(i) = \(i)\n```")
            } else {
                lines.append("Paragraph \(i): Performance testing differential line indexing and Unicode coordinate resolution across high line volume.")
            }
        }
        let docText = lines.joined(separator: "\n")

        let t0 = DispatchTime.now()
        let session = VimSession(initialText: docText)
        let resolver = DocumentCoordinateResolver(documentText: docText)
        let t1 = DispatchTime.now()

        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0

        guard session.lineCount >= 10_000 else {
            throw stressFail("Expected session.lineCount >= 10000, got \(session.lineCount)")
        }
        guard resolver.lineCount >= 10_000 else {
            throw stressFail("Expected resolver.lineCount >= 10000, got \(resolver.lineCount)")
        }

        print("      Created \(session.lineCount) lines in \(String(format: "%.2f", elapsed)) ms")
        if elapsed > 250.0 {
            throw stressFail("Initialization and indexing took \(elapsed) ms (budget: 250ms)")
        }
    }
}

func testDimension1_PlainTextVolumeLoadAndIndex() throws {
    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 1.2: 20,000-Line Plain Text Load & Index",
        budgetMs: 250.0,
        detail: "20,000 continuous lines indexing and coordinate resolution"
    ) {
        var lines: [String] = []
        lines.reserveCapacity(20_000)
        for i in 1...20_000 {
            lines.append("Line \(i): Standard log and plain text record entry with identifier 0x\(String(i, radix: 16))")
        }
        let docText = lines.joined(separator: "\n")

        let t0 = DispatchTime.now()
        let session = VimSession(initialText: docText)
        let resolver = DocumentCoordinateResolver(documentText: docText)
        let t1 = DispatchTime.now()

        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0

        guard session.lineCount == 20_000 else {
            throw stressFail("Expected 20000 lines, got \(session.lineCount)")
        }
        guard resolver.lineCount == 20_000 else {
            throw stressFail("Expected resolver 20000 lines, got \(resolver.lineCount)")
        }

        print("      Created \(session.lineCount) lines in \(String(format: "%.2f", elapsed)) ms")
        if elapsed > 250.0 {
            throw stressFail("Plain text indexing took \(elapsed) ms (budget: 250ms)")
        }
    }
}

func testDimension1_RapidNavigationAndCaretFidelity() throws {
    var lines: [String] = []
    lines.reserveCapacity(10_000)
    for i in 1...10_000 {
        lines.append("Record line number \(i) with data payload")
    }
    let text = lines.joined(separator: "\n")

    let (_, tv) = createTestWindow()
    tv.wrapLines = false
    let session = VimSession(initialText: text)
    tv.session = session
    tv.layoutManager?.ensureLayout(for: tv.textContainer!)

    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 1.3: Rapid Navigation & Caret Fidelity (G, gg, 5000j)",
        budgetMs: 100.0,
        detail: "Top-to-bottom rapid jumps with 100% caret and coordinate parity"
    ) {
        // 1. Jump to bottom: G
        session.feedKeys("G")
        tv.synchronizeCaretWithSession()
        guard session.cursorLine == 10_000 else {
            throw stressFail("Expected cursor at line 10000 after 'G', got \(session.cursorLine)")
        }
        let vimPosBottom = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: tv.selectedRange().location)
        guard vimPosBottom.line == 10_000 else {
            throw stressFail("Expected caret line 10000, got \(vimPosBottom.line)")
        }

        // 2. Jump to top: gg
        session.feedKeys("gg")
        tv.synchronizeCaretWithSession()
        guard session.cursorLine == 1 else {
            throw stressFail("Expected cursor at line 1 after 'gg', got \(session.cursorLine)")
        }
        let vimPosTop = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: tv.selectedRange().location)
        guard vimPosTop.line == 1 else {
            throw stressFail("Expected caret line 1, got \(vimPosTop.line)")
        }

        // 3. Jump down 5000 lines: 5000j
        session.feedKeys("5000j")
        tv.synchronizeCaretWithSession()
        guard session.cursorLine == 5001 else {
            throw stressFail("Expected cursor at line 5001 after '5000j', got \(session.cursorLine)")
        }
        let vimPosMid = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: tv.selectedRange().location)
        guard vimPosMid.line == 5001 else {
            throw stressFail("Expected caret line 5001, got \(vimPosMid.line)")
        }
    }
}

// ============================================================================
// DIMENSION 2: PATHOLOGICAL ULTRA-LONG LINES (50,000+ CHARS)
// ============================================================================

func testDimension2_UltraLongMarkdownLineRegexPerformance() throws {
    let tokens = [
        "**bold token** ",
        "*italic token* ",
        "`inline_code_block()` ",
        "[Hyperlink](https://vimmd.org/spec) ",
        "~~strikethrough~~ ",
        "normal narrative text phrase "
    ]
    var line = "# "
    while line.count < 60_000 {
        line += tokens[line.count % tokens.count]
    }

    let resolver = MarkdownSyntaxResolver()
    let runner = StressBenchmarkRunner.shared

    _ = runner.benchmark(
        name: "Dim 2.1: 50,000+ Char Markdown Line Delimiter Extraction",
        budgetMs: 150.0,
        detail: "Continuous 60,000-char line with dense markdown tokens without backtracking stalls"
    ) {
        let t0 = DispatchTime.now()
        let delimiters = resolver.stylingRanges(in: line)
        let t1 = DispatchTime.now()

        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0

        guard delimiters.count > 1000 else {
            throw stressFail("Expected > 1000 delimiters in 60k char line, got \(delimiters.count)")
        }

        print("      Extracted \(delimiters.count) delimiters from \(line.count)-char line in \(String(format: "%.2f", elapsed)) ms")
        if elapsed > 150.0 {
            throw stressFail("Regex extraction took \(elapsed) ms (budget: 150ms)")
        }
    }
}

func testDimension2_UltraLongLineTextKitLayoutAndRender() throws {
    let tokens = ["**bold** ", "*italic* ", "`code` ", "[link](https://example.com) ", "word "]
    var line = ""
    while line.count < 50_000 {
        line += tokens[line.count % tokens.count]
    }

    let (_, tv) = createTestWindow()
    tv.documentSyntaxType = .markdown
    let session = VimSession(initialText: line)
    tv.session = session

    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 2.2: 50,000+ Char Line TextKit Layout & Syntax Styling",
        budgetMs: 150.0,
        detail: "AppKit NSTextView & LayoutManager glyph generation on ultra-long line"
    ) {
        tv.updateSyntaxStyling(force: true)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
    }
}

// ============================================================================
// DIMENSION 3: HIGH-FREQUENCY KEYSTROKE & CHURN STRESS
// ============================================================================

func testDimension3_HighFrequencyKeystrokesAndQueueChurn() throws {
    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 3.1: 1,000 Continuous Keystrokes & Mode Churn",
        budgetMs: 1000.0,
        detail: "1,000 keystrokes (insert, x, dw, r, esc, motions) averaging < 1ms/key"
    ) {
        let text = "The quick brown fox jumps over the lazy dog.\nRepeated line for high frequency typing and mutation.\n"
        let (_, tv) = createTestWindow()
        let session = VimSession(initialText: text)
        tv.session = session

        let t0 = DispatchTime.now()

        // Stream 1,000 keys in rapid bursts
        for _ in 1...200 {
            // 1. Enter insert mode and type a short word
            session.feedKeys("iabc")
            // 2. Escape to normal mode
            session.feedKeys("\u{1b}")
            // 3. Motion right and delete char
            session.feedKeys("lx")
            // 4. Motion to next word and replace char
            session.feedKeys("wre")
        }

        tv.synchronizeCaretWithSession()

        let t1 = DispatchTime.now()
        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
        let totalKeys = 200 * 7 // i, a, b, c, Esc, l, x, w, r, e = 10 keys per iteration -> 2,000 keys
        let msPerKey = elapsed / Double(totalKeys)

        print("      Processed \(totalKeys) keys in \(String(format: "%.2f", elapsed)) ms (\(String(format: "%.3f", msPerKey)) ms/key)")

        if msPerKey > 1.0 {
            throw stressFail("Average keystroke latency \(msPerKey) ms exceeds 1.0 ms budget")
        }

        // Verify state parity
        let cText = session.serializeBuffer()
        let swiftText = tv.string
        guard cText == swiftText else {
            throw stressFail("C engine buffer and Swift textStorage diverged after 2,000 keystrokes!")
        }
    }
}

// ============================================================================
// DIMENSION 4: MASSIVE TABULAR GRID SCALING (CSV / TSV)
// ============================================================================

func testDimension4_MassiveTabularGridParsingAndColumnResolution() throws {
    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 4.1: 5,000 Rows x 20 Cols (100,000 Cells) Column Calculation",
        budgetMs: 350.0,
        detail: "100k cell CSV column width calculation and cell wrapping"
    ) {
        var lines: [String] = []
        lines.reserveCapacity(5000)

        // Header row: 20 columns
        let headers = (1...20).map { "Column_\($0)" }.joined(separator: ",")
        lines.append(headers)

        // 4,999 data rows
        for r in 1...4999 {
            let row = (1...20).map { c in "Val_\(r)_\(c)" }.joined(separator: ",")
            lines.append(row)
        }
        let csvText = lines.joined(separator: "\n")
        let storage = NSTextStorage(string: csvText)
        let resolver = TabularSyntaxResolver()

        let t0 = DispatchTime.now()
        let widths = resolver.calculateColumnWidths(
            in: storage,
            isTSV: false,
            wrapTableCells: true
        )
        let t1 = DispatchTime.now()

        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
        print("      Resolved \(widths.count) columns for 5,000 rows in \(String(format: "%.2f", elapsed)) ms")

        guard widths.count == 20 else {
            throw stressFail("Expected 20 column widths, got \(widths.count)")
        }

        if elapsed > 350.0 {
            throw stressFail("Column width calculation took \(elapsed) ms (budget: 350ms)")
        }
    }
}

func testDimension4_WideTableGridScaling() throws {
    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 4.2: Wide Table Grid (120 Columns x 100 Rows)",
        budgetMs: 200.0,
        detail: "120 distinct columns width resolution and ruler layout"
    ) {
        var lines: [String] = []
        lines.reserveCapacity(100)

        let headers = (1...120).map { "ColHeader_\($0)" }.joined(separator: ",")
        lines.append(headers)

        for r in 1...99 {
            let row = (1...120).map { c in "R\(r)C\(c)" }.joined(separator: ",")
            lines.append(row)
        }
        let csvText = lines.joined(separator: "\n")
        let storage = NSTextStorage(string: csvText)
        let resolver = TabularSyntaxResolver()

        let t0 = DispatchTime.now()
        let widths = resolver.calculateColumnWidths(
            in: storage,
            isTSV: false,
            wrapTableCells: false
        )
        let t1 = DispatchTime.now()

        let elapsed = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
        print("      Resolved \(widths.count) columns across 100 rows in \(String(format: "%.2f", elapsed)) ms")

        guard widths.count == 120 else {
            throw stressFail("Expected 120 column widths, got \(widths.count)")
        }

        if elapsed > 200.0 {
            throw stressFail("Wide table calculation took \(elapsed) ms (budget: 200ms)")
        }
    }
}

func testDimension4_MassiveTableMouseClickResolution() throws {
    var lines: [String] = []
    lines.reserveCapacity(5000)

    let headers = (1...20).map { "Col_\($0)" }.joined(separator: ",")
    lines.append(headers)

    for r in 1...4999 {
        let row = (1...20).map { c in "Cell_\(r)_\(c)" }.joined(separator: ",")
        lines.append(row)
    }
    let csvText = lines.joined(separator: "\n")

    let (_, tv) = createTestWindow(width: 1000, height: 800)
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    let session = VimSession(initialText: csvText)
    tv.session = session
    tv.layoutManager?.ensureLayout(for: tv.textContainer!)

    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 4.3: Massive Table Mouse Click Cell Caret Resolution",
        budgetMs: 100.0,
        detail: "Hit testing and caret positioning at row 0, row 2500, row 4999 in < 15ms"
    ) {
        // 1. Click Row 0, Col 0
        tv.positionCaret(atRow: 0, column: 0)
        guard session.cursorLine == 1 else {
            throw stressFail("Expected cursor at line 1 after click on row 0, got \(session.cursorLine)")
        }

        // 2. Click Row 2500, Col 5
        tv.positionCaret(atRow: 2500, column: 5)
        guard session.cursorLine == 2501 else {
            throw stressFail("Expected cursor at line 2501 after click on row 2500, got \(session.cursorLine)")
        }

        // 3. Click Row 4999, Col 19
        tv.positionCaret(atRow: 4999, column: 19)
        guard session.cursorLine == 5000 else {
            throw stressFail("Expected cursor at line 5000 after click on row 4999, got \(session.cursorLine)")
        }

        // 4. Test point-based hit testing: rowIndex(at:) & columnIndex(at:)
        let pt0 = NSPoint(x: 20, y: 5)
        let resolvedRow0 = tv.rowIndex(at: pt0, clamped: true)
        guard resolvedRow0 == 0 else {
            throw stressFail("Expected rowIndex 0 at pt \(pt0), got \(String(describing: resolvedRow0))")
        }

        let resolvedCol0 = tv.columnIndex(at: pt0, clamped: true)
        guard resolvedCol0 == 0 else {
            throw stressFail("Expected columnIndex 0 at pt \(pt0), got \(String(describing: resolvedCol0))")
        }
    }
}

// ============================================================================
// DIMENSION 5: DEEP UNDO/REDO & EX-COMMAND PIPELINES
// ============================================================================

func testDimension5_DeepUndoRedo500Steps() throws {
    let initialText = String(repeating: "abcdefghij", count: 50) + "\n"
    let (_, tv) = createTestWindow()
    let session = VimSession(initialText: initialText)
    tv.session = session

    let runner = StressBenchmarkRunner.shared
    _ = runner.benchmark(
        name: "Dim 5.1: 500-Step Deep Undo/Redo Fidelity",
        budgetMs: 750.0,
        detail: "500 mutations followed by full 500-step undo and redo with zero buffer drift"
    ) {
        // 1. Perform 500 distinct mutations (e.g., delete characters with 'x')
        for _ in 1...500 {
            session.feedKeys("x")
        }
        tv.synchronizeCaretWithSession()

        let stateAfter500 = session.serializeBuffer()
        guard tv.string == stateAfter500 else {
            throw stressFail("TextView string does not match C bridge buffer after 500 mutations!")
        }

        // 2. Continuous 500-step Undo
        let t0Undo = DispatchTime.now()
        for _ in 1...500 {
            session.undo()
        }
        tv.synchronizeCaretWithSession()
        let t1Undo = DispatchTime.now()
        let undoElapsed = Double(t1Undo.uptimeNanoseconds - t0Undo.uptimeNanoseconds) / 1_000_000.0

        let stateAfterUndo = session.serializeBuffer()
        guard stateAfterUndo == initialText else {
            throw stressFail("Document did not return to initial baseline after 500 undo steps!\nExpected length: \(initialText.count)\nGot length: \(stateAfterUndo.count)")
        }
        guard tv.string == initialText else {
            throw stressFail("TextView string did not revert to baseline after 500 undos!")
        }
        print("      500 undo steps executed in \(String(format: "%.2f", undoElapsed)) ms")

        // 3. Continuous 500-step Redo
        let t0Redo = DispatchTime.now()
        for _ in 1...500 {
            session.redo()
        }
        tv.synchronizeCaretWithSession()
        let t1Redo = DispatchTime.now()
        let redoElapsed = Double(t1Redo.uptimeNanoseconds - t0Redo.uptimeNanoseconds) / 1_000_000.0

        let stateAfterRedo = session.serializeBuffer()
        guard stateAfterRedo == stateAfter500 else {
            throw stressFail("Document did not restore to mutated state after 500 redo steps!")
        }
        guard tv.string == stateAfter500 else {
            throw stressFail("TextView string did not restore after 500 redos!")
        }
        print("      500 redo steps executed in \(String(format: "%.2f", redoElapsed)) ms")
    }
}

func testDimension5_BulkExSubstitutionsAndSorting() throws {
    var lines: [String] = []
    lines.reserveCapacity(5000)

    // Seed unsorted lines with target token
    for i in (1...5000).reversed() {
        lines.append("entry_\(String(format: "%05d", i))_target_token")
    }
    let text = lines.joined(separator: "\n")

    let (_, tv) = createTestWindow()
    tv.wrapLines = false
    let session = VimSession(initialText: text)
    tv.session = session

    let runner = StressBenchmarkRunner.shared

    // 1. Bulk Ex substitution: :%s/target_token/replacement_value/g
    _ = runner.benchmark(
        name: "Dim 5.2: Bulk Ex-Substitution (:%s) over 5,000 Lines",
        budgetMs: 150.0,
        detail: "Global substitution on 5,000 lines"
    ) {
        session.executeEx("%s/target_token/replacement_value/g")
        tv.synchronizeCaretWithSession()
    }

    let bufferAfterSub = session.serializeBuffer()
    guard !bufferAfterSub.contains("target_token") else {
        throw stressFail("Ex substitution failed: 'target_token' still present in buffer")
    }
    guard bufferAfterSub.contains("replacement_value") else {
        throw stressFail("Ex substitution failed: 'replacement_value' missing in buffer")
    }
    guard tv.string == bufferAfterSub else {
        throw stressFail("TextView string does not match substituted buffer!")
    }

    // 2. Bulk Ex sort: :sort
    _ = runner.benchmark(
        name: "Dim 5.3: Bulk Ex-Sort (:sort) over 5,000 Lines",
        budgetMs: 150.0,
        detail: "Lexicographical sort on 5,000 lines"
    ) {
        session.executeEx("sort")
        tv.synchronizeCaretWithSession()
    }

    let bufferAfterSort = session.serializeBuffer()
    guard bufferAfterSort.hasPrefix("entry_00001_replacement_value") else {
        let firstLine = bufferAfterSort.components(separatedBy: "\n").first ?? ""
        throw stressFail("Ex sort failed: first line is '\(firstLine)', expected 'entry_00001_replacement_value'")
    }
    guard tv.string == bufferAfterSort else {
        throw stressFail("TextView string does not match sorted buffer!")
    }
}

// ============================================================================
// MAIN EXECUTION RUNNER
// ============================================================================

print("================================================================================")
print("             STARTING VIMMD PERFORMANCE BUDGET & STRESS TEST SUITE              ")
print("================================================================================")

var allPassed = true

let tests: [(String, () throws -> Void)] = [
    // Dimension 1
    ("testDimension1_MarkdownVolumeLoadAndIndex", testDimension1_MarkdownVolumeLoadAndIndex),
    ("testDimension1_PlainTextVolumeLoadAndIndex", testDimension1_PlainTextVolumeLoadAndIndex),
    ("testDimension1_RapidNavigationAndCaretFidelity", testDimension1_RapidNavigationAndCaretFidelity),

    // Dimension 2
    ("testDimension2_UltraLongMarkdownLineRegexPerformance", testDimension2_UltraLongMarkdownLineRegexPerformance),
    ("testDimension2_UltraLongLineTextKitLayoutAndRender", testDimension2_UltraLongLineTextKitLayoutAndRender),

    // Dimension 3
    ("testDimension3_HighFrequencyKeystrokesAndQueueChurn", testDimension3_HighFrequencyKeystrokesAndQueueChurn),

    // Dimension 4
    ("testDimension4_MassiveTabularGridParsingAndColumnResolution", testDimension4_MassiveTabularGridParsingAndColumnResolution),
    ("testDimension4_WideTableGridScaling", testDimension4_WideTableGridScaling),
    ("testDimension4_MassiveTableMouseClickResolution", testDimension4_MassiveTableMouseClickResolution),

    // Dimension 5
    ("testDimension5_DeepUndoRedo500Steps", testDimension5_DeepUndoRedo500Steps),
    ("testDimension5_BulkExSubstitutionsAndSorting", testDimension5_BulkExSubstitutionsAndSorting),
]

for (name, test) in tests {
    do {
        try test()
    } catch {
        print("[FAIL] \(name) threw error: \(error)")
        allPassed = false
    }
}

StressBenchmarkRunner.shared.printSummaryReport()

let totalCount = StressBenchmarkRunner.shared.results.count
let passedCount = StressBenchmarkRunner.shared.results.filter { $0.passed }.count

if passedCount == totalCount && allPassed {
    print("[SUCCESS] All \(passedCount)/\(totalCount) stress tests and performance budgets PASSED!\n")
    exit(0)
} else {
    print("[FAILURE] \(totalCount - passedCount) stress tests or performance budgets FAILED!\n")
    exit(1)
}
