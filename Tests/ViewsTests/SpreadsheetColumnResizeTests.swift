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

class TestSpreadsheetHarness {
    let window: NSWindow
    let scrollView: NSScrollView
    let textView: VimMDTextView
    let ruler: ColumnLetterRulerView

    init(csv: String = "Product,Price,Quantity\nWidget,19.99,100\nGadget,29.99,50\n", isTSV: Bool = false) {
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                               styleMask: [.titled],
                               backing: .buffered,
                               defer: false)
        self.scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        self.textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        self.textView.documentSyntaxType = isTSV ? .tsv : .csv
        self.textView.isTabularDocument = true
        self.textView.isTSV = isTSV

        let session = VimSession(initialText: csv)
        self.textView.session = session

        self.scrollView.documentView = self.textView
        self.window.contentView = self.scrollView

        self.ruler = ColumnLetterRulerView(scrollView: self.scrollView, orientation: .horizontalRuler)
        self.ruler.clientView = self.textView
        self.scrollView.horizontalRulerView = self.ruler
        self.scrollView.hasHorizontalRuler = true
        self.scrollView.rulersVisible = true

        self.textView.updateSyntaxStyling(force: true)
    }

    func postRulerEvent(type: NSEvent.EventType, at ptInRuler: NSPoint, clickCount: Int = 1) {
        let locInWindow = ruler.convert(ptInRuler, to: nil)
        let event = NSEvent.mouseEvent(
            with: type,
            location: locInWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1.0
        )!
        switch type {
        case .leftMouseDown:
            ruler.mouseDown(with: event)
        case .leftMouseDragged:
            ruler.mouseDragged(with: event)
        case .leftMouseUp:
            ruler.mouseUp(with: event)
        case .mouseMoved:
            ruler.mouseMoved(with: event)
        default:
            break
        }
    }
}

func createTestSpreadsheetTextView() -> VimMDTextView {
    let harness = TestSpreadsheetHarness()
    return harness.textView
}

// 1. Divider hit-testing: relocated to ColumnLetterRulerView, text view row 0 returns nil
func testDividerHitTesting() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
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

    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)
    let div1PtInRuler = ruler.convert(NSPoint(x: divider1X, y: 0), from: tv)
    let div2PtInRuler = ruler.convert(NSPoint(x: divider2X, y: 0), from: tv)

    // Exact hit on ruler divider 0
    let hit0 = ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x, y: 10))
    guard hit0 == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at exact boundary on ruler, got \(String(describing: hit0))"])
    }

    // Within tolerance (+3.0 pt) on ruler
    let hit0Plus = ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x + 3.0, y: 10))
    guard hit0Plus == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at +3pt tolerance on ruler, got \(String(describing: hit0Plus))"])
    }

    // Within tolerance (-3.0 pt) on ruler
    let hit0Minus = ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x - 3.0, y: 10))
    guard hit0Minus == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at -3pt tolerance on ruler, got \(String(describing: hit0Minus))"])
    }

    // Divider 1 hit on ruler
    let hit1 = ruler.dividerColumnIndex(at: NSPoint(x: div1PtInRuler.x, y: 10))
    guard hit1 == 1 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected divider 1 on ruler, got \(String(describing: hit1))"])
    }

    // Divider 2 hit on ruler
    let hit2 = ruler.dividerColumnIndex(at: NSPoint(x: div2PtInRuler.x, y: 10))
    guard hit2 == 2 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected divider 2 on ruler, got \(String(describing: hit2))"])
    }

    // Inside column body on ruler -> nil
    let midCol0PtInRuler = ruler.convert(NSPoint(x: insetX + widths[0] / 2.0, y: 0), from: tv)
    let hitBody = ruler.dividerColumnIndex(at: NSPoint(x: midCol0PtInRuler.x, y: 10))
    guard hitBody == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected nil inside column body on ruler, got \(String(describing: hitBody))"])
    }

    // On text view itself: dividerColumnIndex returns nil (relocated to ruler)
    guard tv.dividerColumnIndex(at: NSPoint(x: divider0X, y: r0.midY)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected nil on text view header row"])
    }
    guard tv.dividerColumnIndex(at: NSPoint(x: divider0X, y: r1.midY)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected nil on text view data row"])
    }
}

