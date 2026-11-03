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

final class FreezePanesTestContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let tv: VimMDTextView
    let session: VimSession
    let colRuler: ColumnLetterRulerView
    let lineRuler: LineNumberRulerView

    static let sampleCSV: String = {
        var lines = ["ID,Product,Price,Quantity,Department,Status"]
        for i in 1...60 {
            lines.append("ITEM_\(String(format: "%03d", i)),Widget_\(i),\(10 + i).99,\(100 * i),Sales,InStock")
        }
        return lines.joined(separator: "\n") + "\n"
    }()

    init(csv: String = FreezePanesTestContext.sampleCSV) {
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.tv.documentSyntaxType = .csv
        self.tv.isTabularDocument = true
        self.tv.isTSV = false

        self.session = VimSession(initialText: csv)
        self.tv.session = session

        self.scrollView.documentView = tv

        self.lineRuler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        self.lineRuler.clientView = tv
        self.scrollView.hasVerticalRuler = true
        self.scrollView.verticalRulerView = lineRuler
        self.scrollView.rulersVisible = true
        self.lineRuler.updateThickness(for: tv)

        self.colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
        self.colRuler.clientView = tv
        self.scrollView.hasHorizontalRuler = true
        self.scrollView.horizontalRulerView = colRuler

        self.window.contentView = scrollView
        self.window.makeFirstResponder(tv)

        tv.updateSyntaxStyling(force: true)
        tv.updateFrameHeightToFitText()
        tv.resetScrollToTopLeft()
    }

    func scrollTo(x: CGFloat, y: CGFloat) {
        scrollView.contentView.scroll(to: NSPoint(x: x, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func renderToBitmap(rect: NSRect) -> NSBitmapImageRep? {
        guard let rep = tv.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        tv.cacheDisplay(in: rect, to: rep)
        return rep
    }
}

// MARK: - Test Cases

// 1. Rulers Occlusion Defense: Pinned header and column do NOT intersect ColumnLetterRulerView or LineNumberRulerView
func testFreezePanesDoNotIntersectRulers() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstRow = true
    tv.freezeFirstColumn = true

    // Scroll both horizontally and vertically
    context.scrollTo(x: 100.0, y: 200.0)

    guard let pinnedHeader = tv.pinnedHeaderRect(), let pinnedCol = tv.pinnedColumnRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get pinnedHeaderRect or pinnedColumnRect"])
    }

    let headerInSV = tv.convert(pinnedHeader, to: context.scrollView)
    let colInSV = tv.convert(pinnedCol, to: context.scrollView)

    let colRulerFrame = context.colRuler.frame
    let lineRulerFrame = context.lineRuler.frame

    if headerInSV.intersects(colRulerFrame) {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Pinned header in scroll view \(headerInSV) intersects ColumnLetterRulerView \(colRulerFrame)"])
    }
    if headerInSV.intersects(lineRulerFrame) {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Pinned header in scroll view \(headerInSV) intersects LineNumberRulerView \(lineRulerFrame)"])
    }
    if colInSV.intersects(colRulerFrame) {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Pinned column in scroll view \(colInSV) intersects ColumnLetterRulerView \(colRulerFrame)"])
    }
    if colInSV.intersects(lineRulerFrame) {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Pinned column in scroll view \(colInSV) intersects LineNumberRulerView \(lineRulerFrame)"])
    }

    // Must be positioned immediately adjacent to ruler edges
    guard headerInSV.minY >= colRulerFrame.maxY - 0.001 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Pinned header minY \(headerInSV.minY) is above horizontal ruler maxY \(colRulerFrame.maxY)"])
    }
    guard colInSV.minX >= lineRulerFrame.maxX - 0.001 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Pinned column minX \(colInSV.minX) is to the left of vertical ruler maxX \(lineRulerFrame.maxX)"])
    }
}

