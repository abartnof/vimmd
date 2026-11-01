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

func createTestSpreadsheetTextView() -> VimMDTextView {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = false

    let csv = "Product,Price,Quantity\nWidget,19.99,100\nGadget,29.99,50\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)
    return textView
}

// 1. Divider hit-testing: within tolerance on row 0 vs column body vs data rows
func testDividerHitTesting() throws {
    let tv = createTestSpreadsheetTextView()
    let widths = tv.columnWidths()
    guard widths.count == 3 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns, got \(widths.count)"])
    }

    guard let r0 = tv.rowRect(for: 0), let r1 = tv.rowRect(for: 1) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row rects"])
    }

    let insetX = tv.textContainerInset.width
    let divider0X = insetX + widths[0]
    let divider1X = divider0X + widths[1]
    let divider2X = divider1X + widths[2]

    let headerMidY = r0.midY

    // Exact hit on divider 0
    let hit0 = tv.dividerColumnIndex(at: NSPoint(x: divider0X, y: headerMidY))
    guard hit0 == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at exact boundary, got \(String(describing: hit0))"])
    }

    // Within tolerance (+3.0 pt)
    let hit0Plus = tv.dividerColumnIndex(at: NSPoint(x: divider0X + 3.0, y: headerMidY))
    guard hit0Plus == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at +3pt tolerance, got \(String(describing: hit0Plus))"])
    }

    // Within tolerance (-3.0 pt)
    let hit0Minus = tv.dividerColumnIndex(at: NSPoint(x: divider0X - 3.0, y: headerMidY))
    guard hit0Minus == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at -3pt tolerance, got \(String(describing: hit0Minus))"])
    }

    // Divider 1 hit
    let hit1 = tv.dividerColumnIndex(at: NSPoint(x: divider1X, y: headerMidY))
    guard hit1 == 1 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected divider 1, got \(String(describing: hit1))"])
    }

    // Divider 2 hit
    let hit2 = tv.dividerColumnIndex(at: NSPoint(x: divider2X, y: headerMidY))
    guard hit2 == 2 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected divider 2, got \(String(describing: hit2))"])
    }

    // Inside column body (not on boundary) -> nil
    let midCol0X = insetX + widths[0] / 2.0
    let hitBody = tv.dividerColumnIndex(at: NSPoint(x: midCol0X, y: headerMidY))
    guard hitBody == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected nil inside column body, got \(String(describing: hitBody))"])
    }

    // On data row 1 at divider X coordinate -> nil
    let hitRow1 = tv.dividerColumnIndex(at: NSPoint(x: divider0X, y: r1.midY))
    guard hitRow1 == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected nil on data row, got \(String(describing: hitRow1))"])
    }
}

// 2. Cursor feedback: resizeLeftRight on dividers vs downwardArrowCursor in header vs rightwardArrow on col A
func testCursorFeedback() throws {
    let tv = createTestSpreadsheetTextView()
    let widths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0), let r1 = tv.rowRect(for: 1) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row rects"])
    }

    let insetX = tv.textContainerInset.width
    let divider0X = insetX + widths[0]
    let headerMidY = r0.midY

    // Divider on header -> resizeLeftRight
    let divCursor = tv.cursorForPoint(NSPoint(x: divider0X, y: headerMidY))
    guard divCursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on header divider"])
    }

    // Away from divider on header -> nil (standard cell cursor in text view; downward arrow is on ColumnLetterRulerView)
    let headerBodyCursor = tv.cursorForPoint(NSPoint(x: insetX + widths[0] / 2.0, y: headerMidY))
    guard headerBodyCursor == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor inside header cell in text view"])
    }

    // Data row 1, col 0 -> nil in text view (rightward arrow is on LineNumberRulerView)
    let dataRowCol0Cursor = tv.cursorForPoint(NSPoint(x: insetX + widths[0] / 2.0, y: r1.midY))
    guard dataRowCol0Cursor == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor in data row col 0 in text view"])
    }

    // When isResizingColumn is active, cursor is resizeLeftRight anywhere
    tv.isResizingColumn = true
    let resizingCursor = tv.cursorForPoint(NSPoint(x: 10, y: r1.midY))
    guard resizingCursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor while isResizingColumn is true"])
    }
    tv.isResizingColumn = false
}

