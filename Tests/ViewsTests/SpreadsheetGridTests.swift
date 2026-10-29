import Foundation
import AppKit
import Engine
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

// 1. Neutral Color Palette Tests (No rainbow colors)
func testNeutralColorStylingAndDelimiters() throws {
    let csv = "Product,Price,Quantity\nWidget,19.99,100\nGadget,29.99,50"
    let storage = NSTextStorage(string: csv)
    let resolver = TabularSyntaxResolver()
    resolver.renderTabularSyntax(in: storage, isTSV: false, wrapTableCells: false)

    // Header row font should be bold
    let headerFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let hf = headerFont, NSFontManager.shared.traits(of: hf).contains(.boldFontMask) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Header font must be bold"])
    }
    // Header background shading
    let headerBg = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
    guard headerBg != nil else {
        throw NSError(domain: "SpreadsheetGridTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Header must have subtle background shading"])
    }

    // Delimiter comma on header row (after "Product" -> index 7)
    let headerDelim = storage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
    guard headerDelim == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Delimiter must be tertiaryLabelColor, got \(String(describing: headerDelim))"])
    }

    // Data rows should be neutral (NSColor.labelColor or NSColor.textColor) and regular font
    let line2Start = 24 // "Product,Price,Quantity\n".count = 24
    let dataFont = storage.attribute(.font, at: line2Start, effectiveRange: nil) as? NSFont
    guard let df = dataFont, !NSFontManager.shared.traits(of: df).contains(.boldFontMask) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Data row font must be regular weight"])
    }

    let dataColorWidget = storage.attribute(.foregroundColor, at: line2Start, effectiveRange: nil) as? NSColor
    guard dataColorWidget == NSColor.labelColor || dataColorWidget == NSColor.textColor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Data row text must be neutral labelColor, got \(String(describing: dataColorWidget))"])
    }

    // Check col 1 on data row ("19.99" -> index 24 + 7 = 31)
    let dataColorPrice = storage.attribute(.foregroundColor, at: line2Start + 7, effectiveRange: nil) as? NSColor
    guard dataColorPrice == NSColor.labelColor || dataColorPrice == NSColor.textColor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Second column text must be neutral labelColor, got \(String(describing: dataColorPrice))"])
    }
}

// 2. Column Width Calculation (Wrap ON vs Wrap OFF)
func testColumnWidthCalculationWrapOnVsOff() throws {
    let tsv = "ID\tDescription\tStatus\n1\tA quick brown fox jumps over the lazy dog\tActive\n2\tShort\tDone"
    let storage = NSTextStorage(string: tsv)
    let resolver = TabularSyntaxResolver()

    // Wrap OFF: column widths expand to fit longest entry + padding
    let widthsWrapOff = resolver.calculateColumnWidths(in: storage, isTSV: true, wrapTableCells: false)
    guard widthsWrapOff.count == 3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns, got \(widthsWrapOff.count)"])
    }
    // Column 1 ("Description") longest entry is "A quick brown fox jumps over the lazy dog" (41 chars)
    // Font 13pt char width is ~7.8pt, 41 chars * 7.8 = ~320pt + padding >= 320pt
    guard widthsWrapOff[1] > widthsWrapOff[0] && widthsWrapOff[1] > 250.0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Wrap OFF should expand column 1 width to fit longest cell: \(widthsWrapOff[1])"])
    }

    // Wrap ON: column width should cap/wrap to default width (e.g. 240.0)
    let widthsWrapOn = resolver.calculateColumnWidths(in: storage, isTSV: true, wrapTableCells: true, defaultWrapWidth: 240.0)
    guard widthsWrapOn.count == 3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns for wrap on"])
    }
    for w in widthsWrapOn {
        guard abs(w - 240.0) < 0.01 else {
            throw NSError(domain: "SpreadsheetGridTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected wrapped column width 240.0, got \(w)"])
        }
    }
}

// 3. Gridlines Configuration in VimMDTextView
func testGridlinesConfiguration() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    textView.isTabularDocument = true
    textView.isTSV = false

    let session = VimSession(initialText: "HeaderA,HeaderB,HeaderC\nVal1,Val2,Val3\n")
    textView.session = session

    guard textView.isTabularDocument else {
        throw NSError(domain: "SpreadsheetGridTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected isTabularDocument true"])
    }

    // Ensure grid lines separator color is accessible
    let _ = NSColor.separatorColor

    // Verify row rects and column rects can be computed
    guard let row0 = textView.rowRect(for: 0), row0.height > 0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Row 0 rect must have positive height"])
    }
    guard let row1 = textView.rowRect(for: 1), row1.height > 0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Row 1 rect must have positive height"])
    }
    guard let col0 = textView.columnRect(for: 0), col0.width > 0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Col 0 rect must have positive width"])
    }
}

