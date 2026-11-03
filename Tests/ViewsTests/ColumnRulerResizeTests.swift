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

class TestContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let textView: VimMDTextView
    let ruler: ColumnLetterRulerView

    init(csv: String, isTSV: Bool = false) {
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                               styleMask: [.titled],
                               backing: .buffered,
                               defer: false)
        self.scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
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

    func postMouseEvent(type: NSEvent.EventType, at ptInRuler: NSPoint, clickCount: Int = 1) {
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

// Requirement 1a: Hover over column dividers in ColumnLetterRulerView detects divider and displays resizeLeftRight cursor
func testHoverOverDividerDetectsDividerAndResizeCursor() throws {
    let ctx = TestContext(csv: "Alpha,Beta,Gamma\n1,2,3\n")
    let widths = ctx.textView.columnWidths()
    guard widths.count == 3 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns, got \(widths.count)"])
    }

    let insetX = ctx.textView.textContainerInset.width
    let divider0XInTV = insetX + widths[0]
    let divider1XInTV = divider0XInTV + widths[1]

    let div0PtInRuler = ctx.ruler.convert(NSPoint(x: divider0XInTV, y: 0), from: ctx.textView)
    let div1PtInRuler = ctx.ruler.convert(NSPoint(x: divider1XInTV, y: 0), from: ctx.textView)

    // 1. Exact hit on divider 0
    let detected0 = ctx.ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x, y: 10))
    guard detected0 == 0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected dividerColumnIndex to return 0, got \(String(describing: detected0))"])
    }
    let cursor0 = ctx.ruler.cursorForPoint(NSPoint(x: div0PtInRuler.x, y: 10))
    guard cursor0 == NSCursor.resizeLeftRight else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on divider 0, got \(String(describing: cursor0))"])
    }

    // 2. Tolerance hits (+3pt and -3pt)
    let detectedPlus = ctx.ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x + 3.0, y: 10))
    guard detectedPlus == 0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at +3pt tolerance"])
    }
    let detectedMinus = ctx.ruler.dividerColumnIndex(at: NSPoint(x: div0PtInRuler.x - 3.0, y: 10))
    guard detectedMinus == 0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 at -3pt tolerance"])
    }

    // 3. Exact hit on divider 1
    let detected1 = ctx.ruler.dividerColumnIndex(at: NSPoint(x: div1PtInRuler.x, y: 10))
    guard detected1 == 1 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected divider 1 on divider 1 boundary"])
    }

    // 4. In the body of column 0 (away from divider)
    let midCol0PtInRuler = ctx.ruler.convert(NSPoint(x: insetX + widths[0] / 2.0, y: 0), from: ctx.textView)
    let detectedBody = ctx.ruler.dividerColumnIndex(at: NSPoint(x: midCol0PtInRuler.x, y: 10))
    guard detectedBody == nil else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected nil in column body, got \(String(describing: detectedBody))"])
    }
    let bodyCursor = ctx.ruler.cursorForPoint(NSPoint(x: midCol0PtInRuler.x, y: 10))
    guard bodyCursor == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected downwardArrowCursor in column body"])
    }
}

// Requirement 1b: Mouse down and drag on column divider in ColumnLetterRulerView resizes column width in VimMDTextView.customColumnWidths
func testMouseDownAndDragOnDividerResizesColumnWidth() throws {
    let ctx = TestContext(csv: "Product,Price,Quantity\nApple,1.50,100\nBanana,0.75,250\n")
    let initialWidths = ctx.textView.columnWidths()

    let divider0XInTV = ctx.textView.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ctx.ruler.convert(NSPoint(x: divider0XInTV, y: 0), from: ctx.textView)

    // Mouse down on divider 0
    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    guard ctx.ruler.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected ruler.isResizingColumn to be true"])
    }
    guard ctx.ruler.resizingColumnIndex == 0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected resizingColumnIndex == 0"])
    }
    guard ctx.ruler.dragStartColIndex == nil else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Should not initiate column drag-to-copy when on divider"])
    }

    // Drag +50pt to the right
    let dragPt = NSPoint(x: div0PtInRuler.x + 50.0, y: 10)
    ctx.postMouseEvent(type: .leftMouseDragged, at: dragPt)

    let expectedWidth = initialWidths[0] + 50.0
    guard let customW = ctx.textView.customColumnWidths[0], abs(customW - expectedWidth) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected customColumnWidths[0] == \(expectedWidth), got \(String(describing: ctx.textView.customColumnWidths[0]))"])
    }
    guard abs(ctx.textView.columnWidths()[0] - expectedWidth) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] == \(expectedWidth), got \(ctx.textView.columnWidths()[0])"])
    }

    // Mouse up ends resizing and preserves width
    ctx.postMouseEvent(type: .leftMouseUp, at: dragPt)
    guard !ctx.ruler.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected isResizingColumn to be false after mouseUp"])
    }
    guard abs(ctx.textView.columnWidths()[0] - expectedWidth) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected column width to be retained after mouseUp"])
    }
}

