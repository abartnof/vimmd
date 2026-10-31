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

func sendMouseClick(_ tv: VimMDTextView, at point: NSPoint) {
    let windowPoint = tv.convert(point, to: nil)
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    tv.mouseDown(with: event)
    let upEvent = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0.0
    )!
    tv.mouseUp(with: upEvent)
}

func createTestEnvironment(text: String, isTSV: Bool = false) -> (NSWindow, NSView, VimMDTextView, VimSession) {
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let dummyView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = isTSV ? .tsv : .csv
    tv.isTabularDocument = true
    tv.isTSV = isTSV

    let session = VimSession(initialText: text)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    container.addSubview(dummyView)
    container.addSubview(tv)
    window.contentView = container

    window.makeFirstResponder(dummyView)
    return (window, dummyView, tv, session)
}

// 1. Clicking at various X offsets across cell width (left, middle, right)
func testClickVariousXOffsetsAcrossCellWidth() throws {
    let csv = "Product,Price,Quantity\nSuperWidget,19.99,100\nOtherGadget,29.99,50\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1), let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get row 1 or col 1 rect"])
    }

    // Cell (1, 1) is "19.99". On Line 2 ("SuperWidget,19.99,100\n"):
    // "SuperWidget" is 11 chars (offsets 0..<11), ',' is offset 11, "19.99" starts at offset 12.
    // Line 1 is "Product,Price,Quantity\n" = 23 chars.
    // So global offset of "19.99" is 23 + 12 = 35.
    // Vim position is Line 2, ByteCol 13.

    let testPoints = [
        col1.minX + 2.0,   // Left edge
        col1.midX,         // Middle
        col1.maxX - 2.0    // Right edge
    ]

    for (idx, xPos) in testPoints.enumerated() {
        window.makeFirstResponder(dummy)
        var cursorMovedCalled = false
        tv.onCursorMoved = {
            cursorMovedCalled = true
        }

        let pt = NSPoint(x: xPos, y: row1.midY)
        sendMouseClick(tv, at: pt)

        guard window.firstResponder === tv else {
            throw NSError(domain: "TabularCellClickTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Click \(idx) did not transfer first responder"])
        }
        guard tv.selectedRange().location == 35 else {
            throw NSError(domain: "TabularCellClickTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Click \(idx) at x=\(xPos) gave selectedRange \(tv.selectedRange().location), expected 35"])
        }
        guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 13 else {
            throw NSError(domain: "TabularCellClickTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Click \(idx) at x=\(xPos) gave Vim line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol), expected Line 2, Col 13"])
        }
        guard cursorMovedCalled else {
            throw NSError(domain: "TabularCellClickTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Click \(idx) at x=\(xPos) did not invoke onCursorMoved"])
        }
    }
}

// 2. Header row 0 cells click (Column A, B, C)
func testHeaderRowCellsClick() throws {
    let csv = "Alpha,Beta,Gamma\nOne,Two,Three\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row0 = tv.rowRect(for: 0),
          let col0 = tv.columnRect(for: 0),
          let col1 = tv.columnRect(for: 1),
          let col2 = tv.columnRect(for: 2) else {
        throw NSError(domain: "TabularCellClickTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to get header rects"])
    }

    // Col A ("Alpha"): offset 0, Line 1, Col 1
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col0.midX, y: row0.midY))
    guard window.firstResponder === tv && session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Header Col 0 click failed, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }

    // Col B ("Beta"): offset 6, Line 1, Col 7
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row0.midY))
    guard window.firstResponder === tv && session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 7 else {
        throw NSError(domain: "TabularCellClickTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Header Col 1 click failed, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }

    // Col C ("Gamma"): offset 11, Line 1, Col 12
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col2.midX, y: row0.midY))
    guard window.firstResponder === tv && session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 12 else {
        throw NSError(domain: "TabularCellClickTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Header Col 2 click failed, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }
}

// 3. Column A cells click on data rows
func testColumnACellsClick() throws {
    let csv = "ColA,ColB\nFirstRow,10\nSecondRow,20\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1),
          let row2 = tv.rowRect(for: 2),
          let col0 = tv.columnRect(for: 0) else {
        throw NSError(domain: "TabularCellClickTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to get Column A rects"])
    }

    // Row 1, Col A: "FirstRow", Line 2, Col 1
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col0.midX, y: row1.midY))
    guard window.firstResponder === tv && session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Row 1 Col A click failed, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }

    // Row 2, Col A: "SecondRow", Line 3, Col 1
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col0.midX, y: row2.midY))
    guard window.firstResponder === tv && session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Row 2 Col A click failed, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }
}

