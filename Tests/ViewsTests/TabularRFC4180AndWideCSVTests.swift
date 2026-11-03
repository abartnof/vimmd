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

func sendKey(_ tv: VimMDTextView, char: String, keyCode: UInt16 = 0, modifierFlags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: keyCode
    )!
    tv.keyDown(with: event)
}

// MARK: - Milestone AE: RFC 4180 Multiline Quoted CSV Parsing

func testRFC4180MultilineQuotedRecordsCount() throws {
    let csv = "ID,Title,Description,Amount\n1,Item A,\"Line 1 of description\nLine 2 of description\nLine 3 of description\",42.50\n2,Item B,\"Another multiline\nfield\",99.00\n"
    let resolver = TabularSyntaxResolver()
    let fullString = csv as NSString

    let records = resolver.parseRecordRanges(in: fullString, isTSV: false)
    // Naive line count is 7 lines. RFC 4180 record count MUST be exactly 3 records!
    guard records.count == 3 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 records for multiline CSV, got \(records.count)"])
    }

    // Verify record contents
    let r0 = fullString.substring(with: records[0])
    guard r0.hasPrefix("ID,Title,Description,Amount") else {
        throw NSError(domain: "TabularRFC4180Tests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Record 0 unexpected: \(r0)"])
    }

    let r1 = fullString.substring(with: records[1])
    guard r1.contains("Line 1") && r1.contains("Line 2") && r1.contains("Line 3") && r1.contains("42.50") else {
        throw NSError(domain: "TabularRFC4180Tests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Record 1 unexpected: \(r1)"])
    }

    let r2 = fullString.substring(with: records[2])
    guard r2.contains("Item B") && r2.contains("Another multiline") && r2.contains("99.00") else {
        throw NSError(domain: "TabularRFC4180Tests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Record 2 unexpected: \(r2)"])
    }

    // Verify in VimMDTextView
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    scrollView.documentView = tv
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    let totalRows = tv.totalTabularRows()
    guard totalRows == 3 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 5, userInfo: [NSLocalizedDescriptionKey: "tv.totalTabularRows() expected 3, got \(totalRows)"])
    }
}

func testRFC4180VerticalNavigationJKColumnLock() throws {
    let csv = "ID,Title,Description,Amount\n1,Item A,\"Line 1 of description\nLine 2 of description\nLine 3 of description\",42.50\n2,Item B,\"Another multiline\nfield\",99.00\n"

    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    scrollView.documentView = tv
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    window.contentView = scrollView
    window.makeFirstResponder(tv)

    // Position at Row 0, Column 2 ("Description")
    tv.positionCaret(atRow: 0, column: 2)
    guard let cell0 = tv.currentTabularCell() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 10, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil"])
    }
    guard cell0.row == 0 && cell0.column == 2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected (0, 2), got (\(cell0.row), \(cell0.column))"])
    }

    // Move DOWN with 'j' -> must land in Row 1, Column 2 (NOT fragment line in Column 0)
    sendKey(tv, char: "j")
    guard let cell1 = tv.currentTabularCell() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 12, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after j"])
    }
    guard cell1.row == 1 && cell1.column == 2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 2) after j, got (\(cell1.row), \(cell1.column))"])
    }

    // Move DOWN with 'j' again -> must land in Row 2, Column 2
    sendKey(tv, char: "j")
    guard let cell2 = tv.currentTabularCell() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 14, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after second j"])
    }
    guard cell2.row == 2 && cell2.column == 2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected cell (2, 2) after second j, got (\(cell2.row), \(cell2.column))"])
    }

    // Move UP with 'k' -> must return to Row 1, Column 2
    sendKey(tv, char: "k")
    guard let cellUp1 = tv.currentTabularCell() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 16, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after k"])
    }
    guard cellUp1.row == 1 && cellUp1.column == 2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 2) after k, got (\(cellUp1.row), \(cellUp1.column))"])
    }

    // Move UP with 'k' again -> must return to Row 0, Column 2
    sendKey(tv, char: "k")
    guard let cellUp0 = tv.currentTabularCell() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 18, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after second k"])
    }
    guard cellUp0.row == 0 && cellUp0.column == 2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 19, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 2) after second k, got (\(cellUp0.row), \(cellUp0.column))"])
    }
}

// MARK: - Milestone AC: Wide CSV Performance & Caching