// 3. Mouse interaction: mouse down on divider enters isResizingColumn
func testMouseDownEntersResizing() throws {
    let tv = createTestSpreadsheetTextView()
    let widths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row 0 rect"])
    }

    let divider0X = tv.textContainerInset.width + widths[0]
    let pt = NSPoint(x: divider0X, y: r0.midY)

    let handled = tv.handleTabularMouseDown(at: pt)
    guard handled else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "handleTabularMouseDown returned false"])
    }
    guard tv.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "isResizingColumn should be true"])
    }
    guard tv.resizingColumnIndex == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "resizingColumnIndex should be 0, got \(String(describing: tv.resizingColumnIndex))"])
    }
    guard tv.isDraggingCol == false else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "isDraggingCol should remain false when resizing divider"])
    }
    guard abs(tv.resizeStartX - divider0X) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "resizeStartX should be \(divider0X), got \(tv.resizeStartX)"])
    }
    guard abs(tv.initialColumnWidth - widths[0]) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "initialColumnWidth should be \(widths[0]), got \(tv.initialColumnWidth)"])
    }
}

// 4. Mouse drag modifies customColumnWidths and columnWidths()
func testMouseDragModifiesColumnWidths() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row 0 rect"])
    }

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    let startPt = NSPoint(x: divider0X, y: r0.midY)
    _ = tv.handleTabularMouseDown(at: startPt)

    // Drag 60pt to the right
    let dragPt = NSPoint(x: divider0X + 60.0, y: r0.midY)
    tv.handleTabularMouseDragged(to: dragPt)

    let expectedW = initialWidths[0] + 60.0
    guard let customW = tv.customColumnWidths[0], abs(customW - expectedW) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected customColumnWidths[0] = \(expectedW), got \(String(describing: tv.customColumnWidths[0]))"])
    }

    let currentWidths = tv.columnWidths()
    guard abs(currentWidths[0] - expectedW) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] = \(expectedW), got \(currentWidths[0])"])
    }
}

// 5. Clamping prevents shrinking below minimum width (30.0 pt)
func testClampingPreventsShrinkingBelowMinimum() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row 0 rect"])
    }

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    let startPt = NSPoint(x: divider0X, y: r0.midY)
    _ = tv.handleTabularMouseDown(at: startPt)

    // Drag way far to the left (-500pt)
    let dragPt = NSPoint(x: divider0X - 500.0, y: r0.midY)
    tv.handleTabularMouseDragged(to: dragPt)

    guard let customW = tv.customColumnWidths[0], abs(customW - 30.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected clamped width 30.0, got \(String(describing: tv.customColumnWidths[0]))"])
    }

    let currentWidths = tv.columnWidths()
    guard abs(currentWidths[0] - 30.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] = 30.0, got \(currentWidths[0])"])
    }
}

// 6. Mouse up ends resizing
func testMouseUpEndsResizing() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row 0 rect"])
    }

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    _ = tv.handleTabularMouseDown(at: NSPoint(x: divider0X, y: r0.midY))
    tv.handleTabularMouseDragged(to: NSPoint(x: divider0X + 40.0, y: r0.midY))

    guard tv.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Should be resizing during drag"])
    }

    tv.handleTabularMouseUp(at: NSPoint(x: divider0X + 40.0, y: r0.midY))

    guard !tv.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "isResizingColumn should be false after mouse up"])
    }
    guard tv.resizingColumnIndex == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "resizingColumnIndex should be nil after mouse up"])
    }
    // Resized width is preserved
    guard let customW = tv.customColumnWidths[0], abs(customW - (initialWidths[0] + 40.0)) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "Expected persisted width, got \(String(describing: tv.customColumnWidths[0]))"])
    }
}

// 7. Double click resets column width
func testDoubleClickResetsColumnWidth() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row 0 rect"])
    }

    // Manually set custom width
    tv.customColumnWidths[0] = 300.0
    tv.updateSyntaxStyling(force: true)

    guard tv.columnWidths()[0] == 300.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] == 300.0"])
    }

    // Double click on divider
    let dividerAfterCustom = tv.textContainerInset.width + 300.0
    let handled = tv.handleTabularMouseDown(at: NSPoint(x: dividerAfterCustom, y: r0.midY), clickCount: 2)
    guard handled else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Double click should be handled"])
    }
    guard tv.customColumnWidths[0] == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "customColumnWidths[0] should be removed after double click"])
    }
    guard !tv.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 64, userInfo: [NSLocalizedDescriptionKey: "isResizingColumn should be false after double click"])
    }
    // Reverts to original auto content width
    let revertedWidth = tv.columnWidths()[0]
    guard abs(revertedWidth - initialWidths[0]) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 65, userInfo: [NSLocalizedDescriptionKey: "Expected reverted width \(initialWidths[0]), got \(revertedWidth)"])
    }
}