// 4. Quoted cells click (must point to opening quote `"`)
func testQuotedCellsClick() throws {
    let csv = "ID,League,Points\n1,\"Premier League, UK\",85\n2,\"La Liga, Spain\",82\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1), let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to get quoted cell rect"])
    }

    // "ID,League,Points\n" = 17 chars.
    // Line 2: "1,\"Premier League, UK\",85\n"
    // "1," = 2 chars -> offset 17 + 2 = 19 is the quote '"'.
    // Vim position is Line 2, Col 3.

    let testPoints = [
        col1.minX + 3.0,
        col1.midX,
        col1.maxX - 3.0
    ]

    for (i, x) in testPoints.enumerated() {
        window.makeFirstResponder(dummy)
        sendMouseClick(tv, at: NSPoint(x: x, y: row1.midY))

        guard tv.selectedRange().location == 19 else {
            throw NSError(domain: "TabularCellClickTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Quoted cell click \(i) at x=\(x) gave offset \(tv.selectedRange().location), expected 19"])
        }
        guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 3 else {
            throw NSError(domain: "TabularCellClickTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Quoted cell click \(i) at x=\(x) gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 3"])
        }
    }
}

// 5. Empty cells click (e.g. `10,,30` and `,,`)
func testEmptyCellsClick() throws {
    let csv = "ColA,ColB,ColC\n10,,30\n,,99\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1),
          let row2 = tv.rowRect(for: 2),
          let col0 = tv.columnRect(for: 0),
          let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to get empty cell rects"])
    }

    // Row 1, Col 1 is empty: "ColA,ColB,ColC\n" = 15 chars.
    // Line 2 is "10,,30\n". "10," = 3 chars -> offset 15 + 3 = 18.
    // Line 2, Col 4.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row1.midY))
    guard tv.selectedRange().location == 18 else {
        throw NSError(domain: "TabularCellClickTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Empty cell (1, 1) gave offset \(tv.selectedRange().location), expected 18"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 4 else {
        throw NSError(domain: "TabularCellClickTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Empty cell (1, 1) gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 4"])
    }

    // Row 2, Col 0 is empty: "10,,30\n" is 7 chars (offset 15 + 7 = 22).
    // Line 3 is ",,99\n". Col 0 is offset 22. Line 3, Col 1.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col0.midX, y: row2.midY))
    guard tv.selectedRange().location == 22 else {
        throw NSError(domain: "TabularCellClickTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Empty cell (2, 0) gave offset \(tv.selectedRange().location), expected 22"])
    }
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Empty cell (2, 0) gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 3, Col 1"])
    }

    // Row 2, Col 1 is empty: offset 23. Line 3, Col 2.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row2.midY))
    guard tv.selectedRange().location == 23 else {
        throw NSError(domain: "TabularCellClickTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Empty cell (2, 1) gave offset \(tv.selectedRange().location), expected 23"])
    }
    guard session.cursorPosition.line == 3 && session.cursorPosition.byteCol == 2 else {
        throw NSError(domain: "TabularCellClickTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "Empty cell (2, 1) gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 3, Col 2"])
    }
}