// 2. Cursor feedback: resizeLeftRight on ruler dividers, downwardArrow on ruler body, nil on text view header
func testCursorFeedback() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let widths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0), let r1 = tv.rowRect(for: 1) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to obtain row rects"])
    }

    let insetX = tv.textContainerInset.width
    let divider0X = insetX + widths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    // Divider on ruler -> resizeLeftRight
    let divCursor = ruler.cursorForPoint(NSPoint(x: div0PtInRuler.x, y: 10))
    guard divCursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on ruler divider"])
    }

    // Away from divider on ruler -> downwardArrowCursor
    let midCol0PtInRuler = ruler.convert(NSPoint(x: insetX + widths[0] / 2.0, y: 0), from: tv)
    let rulerBodyCursor = ruler.cursorForPoint(NSPoint(x: midCol0PtInRuler.x, y: 10))
    guard rulerBodyCursor == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected downwardArrowCursor on ruler body"])
    }

    // On text view: header row divider position -> nil (caret/iBeam in text view)
    let tvHeaderCursor = tv.cursorForPoint(NSPoint(x: divider0X, y: r0.midY))
    guard tvHeaderCursor == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor inside header row in text view"])
    }

    // On text view: data row -> nil
    let dataRowCol0Cursor = tv.cursorForPoint(NSPoint(x: insetX + widths[0] / 2.0, y: r1.midY))
    guard dataRowCol0Cursor == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor in data row in text view"])
    }

    // When isResizingColumn is active on ruler/tv, cursor is resizeLeftRight
    ruler.isResizingColumn = true
    guard ruler.cursorForPoint(NSPoint(x: 10, y: 10)) == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on ruler while resizing"])
    }
    ruler.isResizingColumn = false
}

// 3. Mouse interaction: mouse down on ruler divider enters isResizingColumn
func testMouseDownEntersResizing() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let widths = tv.columnWidths()

    let divider0X = tv.textContainerInset.width + widths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))

    guard ruler.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "ruler.isResizingColumn should be true"])
    }
    guard ruler.resizingColumnIndex == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "ruler.resizingColumnIndex should be 0"])
    }
    guard ruler.dragStartColIndex == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "ruler.dragStartColIndex should be nil"])
    }
    guard abs(ruler.resizeStartX - div0PtInRuler.x) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "resizeStartX mismatch"])
    }
    guard abs(ruler.initialColumnWidth - widths[0]) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "initialColumnWidth mismatch"])
    }
}

// 4. Mouse drag on ruler modifies customColumnWidths and columnWidths()
func testMouseDragModifiesColumnWidths() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let initialWidths = tv.columnWidths()

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))

    // Drag 60pt to the right
    let dragPt = NSPoint(x: div0PtInRuler.x + 60.0, y: 10)
    harness.postRulerEvent(type: .leftMouseDragged, at: dragPt)

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
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let initialWidths = tv.columnWidths()

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))

    // Drag way far to the left (-500pt)
    let dragPt = NSPoint(x: div0PtInRuler.x - 500.0, y: 10)
    harness.postRulerEvent(type: .leftMouseDragged, at: dragPt)

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
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let initialWidths = tv.columnWidths()

    let divider0X = tv.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    harness.postRulerEvent(type: .leftMouseDragged, at: NSPoint(x: div0PtInRuler.x + 40.0, y: 10))

    guard ruler.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Should be resizing during drag"])
    }

    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x + 40.0, y: 10))

    guard !ruler.isResizingColumn else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "isResizingColumn should be false after mouse up"])
    }
    guard ruler.resizingColumnIndex == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "resizingColumnIndex should be nil after mouse up"])
    }
    // Resized width is preserved
    guard let customW = tv.customColumnWidths[0], abs(customW - (initialWidths[0] + 40.0)) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "Expected persisted width, got \(String(describing: tv.customColumnWidths[0]))"])
    }
}

// 7. Double click resets column width
func testDoubleClickResetsColumnWidth() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let initialWidths = tv.columnWidths()

    // Manually set custom width
    tv.customColumnWidths[0] = 300.0
    tv.updateSyntaxStyling(force: true)

    guard tv.columnWidths()[0] == 300.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] == 300.0"])
    }

    // Double click on divider in ruler
    let dividerAfterCustom = tv.textContainerInset.width + 300.0
    let div0PtInRuler = ruler.convert(NSPoint(x: dividerAfterCustom, y: 0), from: tv)
    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10), clickCount: 2)

    guard tv.customColumnWidths[0] == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "customColumnWidths[0] should be removed after double click"])
    }
    guard !ruler.isResizingColumn else {
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

// 9. TSV Column Resizing via Ruler
func testTSVColumnResizing() throws {
    let tsv = "Name\tRole\tDepartment\nAlice\tEngineer\tCore\nBob\tDesigner\tProduct\n"
    let harness = TestSpreadsheetHarness(csv: tsv, isTSV: true)
    let tv = harness.textView
    let ruler = harness.ruler

    let initialWidths = tv.columnWidths()
    guard initialWidths.count == 3 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Expected 3 TSV columns, got \(initialWidths.count)"])
    }

    let div0X = tv.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: div0X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    harness.postRulerEvent(type: .leftMouseDragged, at: NSPoint(x: div0PtInRuler.x + 50.0, y: 10))
    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x + 50.0, y: 10))

    let expected = initialWidths[0] + 50.0
    guard abs(tv.columnWidths()[0] - expected) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 82, userInfo: [NSLocalizedDescriptionKey: "Expected TSV column 0 width \(expected), got \(tv.columnWidths()[0])"])
    }
}

