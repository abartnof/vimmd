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

    // Wrap ON: column widths stay at defaultWrapWidth (240.0) so long cells wrap inside the column
    let widthsWrapOn = resolver.calculateColumnWidths(in: storage, isTSV: true, wrapTableCells: true, defaultWrapWidth: 240.0)
    guard widthsWrapOn.count == 3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns for wrap on"])
    }
    for (idx, w) in widthsWrapOn.enumerated() {
        guard abs(w - 240.0) < 0.01 else {
            throw NSError(domain: "SpreadsheetGridTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Wrap ON should keep column \(idx) at defaultWrapWidth 240.0, got \(widthsWrapOn)"])
        }
    }
}

// 2b. Long Cell Text Wraps Inside Column Boundary and Expands Row Height
func testLongCellDoesNotSpillAndPreservesColumnAlignment() throws {
    let csv = "ColA,ColB,ColC\n\"Avoids as much CO2e as 2,192 trees absorb in a day\",$357,$420\nShort,ValB,ValC\n"
    let storage = NSTextStorage(string: csv)
    let resolver = TabularSyntaxResolver()

    let widths = resolver.calculateColumnWidths(in: storage, isTSV: false, wrapTableCells: true, defaultWrapWidth: 240.0)
    guard widths.count == 3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns, got \(widths.count)"])
    }

    // All columns stay at defaultWrapWidth 240.0 when wrapTableCells == true
    for (idx, w) in widths.enumerated() {
        guard abs(w - 240.0) < 0.01 else {
            throw NSError(domain: "SpreadsheetGridTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Column \(idx) should stay at defaultWrapWidth 240.0, got \(widths)"])
        }
    }

    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false
    textView.wrapTableCells = true
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    guard let row0 = textView.rowRect(for: 0),
          let row1 = textView.rowRect(for: 1),
          let row2 = textView.rowRect(for: 2),
          let col0 = textView.columnRect(for: 0),
          let col1 = textView.columnRect(for: 1) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Missing row or column rects"])
    }

    guard abs(col0.width - 240.0) < 0.01 && abs(col1.minX - col0.maxX) < 0.01 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "Column alignment broken: col0=\(col0), col1=\(col1)"])
    }
    guard row1.height > 24.0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 29, userInfo: [NSLocalizedDescriptionKey: "Long wrapped cell in row 1 must expand row height > 24.0, got \(row1.height)"])
    }
    guard row0.height <= 22.0 && abs(row2.minY - row1.maxY) < 0.5 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Unexpected row heights/positions: row0=\(row0), row1=\(row1), row2=\(row2)"])
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

// 5. Hover Cursors (Downward Arrow over ColumnLetterRulerView, Rightward Arrow over LineNumberRulerView)
func testHoverCursors() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    textView.isTSV = false

    let session = VimSession(initialText: "HeaderA,HeaderB,HeaderC\nVal1,Val2,Val3\nVal4,Val5,Val6\n")
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    colRuler.clientView = textView
    scrollView.horizontalRulerView = colRuler

    let lineRuler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    lineRuler.clientView = textView
    scrollView.verticalRulerView = lineRuler

    // Over ColumnLetterRulerView -> downward arrow cursor
    let cursorColRuler = colRuler.cursorForPoint(NSPoint(x: 50, y: 10))
    guard cursorColRuler == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected downward arrow cursor over ColumnLetterRulerView"])
    }

    // Over LineNumberRulerView -> rightward arrow cursor
    let cursorLineRuler = lineRuler.cursorForPoint(NSPoint(x: 10, y: 50))
    guard cursorLineRuler == VimMDTextView.rightwardArrowCursor else {
        throw NSError(domain: "SpreadsheetGridTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected rightward arrow cursor over LineNumberRulerView"])
    }

    // Inside text view cells -> nil (standard I-beam)
    guard let row0 = textView.rowRect(for: 0),
          let row1 = textView.rowRect(for: 1),
          let col0 = textView.columnRect(for: 0),
          let col1 = textView.columnRect(for: 1) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to get row/col rects"])
    }
    guard textView.cursorForPoint(NSPoint(x: col1.midX, y: row0.midY)) == nil else {
        throw NSError(domain: "SpreadsheetGridTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor for cell in text view"])
    }
    guard textView.cursorForPoint(NSPoint(x: col0.midX, y: row1.midY)) == nil else {
        throw NSError(domain: "SpreadsheetGridTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor for cell in text view"])
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