// 6. Trailing empty cells click (e.g. `A,B,C\n1,2,\n`)
func testTrailingEmptyCellsClick() throws {
    let csv = "A,B,C\n1,2,\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1), let col2 = tv.columnRect(for: 2) else {
        throw NSError(domain: "TabularCellClickTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Failed to get trailing cell rect"])
    }

    // "A,B,C\n" = 6 chars. Line 2 is "1,2,\n". "1,2," = 4 chars.
    // Trailing empty cell starts after second comma (offset 6 + 4 = 10 in document).
    // In Vim normal mode, the cursor cannot be on a newline on non-empty lines,
    // so Vim normal mode clamps to the trailing delimiter (comma) at Line 2, ByteCol 4 (offset 9).
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col2.midX, y: row1.midY))

    guard tv.selectedRange().location == 9 else {
        throw NSError(domain: "TabularCellClickTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Trailing cell gave offset \(tv.selectedRange().location), expected 9"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 4 else {
        throw NSError(domain: "TabularCellClickTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "Trailing cell gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 4"])
    }

    // Also test non-empty trailing cell: "A,B,C\n1,2,300\n"
    let (w2, d2, tv2, s2) = createTestEnvironment(text: "A,B,C\n1,2,300\n")
    guard let r1_2 = tv2.rowRect(for: 1), let c2_2 = tv2.columnRect(for: 2) else {
        throw NSError(domain: "TabularCellClickTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Failed to get rects for non-empty trailing cell"])
    }
    w2.makeFirstResponder(d2)
    sendMouseClick(tv2, at: NSPoint(x: c2_2.midX, y: r1_2.midY))
    // "300" starts at offset 6 + 4 = 10 ('3'). Line 2, Col 5.
    guard tv2.selectedRange().location == 10 else {
        throw NSError(domain: "TabularCellClickTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "Non-empty trailing cell gave offset \(tv2.selectedRange().location), expected 10"])
    }
    guard s2.cursorPosition.line == 2 && s2.cursorPosition.byteCol == 5 else {
        throw NSError(domain: "TabularCellClickTests", code: 55, userInfo: [NSLocalizedDescriptionKey: "Non-empty trailing cell gave Line \(s2.cursorPosition.line), Col \(s2.cursorPosition.byteCol), expected Line 2, Col 5"])
    }
}

// 7. Clamping beyond last column and row within the view
func testClampingBeyondLastColumnAndRow() throws {
    let csv = "ColA,ColB\nValA,ValB\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row0 = tv.rowRect(for: 0),
          let row1 = tv.rowRect(for: 1),
          let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Failed to get rects for clamping test"])
    }

    // 7a. Click beyond last column on data row 1 (x = 3000, y = row1.midY)
    // Must clamp to last column (Col 1: "ValB"), targeting the FIRST character of that cell ('V')
    // "ColA,ColB\n" = 10 chars. "ValA," = 5 chars -> offset 15. Line 2, Col 6.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: 3000.0, y: row1.midY))
    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularCellClickTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Clamping click did not make tv first responder"])
    }
    guard tv.selectedRange().location == 15 else {
        throw NSError(domain: "TabularCellClickTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Beyond last col gave offset \(tv.selectedRange().location), expected 15 (start of ValB)"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 6 else {
        throw NSError(domain: "TabularCellClickTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Beyond last col gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 6"])
    }

    // 7b. Click beyond last row in column 1 (x = col1.midX, y = 3000.0)
    // Must clamp to last row (Row 1: "ValB"), targeting start of "ValB" (offset 15)
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: 3000.0))
    guard tv.selectedRange().location == 15 else {
        throw NSError(domain: "TabularCellClickTests", code: 64, userInfo: [NSLocalizedDescriptionKey: "Beyond last row gave offset \(tv.selectedRange().location), expected 15"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 6 else {
        throw NSError(domain: "TabularCellClickTests", code: 65, userInfo: [NSLocalizedDescriptionKey: "Beyond last row gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 6"])
    }

    // 7c. Click beyond both last column and last row (x = 3000.0, y = 3000.0)
    // Must clamp to (row 1, col 1) -> start of "ValB" (offset 15)
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: 3000.0, y: 3000.0))
    guard tv.selectedRange().location == 15 else {
        throw NSError(domain: "TabularCellClickTests", code: 66, userInfo: [NSLocalizedDescriptionKey: "Beyond both gave offset \(tv.selectedRange().location), expected 15"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 6 else {
        throw NSError(domain: "TabularCellClickTests", code: 67, userInfo: [NSLocalizedDescriptionKey: "Beyond both gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 6"])
    }

    // 7d. Click negative coordinates (x = -50.0, y = -50.0)
    // Must clamp to (0, 0) -> start of "ColA" (offset 0, Line 1, Col 1)
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: -50.0, y: -50.0))
    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "TabularCellClickTests", code: 68, userInfo: [NSLocalizedDescriptionKey: "Negative coords gave offset \(tv.selectedRange().location), expected 0"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 69, userInfo: [NSLocalizedDescriptionKey: "Negative coords gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 1, Col 1"])
    }

    // 7e. Click beyond last column on header row (x = 3000.0, y = row0.midY)
    // Must clamp to (0, 1) -> start of "ColB" (offset 5, Line 1, Col 6)
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: 3000.0, y: row0.midY))
    guard tv.selectedRange().location == 5 else {
        throw NSError(domain: "TabularCellClickTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Beyond header last col gave offset \(tv.selectedRange().location), expected 5"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 6 else {
        throw NSError(domain: "TabularCellClickTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Beyond header last col gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 1, Col 6"])
    }
}