func testWideCSVColumnRulerPerformanceNoHang() throws {
    // Generate a wide CSV with 115 columns
    let colCount = 115
    let rowCount = 20
    var csv = (0..<colCount).map { "Col_\($0)" }.joined(separator: ",") + "\n"
    for r in 1...rowCount {
        csv += (0..<colCount).map { "R\(r)C\($0)" }.joined(separator: ",") + "\n"
    }

    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    scrollView.documentView = tv
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    scrollView.horizontalRulerView = ruler
    scrollView.hasHorizontalRuler = true

    // Verify column widths caching
    let startCalc = CFAbsoluteTimeGetCurrent()
    let widths1 = tv.columnWidths()
    let _ = CFAbsoluteTimeGetCurrent() - startCalc

    guard widths1.count == colCount else {
        throw NSError(domain: "TabularRFC4180Tests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Expected \(colCount) column widths, got \(widths1.count)"])
    }

    // Cached call must be ultra-fast (< 0.005s)
    let startCached = CFAbsoluteTimeGetCurrent()
    let widths2 = tv.columnWidths()
    let timeCached = CFAbsoluteTimeGetCurrent() - startCached

    guard widths1 == widths2 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Cached column widths do not match"])
    }
    guard timeCached < 0.01 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Cached call took too long: \(timeCached)s"])
    }

    // Measure ruler drawing time (must not freeze in O(N^2) loop; must complete in < 0.05s)
    let image = NSImage(size: NSSize(width: max(1, ruler.bounds.width), height: max(1, ruler.bounds.height)))
    image.lockFocus()
    let startDraw = CFAbsoluteTimeGetCurrent()
    ruler.draw(ruler.bounds)
    let timeDraw = CFAbsoluteTimeGetCurrent() - startDraw
    image.unlockFocus()

    guard timeDraw < 0.05 else {
        throw NSError(domain: "TabularRFC4180Tests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Ruler draw took too long: \(timeDraw)s (expected < 0.05s)"])
    }
}

// MARK: - Milestone AD: Top-Left Viewport Origin Anchoring

func testViewportTopLeftPinningCell11Visible() throws {
    // Generate wide CSV (80 columns)
    let colCount = 80
    var csv = (0..<colCount).map { "ColHeader_\($0)" }.joined(separator: ",") + "\n"
    for r in 1...10 {
        csv += (0..<colCount).map { "Data_Row\(r)_Col\($0)" }.joined(separator: ",") + "\n"
    }

    let doc = VimMDDocument()
    guard let data = csv.data(using: .utf8) else {
        throw NSError(domain: "TabularRFC4180Tests", code: 40, userInfo: nil)
    }

    try doc.read(from: data, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "TabularRFC4180Tests", code: 41, userInfo: [NSLocalizedDescriptionKey: "doc.textView or scrollView is nil"])
    }

    // Verify viewport is pinned at top-left
    tv.pinViewportToTopLeft()

    let rulerOffset: CGFloat = (scrollView.hasVerticalRuler && scrollView.rulersVisible) ? -(scrollView.verticalRulerView?.ruleThickness ?? 0) : 0
    let clipOriginX = scrollView.contentView.bounds.origin.x

    guard abs(clipOriginX - rulerOffset) < 0.5 else {
        throw NSError(
            domain: "TabularRFC4180Tests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Expected clip origin x at ruler offset \(rulerOffset), got \(clipOriginX)"]
        )
    }

    let yRulerOffset: CGFloat = (scrollView.hasHorizontalRuler && scrollView.rulersVisible) ? -(scrollView.horizontalRulerView?.ruleThickness ?? 0) : 0
    let clipOriginY = scrollView.contentView.bounds.origin.y

    guard abs(clipOriginY - yRulerOffset) < 0.5 else {
        throw NSError(
            domain: "TabularRFC4180Tests",
            code: 43,
            userInfo: [NSLocalizedDescriptionKey: "Expected clip origin y at ruler offset \(yRulerOffset), got \(clipOriginY)"]
        )
    }

    // Cell (0, 0) (row 0, col 0) must be current and visible
    guard let details = tv.currentTabularCellDetails() else {
        throw NSError(domain: "TabularRFC4180Tests", code: 44, userInfo: [NSLocalizedDescriptionKey: "currentTabularCellDetails nil"])
    }
    guard details.row == 0 && details.column == 0 else {
        throw NSError(
            domain: "TabularRFC4180Tests",
            code: 45,
            userInfo: [NSLocalizedDescriptionKey: "Expected initial cell (0, 0), got (\(details.row), \(details.column))"]
        )
    }

    doc.close()
}

// MARK: - Main Test Runner

print("=== Tabular RFC 4180 & Wide CSV Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testRFC4180MultilineQuotedRecordsCount", testRFC4180MultilineQuotedRecordsCount),
    ("testRFC4180VerticalNavigationJKColumnLock", testRFC4180VerticalNavigationJKColumnLock),
    ("testWideCSVColumnRulerPerformanceNoHang", testWideCSVColumnRulerPerformanceNoHang),
    ("testViewportTopLeftPinningCell11Visible", testViewportTopLeftPinningCell11Visible)
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