// 10. WrapTableCells Column Resizing via Ruler
func testWrapTableCellsColumnResizing() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    tv.wrapTableCells = true
    tv.updateSyntaxStyling(force: true)

    let wrapWidths = tv.columnWidths()
    guard wrapWidths.count == 3 && wrapWidths[0] == 240.0 && wrapWidths[1] == 240.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Expected default wrap widths of 240.0, got \(wrapWidths)"])
    }

    let div1X = tv.textContainerInset.width + 240.0 + 240.0
    let div1PtInRuler = ruler.convert(NSPoint(x: div1X, y: 0), from: tv)

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div1PtInRuler.x, y: 10))
    harness.postRulerEvent(type: .leftMouseDragged, at: NSPoint(x: div1PtInRuler.x + 80.0, y: 10))
    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div1PtInRuler.x + 80.0, y: 10))

    let newWidths = tv.columnWidths()
    guard abs(newWidths[1] - 320.0) < 0.001 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "Expected column 1 to be 320.0, got \(newWidths[1])"])
    }
    // Column 0 and Column 2 should still be 240.0
    guard newWidths[0] == 240.0 && newWidths[2] == 240.0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 93, userInfo: [NSLocalizedDescriptionKey: "Other columns should remain 240.0, got \(newWidths)"])
    }
}

// 11. Sequential resizing of multiple columns via ruler
func testSequentialResizingMultipleColumns() throws {
    let harness = TestSpreadsheetHarness()
    let tv = harness.textView
    let ruler = harness.ruler
    let initialWidths = tv.columnWidths()

    // Resize col 0 by +40
    let div0X = tv.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: div0X, y: 0), from: tv)
    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    harness.postRulerEvent(type: .leftMouseDragged, at: NSPoint(x: div0PtInRuler.x + 40.0, y: 10))
    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x + 40.0, y: 10))

    // Divider 1 position has shifted by +40
    let div1X = tv.textContainerInset.width + (initialWidths[0] + 40.0) + initialWidths[1]
    let div1PtInRuler = ruler.convert(NSPoint(x: div1X, y: 0), from: tv)
    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div1PtInRuler.x, y: 10))
    harness.postRulerEvent(type: .leftMouseDragged, at: NSPoint(x: div1PtInRuler.x + 25.0, y: 10))
    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div1PtInRuler.x + 25.0, y: 10))

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
    let emptyHarness = TestSpreadsheetHarness(csv: "")
    guard emptyHarness.ruler.dividerColumnIndex(at: NSPoint(x: 100, y: 10)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 110, userInfo: [NSLocalizedDescriptionKey: "Empty document should have no dividers"])
    }
    guard emptyHarness.textView.dividerColumnIndex(at: NSPoint(x: 100, y: 10)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 111, userInfo: [NSLocalizedDescriptionKey: "Empty text view should have no dividers"])
    }

    let singleHarness = TestSpreadsheetHarness(csv: "HeaderOnly\nRow1\n")
    let widths = singleHarness.textView.columnWidths()
    guard widths.count == 1 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 112, userInfo: [NSLocalizedDescriptionKey: "Expected 1 column"])
    }
    let divX = singleHarness.textView.textContainerInset.width + widths[0]
    let divPtInRuler = singleHarness.ruler.convert(NSPoint(x: divX, y: 0), from: singleHarness.textView)
    guard singleHarness.ruler.dividerColumnIndex(at: NSPoint(x: divPtInRuler.x, y: 10)) == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 113, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 on single col ruler"])
    }
    guard singleHarness.ruler.dividerColumnIndex(at: NSPoint(x: divPtInRuler.x + 50, y: 10)) == nil else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 114, userInfo: [NSLocalizedDescriptionKey: "Expected nil beyond divider"])
    }
}

// 13. Normal cell caret positioning preserved on text view (not on divider)
func testHeaderSelectionPreservedWhenNotOnDivider() throws {
    let tv = createTestSpreadsheetTextView()
    let widths = tv.columnWidths()
    guard let r0 = tv.rowRect(for: 0) else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 120, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    // Click in middle of column 1 on text view
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

// 15. Ruler divider hit-testing when scrolled
func testPinnedHeaderHitTestingWhenScrolled() throws {
    var content = "Header1,Header2,Header3\n"
    for i in 1...100 {
        content += "Row\(i)Col1,Row\(i)Col2,Row\(i)Col3\n"
    }
    let harness = TestSpreadsheetHarness(csv: content)
    let scrollView = harness.scrollView
    let tv = harness.textView
    let ruler = harness.ruler

    // Scroll down to y = 400
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: 400))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    let widths = tv.columnWidths()
    let divider0X = tv.textContainerInset.width + widths[0]
    let div0PtInRuler = ruler.convert(NSPoint(x: divider0X, y: 0), from: tv)

    let hit = ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x, y: 10))
    guard hit == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 140, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 on ruler when scrolled, got \(String(describing: hit))"])
    }

    let cursor = ruler.cursorForPoint(NSPoint(x: div0PtInRuler.x, y: 10))
    guard cursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 141, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on ruler divider"])
    }

    harness.postRulerEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    guard ruler.isResizingColumn && ruler.resizingColumnIndex == 0 else {
        throw NSError(domain: "SpreadsheetColumnResizeTests", code: 142, userInfo: [NSLocalizedDescriptionKey: "Expected mouse down on ruler to start resizing"])
    }
    harness.postRulerEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x, y: 10))
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