// 8. Direct positionCaret clamping when c >= fields.count
func testPositionCaretDirectClamping() throws {
    let csv = "A,B,C\n1,2,3\n"
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    tv.isTabularDocument = true
    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Request column index 99 on row 1 ("1,2,3")
    // "A,B,C\n" = 6. "1,2," = 4. "3" is at offset 6 + 4 = 10.
    // Must clamp to last field's FIRST position (offset 10, Line 2, Col 5), not trailing newline.
    tv.positionCaret(atRow: 1, column: 99)
    guard tv.selectedRange().location == 10 else {
        throw NSError(domain: "TabularCellClickTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "positionCaret with col 99 gave offset \(tv.selectedRange().location), expected 10"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 5 else {
        throw NSError(domain: "TabularCellClickTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "positionCaret with col 99 gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 5"])
    }
}

// 9. TSV Cell Clicking (tabs as delimiters)
func testTSVCellClick() throws {
    let tsv = "ID\tProduct\tPrice\n1\tMechanical Keyboard\t120\n2\tMouse\t45\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: tsv, isTSV: true)

    guard let row1 = tv.rowRect(for: 1), let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Failed to get TSV rects"])
    }

    // Line 1: "ID\tProduct\tPrice\n" = 17 chars.
    // Line 2: "1\tMechanical Keyboard\t120\n". "1\t" = 2 chars -> offset 17 + 2 = 19 ('M').
    // Line 2, Col 3.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row1.midY))

    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularCellClickTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "TSV click did not make tv first responder"])
    }
    guard tv.selectedRange().location == 19 else {
        throw NSError(domain: "TabularCellClickTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "TSV cell click gave offset \(tv.selectedRange().location), expected 19"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 3 else {
        throw NSError(domain: "TabularCellClickTests", code: 93, userInfo: [NSLocalizedDescriptionKey: "TSV cell click gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 3"])
    }
}

// 10. Multibyte & Emoji cell clicking
func testUnicodeAndEmojiCellClick() throws {
    let csv = "Item,Price\n☕ Espresso,3.50\nCroissant,4.00\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row1 = tv.rowRect(for: 1), let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to get unicode cell rects"])
    }

    // "Item,Price\n" = 11 UTF-16 chars.
    // Line 2: "☕ Espresso,3.50\n"
    // "☕ Espresso" is 10 UTF-16 chars ('☕' is 1 unichar + ' ' + 8 chars). Comma is 1 unichar.
    // So "3.50" starts at UTF-16 offset 11 + 11 = 22.
    // In UTF-8: "☕" is 3 bytes, " " is 1 byte, "Espresso" is 8 bytes, "," is 1 byte (total 13 bytes).
    // Vim byteCol for "3.50" is 1 + 13 = 14 on Line 2.
    window.makeFirstResponder(dummy)
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row1.midY))

    guard tv.selectedRange().location == 22 else {
        throw NSError(domain: "TabularCellClickTests", code: 101, userInfo: [NSLocalizedDescriptionKey: "Unicode row click gave offset \(tv.selectedRange().location), expected 22"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 14 else {
        throw NSError(domain: "TabularCellClickTests", code: 102, userInfo: [NSLocalizedDescriptionKey: "Unicode row click gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 2, Col 14"])
    }
}

// 11. Empty document safe handling
func testEmptyDocumentClick() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    tv.isTabularDocument = true
    let session = VimSession(initialText: "")
    tv.session = session

    tv.positionCaret(at: NSPoint(x: 50, y: 50))
    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "TabularCellClickTests", code: 110, userInfo: [NSLocalizedDescriptionKey: "Empty doc positionCaret gave offset \(tv.selectedRange().location), expected 0"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 111, userInfo: [NSLocalizedDescriptionKey: "Empty doc cursor gave Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol), expected Line 1, Col 1"])
    }
}