// 2. Freeze First Column: renders cell texts, background, and dividing gridline pinned adjacent to vertical ruler
func testFreezeFirstColumnRendersContentWhenScrolled() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstColumn = true

    let widths = tv.columnWidths()
    guard !widths.isEmpty else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "No column widths calculated"])
    }
    let col0Width = widths[0]

    // Scroll 150 points to the right
    context.scrollTo(x: 150.0, y: tv.horizontalRulerOffset)
    let vThick = tv.verticalRulerThickness

    guard let pinnedCol = tv.pinnedColumnRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "pinnedColumnRect() returned nil when freezeFirstColumn is true and scrolled horizontally"])
    }
    let expectedX = tv.clipBoundsOrigin.x + vThick
    guard abs(pinnedCol.origin.x - expectedX) < 0.1 && abs(pinnedCol.width - col0Width) < 0.1 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "pinnedColumnRect() has incorrect frame: \(pinnedCol), expected origin.x=\(expectedX), width=\(col0Width)"])
    }

    // Verify cell content retrieval for column 0 in frozen pane
    guard let cell0 = tv.frozenColumnCellContent(row: 0), cell0 == "ID" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Row 0 column 0 cell text should be 'ID', got '\(tv.frozenColumnCellContent(row: 0) ?? "nil")'"])
    }
    guard let cell1 = tv.frozenColumnCellContent(row: 1), cell1 == "ITEM_001" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Row 1 column 0 cell text should be 'ITEM_001', got '\(tv.frozenColumnCellContent(row: 1) ?? "nil")'"])
    }

    // Render bitmap and verify non-background text pixels
    guard let bitmap = context.renderToBitmap(rect: pinnedCol) else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Failed to render bitmap for pinned column"])
    }

    let row1 = tv.rowRect(for: 1) ?? NSRect(x: 0, y: 20, width: 100, height: 18)
    let sampleY = Int(row1.midY - pinnedCol.origin.y)
    var foundTextPixel = false
    let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.white
    for x in 5..<Int(col0Width - 5) {
        if let color = bitmap.colorAt(x: x, y: sampleY) {
            let dr = abs(color.redComponent - bg.redComponent)
            let dg = abs(color.greenComponent - bg.greenComponent)
            let db = abs(color.blueComponent - bg.blueComponent)
            if (dr + dg + db) > 0.2 {
                foundTextPixel = true
                break
            }
        }
    }
    guard foundTextPixel else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Pinned column 0 rendered as blank background with no text pixels"])
    }
}

// 3. Freeze Top Row: Pins below horizontal ruler, aligns headers with column widths and scrolls horizontally in sync
func testFreezeTopRowPinsAndAlignsHeaders() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstRow = true

    let widths = tv.columnWidths()
    guard widths.count >= 4 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected >= 4 columns, got \(widths.count)"])
    }

    // Scroll vertically by 200pt and horizontally by 80pt
    context.scrollTo(x: 80.0, y: 200.0)
    let vRect = tv.visibleRect
    let hThick = tv.horizontalRulerThickness

    guard let pinnedHeader = tv.pinnedHeaderRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "pinnedHeaderRect() returned nil when scrolled vertically with freezeFirstRow = true"])
    }
    guard abs(pinnedHeader.origin.y - (vRect.origin.y + hThick)) < 0.1 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "pinnedHeaderRect incorrect: \(pinnedHeader), expected y=\(vRect.origin.y + hThick)"])
    }

    // Verify header cell text retrieval
    guard let h0 = tv.frozenHeaderCellContent(column: 0), h0 == "ID" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Header col 0 expected 'ID', got '\(tv.frozenHeaderCellContent(column: 0) ?? "nil")'"])
    }
    guard let h1 = tv.frozenHeaderCellContent(column: 1), h1 == "Product" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Header col 1 expected 'Product', got '\(tv.frozenHeaderCellContent(column: 1) ?? "nil")'"])
    }
    guard let h2 = tv.frozenHeaderCellContent(column: 2), h2 == "Price" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Header col 2 expected 'Price', got '\(tv.frozenHeaderCellContent(column: 2) ?? "nil")'"])
    }

    // Render bitmap and verify non-background header pixels
    guard let bitmap = context.renderToBitmap(rect: pinnedHeader) else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Failed to render pinned header to bitmap"])
    }
    var foundHeaderPixel = false
    let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.white
    for x in 10..<Int(pinnedHeader.width - 10) {
        if let color = bitmap.colorAt(x: x, y: Int(pinnedHeader.height / 2)) {
            let dr = abs(color.redComponent - bg.redComponent)
            let dg = abs(color.greenComponent - bg.greenComponent)
            let db = abs(color.blueComponent - bg.blueComponent)
            if (dr + dg + db) > 0.15 {
                foundHeaderPixel = true
                break
            }
        }
    }
    guard foundHeaderPixel else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Pinned header row rendered with no text pixels"])
    }
}

// 4. Both frozen: Top-left cell (row 0, col 0) remains pinned at corner between both rulers
func testBothFreezePanesAnchorsCornerCell() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstRow = true
    tv.freezeFirstColumn = true

    let widths = tv.columnWidths()
    let col0Width = widths[0]
    let row0Height = tv.rowRect(for: 0)?.height ?? 18.0

    // Scroll both horizontally and vertically
    context.scrollTo(x: 120.0, y: 350.0)
    let vRect = tv.visibleRect
    let expectedOrigin = NSPoint(x: vRect.origin.x + tv.verticalRulerThickness, y: vRect.origin.y + tv.horizontalRulerThickness)

    guard let corner = tv.pinnedCornerRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "pinnedCornerRect() returned nil when both panes are frozen and scrolled"])
    }
    guard abs(corner.origin.x - expectedOrigin.x) < 0.1 && abs(corner.origin.y - expectedOrigin.y) < 0.1 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Corner origin mismatch: \(corner.origin), expected \(expectedOrigin)"])
    }
    guard abs(corner.width - col0Width) < 0.1 && abs(corner.height - row0Height) < 0.1 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Corner size mismatch: \(corner.size), expected (\(col0Width), \(row0Height))"])
    }

    guard let cornerText = tv.frozenCornerCellContent(), cornerText == "ID" else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Corner text expected 'ID', got '\(tv.frozenCornerCellContent() ?? "nil")'"])
    }
}