// 7. Multi-Row Dragging over LineNumberRulerView
func testMultiRowDraggingOverLineNumberRuler() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "ID,Name\n1,Alice\n2,Bob\n3,Carol\n4,David\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    ruler.clientView = textView
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler

    var feedbackMsg: String?
    textView.onFlashFeedback = { msg in
        feedbackMsg = msg
    }

    guard let row1 = textView.rowRect(for: 1),
          let row3 = textView.rowRect(for: 3) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Missing rects"])
    }

    // Start drag at Row 1 in ruler
    let startPt = ruler.convert(NSPoint(x: 0, y: row1.midY), from: textView)
    let startEvent = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: ruler.convert(startPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDown(with: startEvent)

    // Drag to Row 3
    let dragPt = ruler.convert(NSPoint(x: 0, y: row3.midY), from: textView)
    let dragEvent = NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: ruler.convert(dragPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDragged(with: dragEvent)

    guard ruler.activeRowDragRange == 1...3 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Expected activeRowDragRange 1...3, got \(String(describing: ruler.activeRowDragRange))"])
    }

    // Mouse up
    let upEvent = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: ruler.convert(dragPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0.0
    )!
    ruler.mouseUp(with: upEvent)

    let pbString = NSPasteboard.general.string(forType: .string)
    guard pbString == "1,Alice\n2,Bob\n3,Carol" else {
        throw NSError(domain: "SpreadsheetGridTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Unexpected pasteboard content: '\(String(describing: pbString))'"])
    }

    guard let msg = feedbackMsg, msg.contains("Rows 2–4") else {
        throw NSError(domain: "SpreadsheetGridTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Expected status message mentioning Rows 2–4, got \(String(describing: feedbackMsg))"])
    }
}

// 8. Multi-Column Dragging over ColumnLetterRulerView
func testMultiColumnDraggingOverColumnLetterRuler() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "A,B,C,D\n1,2,3,4\n5,6,7,8\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    ruler.clientView = textView
    scrollView.horizontalRulerView = ruler

    var feedbackMsg: String?
    textView.onFlashFeedback = { msg in
        feedbackMsg = msg
    }

    guard let col1 = textView.columnRect(for: 1),
          let col2 = textView.columnRect(for: 2) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Missing rects"])
    }

    // Start drag at Column 1 in ColumnLetterRulerView
    let startPt = ruler.convert(NSPoint(x: col1.midX, y: 0), from: textView)
    let startEvent = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: ruler.convert(startPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDown(with: startEvent)

    // Drag to Column 2
    let dragPt = ruler.convert(NSPoint(x: col2.midX, y: 0), from: textView)
    let dragEvent = NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: ruler.convert(dragPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDragged(with: dragEvent)

    guard ruler.activeColDragRange == 1...2 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Expected activeColDragRange 1...2, got \(String(describing: ruler.activeColDragRange))"])
    }

    // Mouse up
    let upEvent = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: ruler.convert(dragPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0.0
    )!
    ruler.mouseUp(with: upEvent)

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

// 9. Narrow customColumnWidths with wrapTableCells == true wraps text and increases rowRect.height
func testNarrowCustomColumnWidthWrapsAndIncreasesRowHeight() throws {
    let csv = "ColA,ColB\nHello world this is a long cell,Short\nRow2A,Row2B\n"
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false
    textView.wrapTableCells = true
    textView.customColumnWidths = [0: 80.0]
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    guard let col0 = textView.columnRect(for: 0),
          let row0 = textView.rowRect(for: 0),
          let row1 = textView.rowRect(for: 1),
          let row2 = textView.rowRect(for: 2) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Missing rects"])
    }

    guard abs(col0.width - 80.0) < 0.01 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "Expected col 0 width 80.0, got \(col0.width)"])
    }
    guard row0.height <= 22.0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 82, userInfo: [NSLocalizedDescriptionKey: "Header row should stay single-line, got \(row0.height)"])
    }
    guard row1.height > 30.0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 83, userInfo: [NSLocalizedDescriptionKey: "Narrow col 0 should wrap row 1 and increase height > 30.0, got \(row1.height)"])
    }
    guard abs(row2.minY - row1.maxY) < 0.5 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 84, userInfo: [NSLocalizedDescriptionKey: "Row 2 should start at row1.maxY (\(row1.maxY)), got \(row2.minY)"])
    }
}