// 12. Cell clicks on Row 1 (header) and Column 1 (Col A) do not copy to clipboard and position caret
func testHeaderAndColumnACellClicksDoNotCopyToClipboard() throws {
    let csv = "ColA,ColB,ColC\nRow1A,Row1B,Row1C\nRow2A,Row2B,Row2C\n"
    let (window, dummy, tv, session) = createTestEnvironment(text: csv)

    guard let row0 = tv.rowRect(for: 0),
          let row1 = tv.rowRect(for: 1),
          let col0 = tv.columnRect(for: 0),
          let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularCellClickTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to get rects"])
    }

    // Clear pasteboard before test
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("SENTINEL_PASTEBOARD", forType: .string)

    // Click Header Row, Col B
    sendMouseClick(tv, at: NSPoint(x: col1.midX, y: row0.midY))

    // Caret must be placed at ColB
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 6 else {
        throw NSError(domain: "TabularCellClickTests", code: 101, userInfo: [NSLocalizedDescriptionKey: "Expected Line 1, Col 6, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }
    // Pasteboard must NOT be modified by cell click!
    let pbAfterHeader = NSPasteboard.general.string(forType: .string)
    guard pbAfterHeader == "SENTINEL_PASTEBOARD" else {
        throw NSError(domain: "TabularCellClickTests", code: 102, userInfo: [NSLocalizedDescriptionKey: "Pasteboard was overwritten by header cell click: \(String(describing: pbAfterHeader))"])
    }
    guard !tv.isDraggingCol && tv.activeColDragRange == nil else {
        throw NSError(domain: "TabularCellClickTests", code: 103, userInfo: [NSLocalizedDescriptionKey: "isDraggingCol should be false"])
    }

    // Click Column A on data Row 1
    sendMouseClick(tv, at: NSPoint(x: col0.midX, y: row1.midY))

    // Caret must be placed at Row1A (Line 2, Col 1)
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularCellClickTests", code: 104, userInfo: [NSLocalizedDescriptionKey: "Expected Line 2, Col 1, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }
    // Pasteboard must NOT be modified by cell click!
    let pbAfterColA = NSPasteboard.general.string(forType: .string)
    guard pbAfterColA == "SENTINEL_PASTEBOARD" else {
        throw NSError(domain: "TabularCellClickTests", code: 105, userInfo: [NSLocalizedDescriptionKey: "Pasteboard was overwritten by column A cell click: \(String(describing: pbAfterColA))"])
    }
    guard !tv.isDraggingRow && tv.activeRowDragRange == nil else {
        throw NSError(domain: "TabularCellClickTests", code: 106, userInfo: [NSLocalizedDescriptionKey: "isDraggingRow should be false"])
    }

    // Inside text view, hovering over header cells or column A should NOT return downward/rightward arrow
    let curHeader = tv.cursorForPoint(NSPoint(x: col1.midX, y: row0.midY))
    guard curHeader != VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "TabularCellClickTests", code: 107, userInfo: [NSLocalizedDescriptionKey: "Header cell hover must not show downwardArrowCursor"])
    }
    let curColA = tv.cursorForPoint(NSPoint(x: col0.midX, y: row1.midY))
    guard curColA != VimMDTextView.rightwardArrowCursor else {
        throw NSError(domain: "TabularCellClickTests", code: 108, userInfo: [NSLocalizedDescriptionKey: "Col A cell hover must not show rightwardArrowCursor"])
    }
}

// Main test runner
let tests: [(String, () throws -> Void)] = [
    ("testClickVariousXOffsetsAcrossCellWidth", testClickVariousXOffsetsAcrossCellWidth),
    ("testHeaderRowCellsClick", testHeaderRowCellsClick),
    ("testColumnACellsClick", testColumnACellsClick),
    ("testQuotedCellsClick", testQuotedCellsClick),
    ("testEmptyCellsClick", testEmptyCellsClick),
    ("testTrailingEmptyCellsClick", testTrailingEmptyCellsClick),
    ("testClampingBeyondLastColumnAndRow", testClampingBeyondLastColumnAndRow),
    ("testPositionCaretDirectClamping", testPositionCaretDirectClamping),
    ("testTSVCellClick", testTSVCellClick),
    ("testUnicodeAndEmojiCellClick", testUnicodeAndEmojiCellClick),
    ("testEmptyDocumentClick", testEmptyDocumentClick),
    ("testHeaderAndColumnACellClicksDoNotCopyToClipboard", testHeaderAndColumnACellClicksDoNotCopyToClipboard)
]

print("=== TabularCellClickTests ===")
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