// 4. Dynamic Row & Column Addition As You Type
func testDynamicRowAndColumnAddition() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let session = VimSession(initialText: "ColA,ColB,ColC\n1,2,3")
    textView.session = session

    // Test Dynamic Row Addition:
    // Move to line 2 with 'G', then open new line below with 'o'
    session.feedKeys("G")
    session.feedKeys("o")
    textView.synchronizeCaretWithSession()
    textView.alignNewRowSchemaIfNeeded()

    let linesAfterO = session.serializeBuffer().split(separator: "\n", omittingEmptySubsequences: false)
    guard linesAfterO.count >= 3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Expected at least 3 lines"])
    }
    let newLine = String(linesAfterO[2])
    // Line should have 2 commas for 3 columns: ",,"
    guard newLine == ",," else {
        throw NSError(domain: "SpreadsheetGridTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected schema alignment ',,' on new line, got '\(newLine)'"])
    }

    // Caret should be at beginning of cell 0 (line 3, col 1 in 1-based Vim coordinates)
    let pos = session.cursorPosition
    guard pos.line == 3 && (pos.byteCol == 1 || pos.byteCol == 0) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Caret should be at line 3, col 1, got \(pos.line), \(pos.byteCol)"])
    }

    // Exit insert mode
    session.feedKeys("\u{1b}")
    textView.synchronizeCaretWithSession()

    // Test Dynamic Column Addition:
    // Move to header row (line 1), go to end '$', enter append 'a', type ',ColD'
    session.feedKeys("1G$a,ColD\u{1b}")
    textView.synchronizeCaretWithSession()
    textView.updateSyntaxStyling(force: true)

    let headerLine = String(session.serializeBuffer().split(separator: "\n")[0])
    guard headerLine == "ColA,ColB,ColC,ColD" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected 4 columns in header, got '\(headerLine)'"])
    }

    // Column rect for index 3 must now exist
    guard let col3Rect = textView.columnRect(for: 3), col3Rect.width > 0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Col 3 rect must exist after adding column"])
    }
}

// 5. Hover Cursors (Downward Arrow over Row 1, Rightward Arrow over Column A)
func testHoverCursors() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let session = VimSession(initialText: "HeaderA,HeaderB,HeaderC\nVal1,Val2,Val3\nVal4,Val5,Val6\n")
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    guard let row0 = textView.rowRect(for: 0),
          let row1 = textView.rowRect(for: 1),
          let col0 = textView.columnRect(for: 0),
          let col1 = textView.columnRect(for: 1) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to get row/col rects"])
    }

    // Point in Row 1 (Header row), Column 1 (HeaderB)
    let headerPoint = NSPoint(x: col1.midX, y: row0.midY)
    let cursorHeader = textView.cursorForPoint(headerPoint)
    guard cursorHeader == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected downward arrow cursor over header row"])
    }

    // Point in Column A (First column), Row 2 (Data row 1: Val1)
    let colAPoint = NSPoint(x: col0.midX, y: row1.midY)
    let cursorColA = textView.cursorForPoint(colAPoint)
    guard cursorColA == VimMDTextView.rightwardArrowCursor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected rightward arrow cursor over Column A data row"])
    }
}

// 6. Quick Click-to-Copy Gestures (Row & Column)
func testClickToCopyColumnAndRow() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "Name,Department,Salary\nAlice,Engineering,150k\nBob,Design,120k\nCarol,Product,130k\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    var feedbackMsg: String?
    textView.onFlashFeedback = { msg in
        feedbackMsg = msg
    }

    // Click Column 1 ("Department")
    let col1Text = textView.copyColumnRange(from: 1, to: 1)
    guard col1Text == "Department\nEngineering\nDesign\nProduct" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Unexpected copied column text: '\(col1Text)'"])
    }

    // Check status feedback message
    guard let msg = feedbackMsg, msg.contains("Department") else {
        throw NSError(domain: "SpreadsheetGridTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Expected status message for Department column copy, got \(String(describing: feedbackMsg))"])
    }

    // Click Row 2 ("Bob,Design,120k")
    feedbackMsg = nil
    let row2Text = textView.copyRowRange(from: 2, to: 2)
    guard row2Text == "Bob,Design,120k" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "Unexpected copied row text: '\(row2Text)'"])
    }
    guard let msgRow = feedbackMsg, msgRow.contains("Row 3") else {
        throw NSError(domain: "SpreadsheetGridTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Expected status message for Row 3 copy, got \(String(describing: feedbackMsg))"])
    }
}

