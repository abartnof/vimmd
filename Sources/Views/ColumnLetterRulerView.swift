import AppKit
import Engine

open class ColumnLetterRulerView: NSRulerView {
    override open var isFlipped: Bool {
        return true
    }

    public var activeColDragRange: ClosedRange<Int>?
    public var dragStartColIndex: Int?
    public var isResizingColumn: Bool = false
    public var resizingColumnIndex: Int?
    public var resizeStartX: CGFloat = 0
    public var initialColumnWidth: CGFloat = 0
    private var rulerTrackingArea: NSTrackingArea?

    private var _customUiScale: CGFloat?

    public var uiScale: CGFloat {
        get {
            return _customUiScale ?? (scrollView?.magnification ?? 1.0)
        }
        set {
            _customUiScale = newValue
            self.reservedThicknessForMarkers = 0.0
            self.ruleThickness = 20.0 * newValue
            self.needsDisplay = true
        }
    }

    public var font: NSFont {
        return NSFont.monospacedSystemFont(ofSize: 11.0 * uiScale, weight: .bold)
    }

    // MARK: - Disable Ruler Accessories and Markers

    override open var accessoryView: NSView? {
        get { return nil }
        set {}
    }

    override open var markers: [NSRulerMarker]? {
        get { return nil }
        set {}
    }

    override open func addMarker(_ marker: NSRulerMarker) {
        // Safe no-op: ColumnLetterRulerView does not support text markers
    }

    override open func removeMarker(_ marker: NSRulerMarker) {
        // Safe no-op
    }

    override open func trackMarker(_ marker: NSRulerMarker, withMouseEvent event: NSEvent) -> Bool {
        return false
    }

    public func trackMarker(_ marker: NSRulerMarker, with event: NSEvent) -> Bool {
        return false
    }

    override open func addSubview(_ view: NSView) {
        // Discard all subviews to prevent AppKit text formatting ruler controls from attaching
    }