// 10. Caret insertionBaseRect on wrapped cell's second visual line
func testCaretInsertionBaseRectOnWrappedCellSecondLine() throws {
    let csv = "Alpha Beta Gamma Delta,ColB\n"
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false
    textView.wrapTableCells = true
    textView.customColumnWidths = [0: 80.0]
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    guard let col0 = textView.columnRect(for: 0) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Missing col0"])
    }

    let firstLineRect = textView.insertionBaseRect(at: 0) // 'A' in "Alpha"
    let secondLineRect = textView.insertionBaseRect(at: 18) // 'e' in "Delta" (wrapped line)

    guard secondLineRect.minY > firstLineRect.minY else {
        throw NSError(domain: "SpreadsheetGridTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Wrapped caret minY (\(secondLineRect.minY)) must be > firstLineRect.minY (\(firstLineRect.minY))"])
    }
    guard secondLineRect.minX >= col0.minX && secondLineRect.minX < col0.maxX else {
        throw NSError(domain: "SpreadsheetGridTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "Wrapped caret minX (\(secondLineRect.minX)) must stay inside col0 (\(col0.minX)...\(col0.maxX))"])
    }
}

// 11. LineNumberRulerView aligns row 2's y-position with rowRect(for: 1).minY when row 1 is wrapped
func testLineNumberRulerAlignsWithWrappedRowRects() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    textView.isTSV = false
    textView.wrapTableCells = true
    textView.customColumnWidths = [0: 80.0]

    let csv = "Long wrapped header text here,B\nRow2,C\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    ruler.clientView = textView
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler

    guard let row0 = textView.rowRect(for: 0),
          let row1 = textView.rowRect(for: 1) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Missing row rects"])
    }
    guard row0.height > 30.0 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 101, userInfo: [NSLocalizedDescriptionKey: "Expected row 0 to wrap and have height > 30.0, got \(row0.height)"])
    }

    guard let rulerRow1 = ruler.tabularRowRect(for: 1) else {
        throw NSError(domain: "SpreadsheetGridTests", code: 102, userInfo: [NSLocalizedDescriptionKey: "LineNumberRulerView must return tabularRowRect for row 1"])
    }
    let expectedInRuler = ruler.convert(row1, from: textView)
    guard abs(rulerRow1.minY - expectedInRuler.minY) < 0.5 && abs(rulerRow1.height - expectedInRuler.height) < 0.5 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 103, userInfo: [NSLocalizedDescriptionKey: "Ruler row 1 rect (\(rulerRow1)) must match converted rowRect(for: 1) (\(expectedInRuler))"])
    }
}