// 5. Preserving Viewport Scroll: Clicking pinned header, column, and corner does NOT snap viewport back to (0, 0)
func testClickingPinnedPanesPreservesScrollOffsets() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstRow = true
    tv.freezeFirstColumn = true

    let widths = tv.columnWidths()
    let col0Width = widths[0]
    let col1Width = widths[1]

    // Scroll both x and y to large offsets
    let targetX: CGFloat = 150.0
    let targetY: CGFloat = 250.0
    context.scrollTo(x: targetX, y: targetY)

    // PART A: Click pinned header cell in Column 2 (Price)
    // Document Column 2 is at col0Width + col1Width + 10.0
    guard let headerRect = tv.pinnedHeaderRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Missing pinnedHeaderRect"])
    }
    let col2DocX = col0Width + col1Width + 10.0
    let clickHeaderPt = NSPoint(x: col2DocX, y: headerRect.midY)

    sendMouseClick(tv, at: clickHeaderPt)

    let caretA = tv.caretCellCoordinates()
    guard caretA.row == 0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Click on pinned header expected row 0, got \(caretA.row)"])
    }
    // Vertical scroll offset must be preserved at targetY (NOT snapped back to 0 or -20!)
    let curYAfterHeader = context.scrollView.contentView.bounds.origin.y
    guard abs(curYAfterHeader - targetY) < 1.0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Click on pinned header snapped vertical scroll: got \(curYAfterHeader), expected \(targetY)"])
    }

    // PART B: Click pinned column cell in Row 15
    context.scrollTo(x: targetX, y: targetY)
    guard let colRect = tv.pinnedColumnRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Missing pinnedColumnRect"])
    }
    let clickColPt = NSPoint(x: colRect.midX, y: targetY + 80.0)

    sendMouseClick(tv, at: clickColPt)

    let caretB = tv.caretCellCoordinates()
    guard caretB.col == 0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Click on pinned column expected col 0, got \(caretB.col)"])
    }
    // Horizontal scroll offset must be preserved at targetX (NOT snapped back to 0 or -39!)
    let curXAfterCol = context.scrollView.contentView.bounds.origin.x
    guard abs(curXAfterCol - targetX) < 1.0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Click on pinned column snapped horizontal scroll: got \(curXAfterCol), expected \(targetX)"])
    }

    // PART C: Click pinned corner cell (0, 0)
    context.scrollTo(x: targetX, y: targetY)
    guard let cornerRect = tv.pinnedCornerRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "Missing pinnedCornerRect"])
    }
    let clickCornerPt = NSPoint(x: cornerRect.midX, y: cornerRect.midY)

    sendMouseClick(tv, at: clickCornerPt)

    let caretC = tv.caretCellCoordinates()
    guard caretC.row == 0 && caretC.col == 0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 47, userInfo: [NSLocalizedDescriptionKey: "Click on pinned corner expected (0, 0), got (\(caretC.row), \(caretC.col))"])
    }
    // Both horizontal and vertical scroll offsets must be preserved
    let curXAfterCorner = context.scrollView.contentView.bounds.origin.x
    let curYAfterCorner = context.scrollView.contentView.bounds.origin.y
    guard abs(curXAfterCorner - targetX) < 1.0 && abs(curYAfterCorner - targetY) < 1.0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 48, userInfo: [NSLocalizedDescriptionKey: "Click on pinned corner snapped scroll: got (\(curXAfterCorner), \(curYAfterCorner)), expected (\(targetX), \(targetY))"])
    }
}