// 7. Multi-Row Dragging over Column A
func testMultiRowDraggingOverColumnA() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "ID,Name\n1,Alice\n2,Bob\n3,Carol\n4,David\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    var feedbackMsg: String?
    textView.onFlashFeedback = { msg in
        feedbackMsg = msg
    }

    guard let row1 = textView.rowRect(for: 1),
          let row3 = textView.rowRect(for: 3),
          let col0 = textView.columnRect(for: 0) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Missing rects"])
    }

    // Start drag at Row 1 in Column A
    let startPt = NSPoint(x: col0.midX, y: row1.midY)
    _ = textView.handleTabularMouseDown(at: startPt)

    // Drag to Row 3
    let dragPt = NSPoint(x: col0.midX, y: row3.midY)
    textView.handleTabularMouseDragged(to: dragPt)

    guard textView.activeRowDragRange == 1...3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Expected activeRowDragRange 1...3, got \(String(describing: textView.activeRowDragRange))"])
    }

    // Mouse up
    textView.handleTabularMouseUp(at: dragPt)

    let pbString = NSPasteboard.general.string(forType: .string)
    guard pbString == "1,Alice\n2,Bob\n3,Carol" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Unexpected pasteboard content: '\(String(describing: pbString))'"])
    }

    guard let msg = feedbackMsg, msg.contains("Rows 2–4") else {
        throw NSError(domain: "SpreadsheetGridTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Expected status message mentioning Rows 2–4, got \(String(describing: feedbackMsg))"])
    }
}

// 8. Multi-Column Dragging over Row 1
func testMultiColumnDraggingOverRow1() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "A,B,C,D\n1,2,3,4\n5,6,7,8\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    var feedbackMsg: String?
    textView.onFlashFeedback = { msg in
        feedbackMsg = msg
    }

    guard let row0 = textView.rowRect(for: 0),
          let col1 = textView.columnRect(for: 1),
          let col2 = textView.columnRect(for: 2) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Missing rects"])
    }

    // Start drag at Column 1 in Row 1
    let startPt = NSPoint(x: col1.midX, y: row0.midY)
    _ = textView.handleTabularMouseDown(at: startPt)

    // Drag to Column 2
    let dragPt = NSPoint(x: col2.midX, y: row0.midY)
    textView.handleTabularMouseDragged(to: dragPt)

    guard textView.activeColDragRange == 1...2 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Expected activeColDragRange 1...2, got \(String(describing: textView.activeColDragRange))"])
    }

    // Mouse up
    textView.handleTabularMouseUp(at: dragPt)

    let pbString = NSPasteboard.general.string(forType: .string)
    // Multi-column extract should be comma-delimited across rows:
    // Row 1: B,C
    // Row 2: 2,3
    // Row 3: 6,7
    guard pbString == "B,C\n2,3\n6,7" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 72, userInfo: [NSLocalizedDescriptionKey: "Unexpected multi-col pasteboard: '\(String(describing: pbString))'"])
    }

    guard let msg = feedbackMsg, (msg.contains("Columns B–C") || msg.contains("Columns")) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 73, userInfo: [NSLocalizedDescriptionKey: "Expected status message for columns drag, got \(String(describing: feedbackMsg))"])
    }
}

print("=== SpreadsheetGrid Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testNeutralColorStylingAndDelimiters", testNeutralColorStylingAndDelimiters),
    ("testColumnWidthCalculationWrapOnVsOff", testColumnWidthCalculationWrapOnVsOff),
    ("testGridlinesConfiguration", testGridlinesConfiguration),
    ("testDynamicRowAndColumnAddition", testDynamicRowAndColumnAddition),
    ("testHoverCursors", testHoverCursors),
    ("testClickToCopyColumnAndRow", testClickToCopyColumnAndRow),
    ("testMultiRowDraggingOverColumnA", testMultiRowDraggingOverColumnA),
    ("testMultiColumnDraggingOverRow1", testMultiColumnDraggingOverRow1)
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