// 12. drawInsertionPoint in tabular mode uses insertionBaseRect(at:) instead of AppKit's unwrapped rect
func testDrawInsertionPointUsesTabularInsertionBaseRect() throws {
    let csv = "Alpha Beta Gamma Delta,ColB\n"
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false
    textView.wrapTableCells = true
    textView.customColumnWidths = [0: 80.0]
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)
    textView.setSelectedRange(NSRange(location: 18, length: 0))

    let expectedRect = textView.currentCaretRect
    let unwrappedAppKitRect = NSRect(x: 999, y: 0, width: 2, height: 18)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 800,
        pixelsHigh: 600,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    textView.drawInsertionPoint(in: unwrappedAppKitRect, color: .labelColor, turnedOn: true)
    let drawnOn = textView.lastDrawnCursorRect
    textView.drawInsertionPoint(in: unwrappedAppKitRect, color: .labelColor, turnedOn: false)
    let drawnOff = textView.lastDrawnCursorRect
    NSGraphicsContext.restoreGraphicsState()

    guard let onRect = drawnOn,
          abs(onRect.minX - expectedRect.minX) < 0.5,
          abs(onRect.minY - expectedRect.minY) < 0.5 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 110, userInfo: [NSLocalizedDescriptionKey: "drawInsertionPoint(turnedOn: true) drew at \(String(describing: drawnOn)), expected \(expectedRect)"])
    }
    guard let offRect = drawnOff,
          abs(offRect.minX - expectedRect.minX) < 0.5,
          abs(offRect.minY - expectedRect.minY) < 0.5 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 111, userInfo: [NSLocalizedDescriptionKey: "drawInsertionPoint(turnedOn: false) drew at \(String(describing: drawnOff)), expected \(expectedRect)"])
    }
}

// 13. Visual selection highlighting in tabular mode computes rects inside wrapped cell bounds
func testTabularSelectionRectsInsideWrappedCell() throws {
    let text = "Alpha Beta Gamma Delta"
    let cellRect = NSRect(x: 10, y: 20, width: 80, height: 60)
    let font = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)
    let stack = TabularCellLayout.CellTextKitStack()
    let rects = TabularCellLayout.selectionRects(
        text: text,
        selectedRange: NSRange(location: 0, length: text.count),
        font: font,
        cellRect: cellRect,
        wrap: true,
        stack: stack
    )

    guard rects.count >= 2 else {
        throw NSError(domain: "SpreadsheetGridTests", code: 120, userInfo: [NSLocalizedDescriptionKey: "Expected >= 2 wrapped selection line rects, got \(rects.count)"])
    }
    for r in rects {
        guard cellRect.contains(r) else {
            throw NSError(domain: "SpreadsheetGridTests", code: 121, userInfo: [NSLocalizedDescriptionKey: "Selection rect \(r) escaped cellRect \(cellRect)"])
        }
    }
    guard rects[1].minY > rects[0].minY else {
        throw NSError(domain: "SpreadsheetGridTests", code: 122, userInfo: [NSLocalizedDescriptionKey: "Expected second line selection rect below first: \(rects)"])
    }
}

print("=== SpreadsheetGrid Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testNeutralColorStylingAndDelimiters", testNeutralColorStylingAndDelimiters),
    ("testColumnWidthCalculationWrapOnVsOff", testColumnWidthCalculationWrapOnVsOff),
    ("testLongCellDoesNotSpillAndPreservesColumnAlignment", testLongCellDoesNotSpillAndPreservesColumnAlignment),
    ("testGridlinesConfiguration", testGridlinesConfiguration),
    ("testDynamicRowAndColumnAddition", testDynamicRowAndColumnAddition),
    ("testHoverCursors", testHoverCursors),
    ("testClickToCopyColumnAndRow", testClickToCopyColumnAndRow),
    ("testMultiRowDraggingOverLineNumberRuler", testMultiRowDraggingOverLineNumberRuler),
    ("testMultiColumnDraggingOverColumnLetterRuler", testMultiColumnDraggingOverColumnLetterRuler),
    ("testNarrowCustomColumnWidthWrapsAndIncreasesRowHeight", testNarrowCustomColumnWidthWrapsAndIncreasesRowHeight),
    ("testCaretInsertionBaseRectOnWrappedCellSecondLine", testCaretInsertionBaseRectOnWrappedCellSecondLine),
    ("testLineNumberRulerAlignsWithWrappedRowRects", testLineNumberRulerAlignsWithWrappedRowRects),
    ("testDrawInsertionPointUsesTabularInsertionBaseRect", testDrawInsertionPointUsesTabularInsertionBaseRect),
    ("testTabularSelectionRectsInsideWrappedCell", testTabularSelectionRectsInsideWrappedCell)
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