// 8. Text layout tab stops update to match resized column widths
func testTextLayoutTabStopsUpdate() throws {
    let tv = createTestSpreadsheetTextView()
    guard let storage = tv.textStorage else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Missing text storage"])
    }

    tv.customColumnWidths[0] = 180.0
    tv.updateSyntaxStyling(force: true)

    let pStyle = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    guard let style = pStyle, !style.tabStops.isEmpty else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Missing paragraphStyle or tabStops"])
    }

    let firstTabStopLoc = style.tabStops[0].location
    guard abs(firstTabStopLoc - 180.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 72, userInfo: [NSLocalizedDescriptionKey: "Expected first tab stop at 180.0, got \(firstTabStopLoc)"])
    }
}

// 9. TSV Column Resizing
func testTSVColumnResizing() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    textView.isTabularDocument = true
    textView.isTSV = true

    let tsv = "Name\tRole\tDepartment\nAlice\tEngineer\tCore\nBob\tDesigner\tProduct\n"
    let session = VimSession(initialText: tsv)
    textView.session = session
    textView.updateSyntaxStyling(force: true)

    let initialWidths = textView.columnWidths()
    guard initialWidths.count == 3 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Expected 3 TSV columns, got \(initialWidths.count)"])
    }

    guard let r0 = textView.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    let div0X = textView.textContainerInset.width + initialWidths[0]
    _ = textView.handleTabularMouseDown(at: NSPoint(x: div0X, y: r0.midY))
    textView.handleTabularMouseDragged(to: NSPoint(x: div0X + 50.0, y: r0.midY))
    textView.handleTabularMouseUp(at: NSPoint(x: div0X + 50.0, y: r0.midY))

    let expected = initialWidths[0] + 50.0
    guard abs(textView.columnWidths()[0] - expected) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 82, userInfo: [NSLocalizedDescriptionKey: "Expected TSV column 0 width \(expected), got \(textView.columnWidths()[0])"])
    }
}

// 10. WrapTableCells Column Resizing
func testWrapTableCellsColumnResizing() throws {
    let tv = createTestSpreadsheetTextView()
    tv.wrapTableCells = true
    tv.updateSyntaxStyling(force: true)

    let wrapWidths = tv.columnWidths()
    guard wrapWidths.count == 3 && wrapWidths[0] == 240.0 && wrapWidths[1] == 240.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Expected default wrap widths of 240.0, got \(wrapWidths)"])
    }

    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    let div1X = tv.textContainerInset.width + 240.0 + 240.0
    _ = tv.handleTabularMouseDown(at: NSPoint(x: div1X, y: r0.midY))
    tv.handleTabularMouseDragged(to: NSPoint(x: div1X + 80.0, y: r0.midY))
    tv.handleTabularMouseUp(at: NSPoint(x: div1X + 80.0, y: r0.midY))

    let newWidths = tv.columnWidths()
    guard abs(newWidths[1] - 320.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "Expected column 1 to be 320.0, got \(newWidths[1])"])
    }
    // Column 0 and Column 2 should still be 240.0
    guard newWidths[0] == 240.0 && newWidths[2] == 240.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 93, userInfo: [NSLocalizedDescriptionKey: "Other columns should remain 240.0, got \(newWidths)"])
    }
}

// 11. Sequential resizing of multiple columns
func testSequentialResizingMultipleColumns() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    // Resize col 0 by +40
    let div0X = tv.textContainerInset.width + initialWidths[0]
    _ = tv.handleTabularMouseDown(at: NSPoint(x: div0X, y: r0.midY))
    tv.handleTabularMouseDragged(to: NSPoint(x: div0X + 40.0, y: r0.midY))
    tv.handleTabularMouseUp(at: NSPoint(x: div0X + 40.0, y: r0.midY))

    // Divider 1 position has shifted by +40
    let div1X = tv.textContainerInset.width + (initialWidths[0] + 40.0) + initialWidths[1]
    _ = tv.handleTabularMouseDown(at: NSPoint(x: div1X, y: r0.midY))
    tv.handleTabularMouseDragged(to: NSPoint(x: div1X + 25.0, y: r0.midY))
    tv.handleTabularMouseUp(at: NSPoint(x: div1X + 25.0, y: r0.midY))

    let updatedWidths = tv.columnWidths()
    guard abs(updatedWidths[0] - (initialWidths[0] + 40.0)) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 101, userInfo: [NSLocalizedDescriptionKey: "Col 0 width mismatch"])
    }
    guard abs(updatedWidths[1] - (initialWidths[1] + 25.0)) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 102, userInfo: [NSLocalizedDescriptionKey: "Col 1 width mismatch"])
    }
}