    override open func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo otherView: NSView?) {
        // Discard all subviews to prevent AppKit text formatting ruler controls from attaching
    }

    override open func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        subview.removeFromSuperview()
    }

    override open func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
    }

    public static func columnLetter(for columnIndex: Int) -> String {
        var index = columnIndex
        var result = ""
        while index >= 0 {
            let remainder = index % 26
            let char = Character(UnicodeScalar(65 + remainder)!)
            result = String(char) + result
            index = (index / 26) - 1
        }
        return result
    }

    public override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        setupRuler()
    }

    required public init(coder: NSCoder) {
        super.init(coder: coder)
        setupRuler()
    }

    private func setupRuler() {
        self.reservedThicknessForMarkers = 0.0
        self.ruleThickness = 20.0 * self.uiScale
        super.accessoryView = nil
        super.markers = nil
        for sub in self.subviews {
            sub.removeFromSuperview()
        }
        guard let scrollView = self.scrollView else { return }
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulerNeedsRedraw(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulerNeedsRedraw(_:)),
            name: NSView.frameDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChangeNotification(_:)),
            name: NSText.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulerNeedsRedraw(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func rulerNeedsRedraw(_ notification: Notification) {
        self.reservedThicknessForMarkers = 0.0
        if let sv = self.scrollView, _customUiScale == nil, abs(self.uiScale - sv.magnification) > 0.001 {
            self.ruleThickness = 20.0 * sv.magnification
        }
        self.needsDisplay = true
        self.window?.invalidateCursorRects(for: self)
    }

    @objc private func textDidChangeNotification(_ notification: Notification) {
        self.needsDisplay = true
    }

    private var targetTextView: VimMDTextView? {
        return (self.clientView as? VimMDTextView) ?? (self.scrollView?.documentView as? VimMDTextView)
    }

    public func convertPointToTextView(_ point: NSPoint) -> NSPoint {
        guard let tv = targetTextView else { return point }
        if self.window != nil && self.window == tv.window {
            return tv.convert(point, from: self)
        }
        if let sv = self.scrollView, sv == tv.enclosingScrollView || (self.isDescendant(of: sv) && tv.isDescendant(of: sv)) {
            return tv.convert(point, from: self)
        }
        let scrollOffset = self.scrollView?.contentView.bounds.origin.x ?? 0
        let mag = self.scrollView?.magnification ?? 1.0
        return NSPoint(x: (point.x / mag) + scrollOffset, y: point.y)
    }

    public func convertPointFromTextView(_ point: NSPoint) -> NSPoint {
        guard let tv = targetTextView else { return point }
        if self.window != nil && self.window == tv.window {
            return self.convert(point, from: tv)
        }
        if let sv = self.scrollView, sv == tv.enclosingScrollView || (self.isDescendant(of: sv) && tv.isDescendant(of: sv)) {
            return self.convert(point, from: tv)
        }
        let scrollOffset = self.scrollView?.contentView.bounds.origin.x ?? 0
        let mag = self.scrollView?.magnification ?? 1.0
        return NSPoint(x: (point.x - scrollOffset) * mag, y: point.y)
    }

    public func convertRectFromTextView(_ rect: NSRect) -> NSRect {
        guard let tv = targetTextView else { return rect }
        if self.window != nil && self.window == tv.window {
            return self.convert(rect, from: tv)
        }
        if let sv = self.scrollView, sv == tv.enclosingScrollView || (self.isDescendant(of: sv) && tv.isDescendant(of: sv)) {
            return self.convert(rect, from: tv)
        }
        let scrollOffset = self.scrollView?.contentView.bounds.origin.x ?? 0
        let mag = self.scrollView?.magnification ?? 1.0
        return NSRect(x: (rect.origin.x - scrollOffset) * mag, y: rect.origin.y, width: rect.width * mag, height: rect.height)
    }

    public func columnIndex(at point: NSPoint) -> Int? {
        guard let tv = targetTextView else { return nil }
        let ptInTV = convertPointToTextView(point)
        return tv.columnIndex(at: ptInTV, clamped: false)
    }

    public func dividerColumnIndex(at point: NSPoint, hitTolerance: CGFloat = 4.0) -> Int? {
        guard let tv = targetTextView, tv.isTabularDocument else { return nil }
        let widths = tv.columnWidths()
        guard !widths.isEmpty else { return nil }

        var runningStartX = tv.textContainerInset.width
        for (i, w) in widths.enumerated() {
            runningStartX += w
            let divPtInRuler = convertPointFromTextView(NSPoint(x: runningStartX, y: 0))
            if abs(point.x - divPtInRuler.x) <= hitTolerance {
                return i
            }
        }
        return nil
    }

    // MARK: - Cursor Handling

    public func cursorForPoint(_ point: NSPoint) -> NSCursor? {
        guard let tv = targetTextView, tv.isTabularDocument else { return nil }
        if isResizingColumn {
            return NSCursor.resizeLeftRight
        }
        if dividerColumnIndex(at: point) != nil {
            return NSCursor.resizeLeftRight
        }
        if columnIndex(at: point) != nil {
            return VimMDTextView.downwardArrowCursor
        }
        return nil
    }

    override open func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = rulerTrackingArea {
            removeTrackingArea(old)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        rulerTrackingArea = tracking
    }

    override open func resetCursorRects() {
        super.resetCursorRects()
        guard let tv = targetTextView, tv.isTabularDocument else { return }

        let widths = tv.columnWidths()
        guard !widths.isEmpty else {
            if let cursor = cursorForPoint(.zero) {
                addCursorRect(bounds, cursor: cursor)
            }
            return
        }

        var runningStartX = tv.textContainerInset.width
        for (_, colWidth) in widths.enumerated() {
            let colRectInTV = NSRect(x: runningStartX, y: 0, width: colWidth, height: bounds.height)
            runningStartX += colWidth
            let rectInRuler = convertRectFromTextView(colRectInTV)
            let colBoundsInRuler = NSRect(x: rectInRuler.minX, y: 0, width: rectInRuler.width, height: bounds.height)

            let divRect = NSRect(x: colBoundsInRuler.maxX - 4.0, y: 0, width: 8.0, height: bounds.height)
            let colBodyRect = NSRect(x: colBoundsInRuler.minX, y: 0, width: max(0, colBoundsInRuler.width - 4.0), height: bounds.height)

            addCursorRect(colBodyRect, cursor: VimMDTextView.downwardArrowCursor)
            addCursorRect(divRect, cursor: NSCursor.resizeLeftRight)
        }
    }

    override open func cursorUpdate(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let cursor = cursorForPoint(pt) {
            cursor.set()
            return
        }
        super.cursorUpdate(with: event)
    }

    override open func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let cursor = cursorForPoint(pt) {
            cursor.set()
            return
        } else {
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    // MARK: - Click & Drag Interaction

    override open func mouseDown(with event: NSEvent) {
        guard let tv = targetTextView, tv.isTabularDocument else {
            super.mouseDown(with: event)
            return
        }
        let ptInRuler = convert(event.locationInWindow, from: nil)

        if let divCol = dividerColumnIndex(at: ptInRuler) {
            if event.clickCount == 2 {
                tv.customColumnWidths.removeValue(forKey: divCol)
                isResizingColumn = false
                resizingColumnIndex = nil
                tv.isResizingColumn = false
                tv.resizingColumnIndex = nil
                dragStartColIndex = nil
                activeColDragRange = nil
                tv.updateSyntaxStyling(force: true)
                if !tv.wrapTableCells {
                    tv.updateFrameForUnwrappedLines()
                }
                tv.needsDisplay = true
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
                return
            } else {
                let widths = tv.columnWidths()
                let initialW = divCol < widths.count ? widths[divCol] : 60.0
                isResizingColumn = true
                resizingColumnIndex = divCol
                resizeStartX = ptInRuler.x
                initialColumnWidth = initialW

                tv.isResizingColumn = true
                tv.resizingColumnIndex = divCol
                tv.resizeStartX = convertPointToTextView(ptInRuler).x
                tv.initialColumnWidth = initialW

                dragStartColIndex = nil
                activeColDragRange = nil
                self.needsDisplay = true
                tv.needsDisplay = true
                return
            }
        }

        if let col = columnIndex(at: ptInRuler) {
            dragStartColIndex = col
            activeColDragRange = col...col
            _ = tv.copyColumnRange(from: col, to: col)
            tv.flashHighlight()
            self.needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }

    override open func mouseDragged(with event: NSEvent) {
        guard let tv = targetTextView, tv.isTabularDocument else {
            super.mouseDragged(with: event)
            return
        }

        if isResizingColumn, let divCol = resizingColumnIndex {
            let ptInRuler = convert(event.locationInWindow, from: nil)
            let startInTV = convertPointToTextView(NSPoint(x: resizeStartX, y: 0)).x
            let currentInTV = convertPointToTextView(ptInRuler).x
            let deltaX = currentInTV - startInTV
            let newWidth = max(30.0, initialColumnWidth + deltaX)
            if newWidth.isFinite && !newWidth.isNaN {
                tv.customColumnWidths[divCol] = newWidth
                tv.updateSyntaxStyling(force: true)
                if !tv.wrapTableCells {
                    tv.updateFrameForUnwrappedLines()
                }
                tv.needsDisplay = true
                self.needsDisplay = true
            }
            return
        }

        guard let start = dragStartColIndex else {
            super.mouseDragged(with: event)
            return
        }
        let ptInRuler = convert(event.locationInWindow, from: nil)
        let ptInTV = convertPointToTextView(ptInRuler)
        let current = tv.columnIndex(at: ptInTV, clamped: true) ?? start
        let minC = min(start, current)
        let maxC = max(start, current)
        activeColDragRange = minC...maxC
        self.needsDisplay = true
    }

    override open func mouseUp(with event: NSEvent) {
        guard let tv = targetTextView, tv.isTabularDocument else {
            super.mouseUp(with: event)
            return
        }

        if isResizingColumn {
            isResizingColumn = false
            resizingColumnIndex = nil
            tv.isResizingColumn = false
            tv.resizingColumnIndex = nil
            tv.needsDisplay = true
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
            return
        }

        if let range = activeColDragRange, range.count > 1 {
            _ = tv.copyColumnRange(from: range.lowerBound, to: range.upperBound)
            tv.flashHighlight()
        }
        dragStartColIndex = nil
        activeColDragRange = nil
        self.needsDisplay = true
    }

    // MARK: - Drawing

    override open func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override open func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = targetTextView else { return }

        // 1. Background fill
        NSColor.windowBackgroundColor.setFill()
        rect.fill()

        // 2. Bottom separator line
        let separatorY = self.bounds.height - 0.5
        NSColor.separatorColor.setStroke()
        let sepPath = NSBezierPath()
        sepPath.move(to: NSPoint(x: rect.minX, y: separatorY))
        sepPath.line(to: NSPoint(x: rect.maxX, y: separatorY))
        sepPath.lineWidth = 1.0
        sepPath.stroke()

        guard tv.isTabularDocument else { return }

        let widths = tv.columnWidths()
        guard !widths.isEmpty else { return }

        let effectiveScale = self.uiScale
        let font = self.font
        let labelColor = NSColor.secondaryLabelColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor,
            .paragraphStyle: paragraphStyle
        ]

        var runningStartX = tv.textContainerInset.width
        for (colIndex, colWidth) in widths.enumerated() {
            let colRectInTV = NSRect(x: runningStartX, y: 0, width: colWidth, height: 20)
            runningStartX += colWidth
            let rectInRuler = convertRectFromTextView(colRectInTV)
            let colBoundsInRuler = NSRect(x: rectInRuler.minX, y: 0, width: rectInRuler.width, height: bounds.height)

            guard colBoundsInRuler.intersects(rect) else { continue }

            // Highlight if active drag range covers this column
            if let activeRange = activeColDragRange, activeRange.contains(colIndex) {
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
                colBoundsInRuler.fill()
            }

            // Draw column letter label centered
            let letter = ColumnLetterRulerView.columnLetter(for: colIndex) as NSString
            let textY = max(0, (bounds.height - font.pointSize - 4.0 * effectiveScale) / 2.0)
            let textRect = NSRect(x: colBoundsInRuler.minX, y: textY, width: colBoundsInRuler.width, height: font.pointSize + 4.0 * effectiveScale)
            letter.draw(in: textRect, withAttributes: textAttrs)

            // Right vertical divider line
            let divX = colBoundsInRuler.maxX - 0.5
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
            let divPath = NSBezierPath()
            divPath.move(to: NSPoint(x: divX, y: 2.0 * effectiveScale))
            divPath.line(to: NSPoint(x: divX, y: bounds.height - 2.0 * effectiveScale))
            divPath.lineWidth = 1.0
            divPath.stroke()
        }
    }
}