// Requirement 1b (cont.): Clamping prevents shrinking below 30.0pt
func testClampingPreventsShrinkingBelowMinimum() throws {
    let ctx = TestContext(csv: "Item,Amount\nA,10\nB,20\n")
    let initialWidths = ctx.textView.columnWidths()

    let divider0XInTV = ctx.textView.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ctx.ruler.convert(NSPoint(x: divider0XInTV, y: 0), from: ctx.textView)

    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    // Drag -500pt left
    ctx.postMouseEvent(type: .leftMouseDragged, at: NSPoint(x: div0PtInRuler.x - 500.0, y: 10))
    ctx.postMouseEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x - 500.0, y: 10))

    guard let customW = ctx.textView.customColumnWidths[0], abs(customW - 30.0) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected customColumnWidths[0] clamped to 30.0, got \(String(describing: ctx.textView.customColumnWidths[0]))"])
    }
    guard abs(ctx.textView.columnWidths()[0] - 30.0) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] clamped to 30.0, got \(ctx.textView.columnWidths()[0])"])
    }
}

// Requirement 1c: Double clicking column divider in ColumnLetterRulerView resets custom column width
func testDoubleClickDividerResetsCustomColumnWidth() throws {
    let ctx = TestContext(csv: "City,Country,Population\nTokyo,Japan,37M\nParis,France,11M\n")
    let initialWidths = ctx.textView.columnWidths()

    // Manually set custom width
    ctx.textView.customColumnWidths[0] = 350.0
    ctx.textView.updateSyntaxStyling(force: true)
    guard ctx.textView.columnWidths()[0] == 350.0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to set custom width 350.0"])
    }

    // Divider position with custom width
    let customDiv0XInTV = ctx.textView.textContainerInset.width + 350.0
    let div0PtInRuler = ctx.ruler.convert(NSPoint(x: customDiv0XInTV, y: 0), from: ctx.textView)

    // Double click on divider 0
    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10), clickCount: 2)

    guard ctx.textView.customColumnWidths[0] == nil else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected customColumnWidths[0] to be removed after double-click"])
    }
    guard !ctx.ruler.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Expected isResizingColumn to be false after double-click"])
    }
    // Width reverts to auto-calculated initial width
    guard abs(ctx.textView.columnWidths()[0] - initialWidths[0]) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected columnWidths()[0] reverted to \(initialWidths[0]), got \(ctx.textView.columnWidths()[0])"])
    }
}

// Requirement 1d: Clicking and dragging on first text row of VimMDTextView does NOT initiate column resizing anymore
func testTextViewFirstRowDoesNotInitiateColumnResizing() throws {
    let ctx = TestContext(csv: "Header1,Header2,Header3\nRow1Col1,Row1Col2,Row1Col3\n")
    let widths = ctx.textView.columnWidths()
    guard let r0 = ctx.textView.rowRect(for: 0) else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Missing row 0 rect"])
    }

    let divider0X = ctx.textView.textContainerInset.width + widths[0]
    let headerDividerPt = NSPoint(x: divider0X, y: r0.midY)

    // 1. Cursor over first text row divider position is NOT resizeLeftRight
    let cursor = ctx.textView.cursorForPoint(headerDividerPt)
    guard cursor != NSCursor.resizeLeftRight else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "VimMDTextView first row should NOT display resizeLeftRight cursor"])
    }

    // 2. handleTabularMouseDown returns false on text view first row divider
    let handled = ctx.textView.handleTabularMouseDown(at: headerDividerPt)
    guard !handled else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "handleTabularMouseDown should return false on header row"])
    }
    guard !ctx.textView.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "isResizingColumn should remain false on text view click"])
    }

    // 3. Normal mouseDown on text view row 0 positions caret / selection, not resizing
    let locInWindow = ctx.textView.convert(headerDividerPt, to: nil)
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: locInWindow,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: ctx.window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ctx.textView.mouseDown(with: event)
    guard !ctx.textView.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "VimMDTextView.mouseDown should not enter resizing"])
    }
    // Caret is positioned inside the cell
    guard ctx.textView.selectedRange().location != NSNotFound else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Expected caret to be positioned"])
    }
}