// 12. Empty and single-column document edge cases
func testEmptyAndSingleColumnEdgeCases() throws {
    let emptyTV = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    emptyTV.isTabularDocument = true
    let emptySession = VimSession(initialText: "")
    emptyTV.session = emptySession
    emptyTV.updateSyntaxStyling(force: true)

    guard emptyTV.dividerColumnIndex(at: NSPoint(x: 100, y: 10)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 110, userInfo: [NSLocalizedDescriptionKey: "Empty document should have no dividers"])
    }

    let singleTV = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    singleTV.isTabularDocument = true
    let singleSession = VimSession(initialText: "HeaderOnly\nRow1\n")
    singleTV.session = singleSession
    singleTV.updateSyntaxStyling(force: true)

    let widths = singleTV.columnWidths()
    guard widths.count == 1 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 111, userInfo: [NSLocalizedDescriptionKey: "Expected 1 column"])
    }
    let divX = singleTV.textContainerInset.width + widths[0]
    guard singleTV.dividerColumnIndex(at: NSPoint(x: divX, y: 10)) == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 112, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 on single col"])
    }
    guard singleTV.dividerColumnIndex(at: NSPoint(x: divX + 50, y: 10)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 113, userInfo: [NSLocalizedDescriptionKey: "Expected nil beyond divider"])
    }
}

// 13. Normal cell caret positioning preserved when not on divider
func testHeaderSelectionPreservedWhenNotOnDivider() throws {
    let tv = createTestSpreadsheetTextView()
    let widths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 120, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    // Click in middle of column 1 (not on divider)
    let col1MidX = tv.textContainerInset.width + widths[0] + (widths[1] / 2.0)
    let handled = tv.handleTabularMouseDown(at: NSPoint(x: col1MidX, y: r0.midY))
    guard !handled else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 121, userInfo: [NSLocalizedDescriptionKey: "Should not handle as column resize or drag"])
    }
    guard !tv.isDraggingCol && !tv.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 122, userInfo: [NSLocalizedDescriptionKey: "Should not enter isDraggingCol or isResizingColumn"])
    }

    // Caret is positioned at clicked cell
    tv.positionCaret(atRow: 0, column: 1)
    guard tv.selectedRange().location != NSNotFound else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 123, userInfo: [NSLocalizedDescriptionKey: "Caret should be positioned"])
    }
}

// 14. Sanitization of non-finite/NaN/negative custom widths in TabularSyntaxResolver
func testSanitizationOfNonFiniteAndNegativeCustomWidths() throws {
    let resolver = TabularSyntaxResolver()
    let storage = NSTextStorage(string: "A,B,C,D\n1,2,3,4\n")

    let badWidths: [Int: CGFloat] = [
        0: -100.0,
        1: 0.0,
        2: CGFloat.nan,
        3: CGFloat.infinity
    ]

    let widths = resolver.calculateColumnWidths(in: storage, isTSV: false, wrapTableCells: false, customColumnWidths: badWidths)
    guard widths.count == 4 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 130, userInfo: [NSLocalizedDescriptionKey: "Expected 4 widths, got \(widths.count)"])
    }
    for (i, w) in widths.enumerated() {
        guard w.isFinite && !w.isNaN && w >= 30.0 else {
            throw NSError(domain: "SpreadsheetColumnResizeTests", code: 131, userInfo: [NSLocalizedDescriptionKey: "Width for column \(i) was not properly sanitized: \(w)"])
        }
    }

    // Also verify wrapTableCells path
    let wrapWidths = resolver.calculateColumnWidths(in: storage, isTSV: false, wrapTableCells: true, customColumnWidths: badWidths)
    for (i, w) in wrapWidths.enumerated() {
        guard w.isFinite && !w.isNaN && w >= 30.0 else {
            throw NSError(domain: "SpreadsheetColumnResizeTests", code: 132, userInfo: [NSLocalizedDescriptionKey: "Wrap width for column \(i) was not properly sanitized: \(w)"])
        }
    }
}

