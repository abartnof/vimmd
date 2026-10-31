import AppKit
import Engine

open class ColumnLetterRulerView: NSRulerView {
    override open var isFlipped: Bool {
        return true
    }

    public var activeColDragRange: ClosedRange<Int>?
    public var dragStartColIndex: Int?
    private var rulerTrackingArea: NSTrackingArea?

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
        self.ruleThickness = 22.0
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func rulerNeedsRedraw(_ notification: Notification) {
        self.needsDisplay = true
    }

    @objc private func textDidChangeNotification(_ notification: Notification) {
        self.needsDisplay = true
    }

    private var targetTextView: VimMDTextView? {
        return (self.clientView as? VimMDTextView) ?? (self.scrollView?.documentView as? VimMDTextView)
    }

    public func columnIndex(at point: NSPoint) -> Int? {
        guard let tv = targetTextView else { return nil }
        let ptInTV = tv.convert(point, from: self)
        return tv.columnIndex(at: ptInTV, clamped: false)
    }

    // MARK: - Cursor Handling

    public func cursorForPoint(_ point: NSPoint) -> NSCursor? {
        guard let tv = targetTextView, tv.isTabularDocument else { return nil }
        return VimMDTextView.downwardArrowCursor
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
        if let cursor = cursorForPoint(.zero) {
            addCursorRect(bounds, cursor: cursor)
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
        guard let tv = targetTextView, tv.isTabularDocument, let start = dragStartColIndex else {
            super.mouseDragged(with: event)
            return
        }
        let ptInRuler = convert(event.locationInWindow, from: nil)
        let ptInTV = tv.convert(ptInRuler, from: self)
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

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let labelColor = NSColor.secondaryLabelColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelColor,
            .paragraphStyle: paragraphStyle
        ]

        for colIndex in 0..<widths.count {
            guard let colRectInTV = tv.columnRect(for: colIndex) else { continue }
            let rectInRuler = self.convert(colRectInTV, from: tv)
            let colBoundsInRuler = NSRect(x: rectInRuler.minX, y: 0, width: rectInRuler.width, height: bounds.height)

            guard colBoundsInRuler.intersects(rect) else { continue }

            // Highlight if active drag range covers this column
            if let activeRange = activeColDragRange, activeRange.contains(colIndex) {
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
                colBoundsInRuler.fill()
            }

            // Draw column letter label centered
            let letter = ColumnLetterRulerView.columnLetter(for: colIndex) as NSString
            let textY = max(0, (bounds.height - font.pointSize - 4.0) / 2.0)
            let textRect = NSRect(x: colBoundsInRuler.minX, y: textY, width: colBoundsInRuler.width, height: font.pointSize + 4.0)
            letter.draw(in: textRect, withAttributes: textAttrs)

            // Right vertical divider line
            let divX = colBoundsInRuler.maxX - 0.5
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
            let divPath = NSBezierPath()
            divPath.move(to: NSPoint(x: divX, y: 2.0))
            divPath.line(to: NSPoint(x: divX, y: bounds.height - 2.0))
            divPath.lineWidth = 1.0
            divPath.stroke()
        }
    }
}