// Additional test: Clicking away from divider on ruler initiates column selection/drag
func testRulerClickAwayFromDividerInitiatesColumnSelection() throws {
    let ctx = TestContext(csv: "First,Second,Third\n1,2,3\n")
    let widths = ctx.textView.columnWidths()

    let midCol1XInTV = ctx.textView.textContainerInset.width + widths[0] + (widths[1] / 2.0)
    let midCol1PtInRuler = ctx.ruler.convert(NSPoint(x: midCol1XInTV, y: 0), from: ctx.textView)

    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: midCol1PtInRuler.x, y: 10))

    guard !ctx.ruler.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Should not resize column when clicking in column body"])
    }
    guard ctx.ruler.dragStartColIndex == 1 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Expected dragStartColIndex == 1, got \(String(describing: ctx.ruler.dragStartColIndex))"])
    }
    guard ctx.ruler.activeColDragRange == 1...1 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "Expected activeColDragRange == 1...1"])
    }
    ctx.postMouseEvent(type: .leftMouseUp, at: NSPoint(x: midCol1PtInRuler.x, y: 10))
}

// Additional test: TSV column resizing via ruler
func testTSVColumnResizingViaRuler() throws {
    let ctx = TestContext(csv: "Name\tDepartment\tRole\nBob\tEngineering\tArchitect\n", isTSV: true)
    let initialWidths = ctx.textView.columnWidths()

    let div0XInTV = ctx.textView.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ctx.ruler.convert(NSPoint(x: div0XInTV, y: 0), from: ctx.textView)

    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))
    ctx.postMouseEvent(type: .leftMouseDragged, at: NSPoint(x: div0PtInRuler.x + 75.0, y: 10))
    ctx.postMouseEvent(type: .leftMouseUp, at: NSPoint(x: div0PtInRuler.x + 75.0, y: 10))

    let expected = initialWidths[0] + 75.0
    guard abs(ctx.textView.columnWidths()[0] - expected) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Expected TSV column 0 resized to \(expected), got \(ctx.textView.columnWidths()[0])"])
    }
}

// Remediation Test 8: Empty space beyond the last column returns nil (default arrow) instead of downwardArrowCursor
func testEmptySpaceBeyondColumnsReturnsNilCursor() throws {
    let ctx = TestContext(csv: "A,B\n1,2\n")
    let widths = ctx.textView.columnWidths()
    let totalColsWidth = ctx.textView.textContainerInset.width + widths.reduce(0, +)

    let emptyPtInRuler = NSPoint(x: totalColsWidth + 150.0, y: 10)
    let col = ctx.ruler.columnIndex(at: emptyPtInRuler)
    guard col == nil else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Expected nil column in empty space beyond table"])
    }
    let cursor = ctx.ruler.cursorForPoint(emptyPtInRuler)
    guard cursor == nil else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor in empty space beyond table, got \(String(describing: cursor))"])
    }
}

// Remediation Test 9: Divider hit-testing when horizontally scrolled
func testDividerHitTestingWhenHorizontallyScrolled() throws {
    let ctx = TestContext(csv: "Col1,Col2,Col3,Col4,Col5\n1,2,3,4,5\n")
    let widths = ctx.textView.columnWidths()
    let divider0XInTV = ctx.textView.textContainerInset.width + widths[0]

    // Scroll horizontally by 80pt
    ctx.scrollView.contentView.scroll(to: NSPoint(x: 80.0, y: 0))
    ctx.scrollView.reflectScrolledClipView(ctx.scrollView.contentView)

    let div0InRuler = ctx.ruler.convertPointFromTextView(NSPoint(x: divider0XInTV, y: 0))
    let hit = ctx.ruler.dividerColumnIndex(at: NSPoint(x: div0InRuler.x, y: 10))
    guard hit == 0 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Expected divider 0 on ruler when scrolled, got \(String(describing: hit))"])
    }

    let cursor = ctx.ruler.cursorForPoint(NSPoint(x: div0InRuler.x, y: 10))
    guard cursor == NSCursor.resizeLeftRight else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "Expected resizeLeftRight cursor on scrolled divider"])
    }
}