// 6. Smooth Activation without Dead Zone: Activates as soon as scroll exceeds horizontal/vertical ruler offset
func testFreezePanesSmoothActivationWithoutDeadZone() throws {
    let context = FreezePanesTestContext()
    let tv = context.tv
    tv.freezeFirstRow = true
    tv.freezeFirstColumn = true

    let hOffset = tv.horizontalRulerOffset
    let vOffset = tv.verticalRulerOffset

    // At exact unscroll (resetScrollToTopLeft), freeze panes are inactive
    context.scrollTo(x: vOffset, y: hOffset)
    guard !tv.isFirstRowFrozenActive && !tv.isFirstColumnFrozenActive else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Freeze panes should not be active at unscroll origin"])
    }

    // Scroll vertically by just 1 point past hOffset -> Row freeze activates immediately
    context.scrollTo(x: vOffset, y: hOffset + 1.0)
    guard tv.isFirstRowFrozenActive else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Row freeze should activate immediately past hOffset"])
    }
    guard tv.pinnedHeaderRect() != nil else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "pinnedHeaderRect() should be non-nil immediately past hOffset"])
    }

    // Scroll horizontally by just 1 point past vOffset -> Col freeze activates immediately
    context.scrollTo(x: vOffset + 1.0, y: hOffset)
    guard tv.isFirstColumnFrozenActive else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Col freeze should activate immediately past vOffset"])
    }
    guard tv.pinnedColumnRect() != nil else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "pinnedColumnRect() should be non-nil immediately past vOffset"])
    }
}

// 7. RFC 4180 Multiline Quoted Cells in Frozen Column
func testRFC4180MultilineQuotedCellsInFrozenColumn() throws {
    let csv = """
    "Code
    ID",Description,Price
    "101-A
    101-B","A multiline
    description cell
    spanning multiple lines",19.99
    "102-A",Standard Item,29.99

    """
    let context = FreezePanesTestContext(csv: csv)
    let tv = context.tv
    tv.freezeFirstColumn = true
    tv.freezeFirstRow = true

    // Column 0 cell text should include newlines for multiline quoted fields
    guard let h0 = tv.frozenHeaderCellContent(column: 0), h0.contains("Code") && h0.contains("ID") else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "RFC 4180 multiline header expected 'Code\\nID', got '\(tv.frozenHeaderCellContent(column: 0) ?? "nil")'"])
    }
    guard let c1 = tv.frozenColumnCellContent(row: 1), c1.contains("101-A") && c1.contains("101-B") else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "RFC 4180 multiline data expected '101-A\\n101-B', got '\(tv.frozenColumnCellContent(row: 1) ?? "nil")'"])
    }

    // Row 1 height must accommodate multiple lines (> 30pt)
    guard let r1Rect = tv.rowRect(for: 1), r1Rect.height > 30.0 else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Row 1 height should expand for multiline quotes, got \(tv.rowRect(for: 1)?.height ?? 0)"])
    }

    // Scroll horizontally and verify pinned column renders valid bitmap
    context.scrollTo(x: 100.0, y: tv.horizontalRulerOffset)
    guard let pinnedCol = tv.pinnedColumnRect() else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Missing pinnedColumnRect"])
    }
    guard let bitmap = context.renderToBitmap(rect: pinnedCol) else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 64, userInfo: [NSLocalizedDescriptionKey: "Failed to render bitmap for multiline RFC 4180 pinned column"])
    }

    var foundTextPixel = false
    let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? NSColor.white
    for x in 5..<Int(pinnedCol.width - 5) {
        if let color = bitmap.colorAt(x: x, y: Int(r1Rect.height / 2)) {
            let dr = abs(color.redComponent - bg.redComponent)
            let dg = abs(color.greenComponent - bg.greenComponent)
            let db = abs(color.blueComponent - bg.blueComponent)
            if (dr + dg + db) > 0.15 {
                foundTextPixel = true
                break
            }
        }
    }
    guard foundTextPixel else {
        throw NSError(domain: "SpreadsheetFreezePanesTests", code: 65, userInfo: [NSLocalizedDescriptionKey: "Multiline RFC 4180 pinned column cell rendered without text pixels"])
    }
}

// MARK: - Main Runner

let tests: [(String, () throws -> Void)] = [
    ("testFreezePanesDoNotIntersectRulers", testFreezePanesDoNotIntersectRulers),
    ("testFreezeFirstColumnRendersContentWhenScrolled", testFreezeFirstColumnRendersContentWhenScrolled),
    ("testFreezeTopRowPinsAndAlignsHeaders", testFreezeTopRowPinsAndAlignsHeaders),
    ("testBothFreezePanesAnchorsCornerCell", testBothFreezePanesAnchorsCornerCell),
    ("testClickingPinnedPanesPreservesScrollOffsets", testClickingPinnedPanesPreservesScrollOffsets),
    ("testFreezePanesSmoothActivationWithoutDeadZone", testFreezePanesSmoothActivationWithoutDeadZone),
    ("testRFC4180MultilineQuotedCellsInFrozenColumn", testRFC4180MultilineQuotedCellsInFrozenColumn)
]

print("=== SpreadsheetFreezePanesTests ===")
var passedCount = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passedCount += 1
    }
}
print("Result: \(passedCount)/\(tests.count) tests passed.")
if passedCount != tests.count {
    exit(1)
}