// 15. Pinned header divider hit-testing when scrolled with freezeFirstRow = true
func testPinnedHeaderHitTestingWhenScrolled() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 2000))
    tv.isTabularDocument = true
    tv.isTSV = false

    var content = "Header1,Header2,Header3\n"
    for i in 1...100 {
        content += "Row\(i)Col1,Row\(i)Col2,Row\(i)Col3\n"
    }
    let session = VimSession(initialText: content)
    tv.session = session
    tv.freezeFirstRow = true
    tv.updateSyntaxStyling(force: true)

    scrollView.documentView = tv
    // Scroll down to y = 400
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 400))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    let widths = tv.columnWidths()
    let divider0X = tv.textContainerInset.width + widths[0]

    // Point in the scrolled visible pinned header: y = 405 (within [400, 400 + headerHeight])
    let pinnedPt = NSPoint(x: divider0X, y: 405)
    let hit = tv.dividerColumnIndex(at: pinnedPt)
    guard hit == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 140, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 on pinned header when scrolled, got \(String(describing: hit))"])
    }

    let cursor = tv.cursorForPoint(pinnedPt)
    guard cursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 141, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on pinned header divider"])
    }

    let handled = tv.handleTabularMouseDown(at: pinnedPt)
    guard handled && tv.isResizingColumn && tv.resizingColumnIndex == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 142, userInfo: [NSLocalizedDescriptionKey: "Expected mouse down on pinned header to start resizing"])
    }
    tv.handleTabularMouseUp(at: pinnedPt)
}

// 16. customColumnWidths didSet invalidates cachedColumnWidths
func testCustomColumnWidthsDidSetInvalidatesCache() throws {
    let tv = createTestSpreadsheetTextView()
    let initialWidths = tv.columnWidths()
    guard initialWidths.count >= 2 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 151, userInfo: [NSLocalizedDescriptionKey: "Expected at least 2 columns"])
    }

    // Setting customColumnWidths must invalidate the cache via didSet
    tv.customColumnWidths = [0: 275.0]
    let updatedWidths = tv.columnWidths()
    guard abs(updatedWidths[0] - 275.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 152, userInfo: [NSLocalizedDescriptionKey: "Expected cached widths to be invalidated and return 275.0, got \(updatedWidths[0])"])
    }
}

// 17. viewDidMoveToWindow preserves cursor when not at top left
func testViewDidMoveToWindowPreservesCursorWhenNotAtTopLeft() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    tv.isTabularDocument = true
    let session = VimSession(initialText: "Product,Price,Quantity\nWidget,19.99,100\nGadget,29.99,50\n")
    tv.session = session
    session.setCursor(line: 2, byteCol: 3)

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = tv
    tv.viewDidMoveToWindow()

    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 3 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 162, userInfo: [NSLocalizedDescriptionKey: "Expected cursor to remain at (2, 3), got line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol)"])
    }
}

print("=== SpreadsheetColumnResize Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testDividerHitTesting", testDividerHitTesting),
    ("testCursorFeedback", testCursorFeedback),
    ("testMouseDownEntersResizing", testMouseDownEntersResizing),
    ("testMouseDragModifiesColumnWidths", testMouseDragModifiesColumnWidths),
    ("testClampingPreventsShrinkingBelowMinimum", testClampingPreventsShrinkingBelowMinimum),
    ("testMouseUpEndsResizing", testMouseUpEndsResizing),
    ("testDoubleClickResetsColumnWidth", testDoubleClickResetsColumnWidth),
    ("testTextLayoutTabStopsUpdate", testTextLayoutTabStopsUpdate),
    ("testTSVColumnResizing", testTSVColumnResizing),
    ("testWrapTableCellsColumnResizing", testWrapTableCellsColumnResizing),
    ("testSequentialResizingMultipleColumns", testSequentialResizingMultipleColumns),
    ("testEmptyAndSingleColumnEdgeCases", testEmptyAndSingleColumnEdgeCases),
    ("testHeaderSelectionPreservedWhenNotOnDivider", testHeaderSelectionPreservedWhenNotOnDivider),
    ("testSanitizationOfNonFiniteAndNegativeCustomWidths", testSanitizationOfNonFiniteAndNegativeCustomWidths),
    ("testPinnedHeaderHitTestingWhenScrolled", testPinnedHeaderHitTestingWhenScrolled),
    ("testCustomColumnWidthsDidSetInvalidatesCache", testCustomColumnWidthsDidSetInvalidatesCache),
    ("testViewDidMoveToWindowPreservesCursorWhenNotAtTopLeft", testViewDidMoveToWindowPreservesCursorWhenNotAtTopLeft)
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