// Remediation Test 10: Resizing under magnification (1.5x / 2.0x): verify 1:1 mouse tracking
func testResizingUnderMagnification1to1Tracking() throws {
    let ctx = TestContext(csv: "Product,Price\nWidget,10.0\n")
    let initialWidths = ctx.textView.columnWidths()
    let mag: CGFloat = 2.0
    ctx.scrollView.magnification = mag
    ctx.ruler.uiScale = mag

    let divider0XInTV = ctx.textView.textContainerInset.width + initialWidths[0]
    let div0PtInRuler = ctx.ruler.convertPointFromTextView(NSPoint(x: divider0XInTV, y: 0))

    // Start resize at divider
    ctx.postMouseEvent(type: .leftMouseDown, at: NSPoint(x: div0PtInRuler.x, y: 10))

    // Drag by 60pt on screen (ruler space)
    let dragPt = NSPoint(x: div0PtInRuler.x + 60.0, y: 10)
    ctx.postMouseEvent(type: .leftMouseDragged, at: dragPt)

    // With 2.0x magnification, 60pt on screen is exactly 30pt in document space:
    let expectedTVWidth = initialWidths[0] + (60.0 / mag)
    guard let customW = ctx.textView.customColumnWidths[0], abs(customW - expectedTVWidth) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Expected document width \(expectedTVWidth) under 2.0x zoom, got \(String(describing: ctx.textView.customColumnWidths[0]))"])
    }

    ctx.postMouseEvent(type: .leftMouseUp, at: dragPt)
    guard !ctx.ruler.isResizingColumn else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Should end resizing on mouseUp"])
    }
}

// Remediation Test 11: Cursor Rects and convertRectFromTextView under magnification
func testResetCursorRectsUnderMagnification() throws {
    let ctx = TestContext(csv: "Item,Cost\nA,1\n")
    let mag: CGFloat = 2.0
    ctx.scrollView.magnification = mag
    ctx.ruler.uiScale = mag

    let col0RectInTV = NSRect(x: 10, y: 0, width: 100, height: 20)
    let rectInRuler = ctx.ruler.convertRectFromTextView(col0RectInTV)

    // In ruler space under 2.0x zoom, width must be scaled by magnification (200.0)
    guard abs(rectInRuler.width - 200.0) < 0.001 else {
        throw NSError(domain: "ColumnRulerResizeTests", code: 100, userInfo: [NSLocalizedDescriptionKey: "Expected ruler rect width 200.0 under 2x zoom, got \(rectInRuler.width)"])
    }
}

print("=== ColumnRulerResize Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testHoverOverDividerDetectsDividerAndResizeCursor", testHoverOverDividerDetectsDividerAndResizeCursor),
    ("testMouseDownAndDragOnDividerResizesColumnWidth", testMouseDownAndDragOnDividerResizesColumnWidth),
    ("testClampingPreventsShrinkingBelowMinimum", testClampingPreventsShrinkingBelowMinimum),
    ("testDoubleClickDividerResetsCustomColumnWidth", testDoubleClickDividerResetsCustomColumnWidth),
    ("testTextViewFirstRowDoesNotInitiateColumnResizing", testTextViewFirstRowDoesNotInitiateColumnResizing),
    ("testRulerClickAwayFromDividerInitiatesColumnSelection", testRulerClickAwayFromDividerInitiatesColumnSelection),
    ("testTSVColumnResizingViaRuler", testTSVColumnResizingViaRuler),
    ("testEmptySpaceBeyondColumnsReturnsNilCursor", testEmptySpaceBeyondColumnsReturnsNilCursor),
    ("testDividerHitTestingWhenHorizontallyScrolled", testDividerHitTestingWhenHorizontallyScrolled),
    ("testResizingUnderMagnification1to1Tracking", testResizingUnderMagnification1to1Tracking),
    ("testResetCursorRectsUnderMagnification", testResetCursorRectsUnderMagnification)
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
