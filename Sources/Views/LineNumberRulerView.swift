import AppKit
import Engine
import CBridge

open class LineNumberRulerView: NSRulerView {
    override open var isFlipped: Bool {
        return true
    }

    public var activeRowDragRange: ClosedRange<Int>?
    public var dragStartRowIndex: Int?
    private var rulerTrackingArea: NSTrackingArea?

    private var _customUiScale: CGFloat?

    public var uiScale: CGFloat {
        get {
            return _customUiScale ?? (scrollView?.magnification ?? 1.0)
        }
        set {
            _customUiScale = newValue
            if let tv = (self.clientView as? NSTextView) ?? (self.scrollView?.documentView as? NSTextView) {
                updateThickness(for: tv)
            }
            self.needsDisplay = true
        }
    }

    private var targetTextView: VimMDTextView? {
        return (self.clientView as? VimMDTextView) ?? (self.scrollView?.documentView as? VimMDTextView)
    }

    public func cursorForPoint(_ point: NSPoint) -> NSCursor? {
        guard let tv = targetTextView, tv.isTabularDocument else { return nil }
        return VimMDTextView.rightwardArrowCursor
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
        let ptInTV = tv.convert(ptInRuler, from: self)
        if let row = tv.rowIndex(at: ptInTV, clamped: false) {
            dragStartRowIndex = row
            activeRowDragRange = row...row
            _ = tv.copyRowRange(from: row, to: row)
            tv.flashHighlight()
            self.needsDisplay = true
            return
        }
        super.mouseDown(with: event)
    }

    override open func mouseDragged(with event: NSEvent) {
        guard let tv = targetTextView, tv.isTabularDocument, let start = dragStartRowIndex else {
            super.mouseDragged(with: event)
            return
        }
        let ptInRuler = convert(event.locationInWindow, from: nil)
        let ptInTV = tv.convert(ptInRuler, from: self)
        let current = tv.rowIndex(at: ptInTV, clamped: true) ?? start
        let minR = min(start, current)
        let maxR = max(start, current)
        activeRowDragRange = minR...maxR
        self.needsDisplay = true
    }

    override open func mouseUp(with event: NSEvent) {
        guard let tv = targetTextView, tv.isTabularDocument else {
            super.mouseUp(with: event)
            return
        }
        if let range = activeRowDragRange, range.count > 1 {
            _ = tv.copyRowRange(from: range.lowerBound, to: range.upperBound)
            tv.flashHighlight()
        }
        dragStartRowIndex = nil
        activeRowDragRange = nil
        self.needsDisplay = true
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
        self.ruleThickness = 36.0 * uiScale
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
            selector: #selector(textDidChangeNotification(_:)),
            name: NSText.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rulerNeedsRedraw(_:)),
            name: NSView.frameDidChangeNotification,
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
        if let sv = self.scrollView, _customUiScale == nil, abs(self.uiScale - sv.magnification) > 0.001 {
            if let tv = (self.clientView as? NSTextView) ?? (self.scrollView?.documentView as? NSTextView) {
                updateThickness(for: tv)
            }
        }
        self.needsDisplay = true
    }

    @objc private func textDidChangeNotification(_ notification: Notification) {
        if let tv = (notification.object as? NSTextView),
           tv == self.clientView || tv == self.scrollView?.documentView {
            updateThickness(for: tv)
            self.needsDisplay = true
        }
    }

    public func updateThickness(for textView: NSTextView) {
        let lineCount: Int
        if let vimTextView = textView as? VimMDTextView, let session = vimTextView.session {
            lineCount = session.lineIndexTable.lineCount
        } else {
            let str = textView.string
            lineCount = max(1, str.isEmpty ? 1 : str.components(separatedBy: "\n").count)
        }

        let digits = max(3, String(lineCount).count)
        let scale = self.uiScale
        let sampleFont = NSFont.monospacedDigitSystemFont(ofSize: 11.0 * scale, weight: .regular)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: sampleFont]).width
        let targetThickness = ceil(CGFloat(digits) * digitWidth + 18.0 * scale)

        if abs(self.ruleThickness - targetThickness) > 0.5 {
            self.ruleThickness = targetThickness
            if let vimTV = textView as? VimMDTextView, vimTV.wrapLines && !vimTV.isTabularDocument {
                vimTV.applyWrapLinesSetting()
            }
        }
    }

    override open func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override open func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = (self.clientView as? NSTextView) ?? (self.scrollView?.documentView as? NSTextView),
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        // 1. Background fill
        NSColor.windowBackgroundColor.setFill()
        rect.fill()

        // 2. Right border separator line
        let separatorX = self.bounds.width - 0.5
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: separatorX, y: rect.minY))
        path.line(to: NSPoint(x: separatorX, y: rect.maxY))
        path.lineWidth = 1.0
        path.stroke()

        // 3. Dynamic thickness check
        updateThickness(for: textView)

        let activeLine: Int? = (textView as? VimMDTextView)?.session?.cursorPosition.line
        let contentString = textView.string as NSString
        let docLength = contentString.length

        if docLength == 0 {
            // Draw line 1 for empty document
            drawLineNumber(1, y: textView.textContainerInset.height * uiScale, rowHeight: 18.0 * uiScale, isActive: (activeLine == 1))
            return
        }

        // Visible glyphs in text view
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else {
            drawLineNumber(1, y: textView.textContainerInset.height * uiScale, rowHeight: 18.0 * uiScale, isActive: (activeLine == 1))
            return
        }

        var lastDrawnLine = -1

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] (lineRect, usedRect, container, range, stop) in
            guard let self = self else { return }
            let charRange = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)

            // Only draw line number on the first line fragment of a line (not soft wraps)
            let isStartOfLine = (charRange.location == 0 || contentString.character(at: charRange.location - 1) == 0x0A)
            guard isStartOfLine else { return }

            let lineNumber: Int
            if let vimTextView = textView as? VimMDTextView, let session = vimTextView.session {
                lineNumber = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: charRange.location).line
            } else {
                var count = 1
                for i in 0..<charRange.location {
                    if contentString.character(at: i) == 0x0A {
                        count += 1
                    }
                }
                lineNumber = count
            }

            if lineNumber != lastDrawnLine {
                lastDrawnLine = lineNumber
                let rectInRuler = self.convert(lineRect, from: textView)
                let isActive = (lineNumber == activeLine)
                self.drawLineNumber(lineNumber, y: rectInRuler.minY, rowHeight: rectInRuler.height, isActive: isActive)
            }
        }

        // Extra empty line fragment if text ends with newline
        if layoutManager.extraLineFragmentTextContainer != nil {
            let extraRect = layoutManager.extraLineFragmentRect
            let extraRectInRuler = self.convert(extraRect, from: textView)
            let extraLineNumber = lastDrawnLine > 0 ? (lastDrawnLine + 1) : 2
            let isActive = (extraLineNumber == activeLine)
            drawLineNumber(extraLineNumber, y: extraRectInRuler.minY, rowHeight: extraRectInRuler.height, isActive: isActive)
        }
    }

    public var activeFont: NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: 11.0 * uiScale, weight: .bold)
    }
    public var inactiveFont: NSFont {
        return NSFont.monospacedDigitSystemFont(ofSize: 11.0 * uiScale, weight: .regular)
    }
    public var activeAttrs: [NSAttributedString.Key: Any] {
        return [
            .font: activeFont,
            .foregroundColor: NSColor.white
        ]
    }
    public var inactiveAttrs: [NSAttributedString.Key: Any] {
        return [
            .font: inactiveFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }
    public var badgeHeight: CGFloat {
        return 16.0 * uiScale
    }
    public var horizontalPadding: CGFloat {
        return 6.0 * uiScale
    }
    public var textRightMargin: CGFloat {
        return 8.0 * uiScale
    }

    public func lineNumberTextRect(for number: Int, y: CGFloat, rowHeight: CGFloat = 18.0, isActive: Bool = true) -> NSRect {
        let font = isActive ? self.activeFont : self.inactiveFont
        let numStr = "\(number)" as NSString
        let textSize = numStr.size(withAttributes: [.font: font])

        let bHeight = self.badgeHeight
        let badgeY = y + max(0, (rowHeight - bHeight) / 2.0)
        let textY = badgeY + (bHeight - textSize.height) / 2.0

        let effectiveWidth = max(self.bounds.width, self.ruleThickness)
        let textRightX = effectiveWidth - self.textRightMargin
        let textLeftX = textRightX - textSize.width

        return NSRect(x: textLeftX, y: textY, width: textSize.width, height: textSize.height)
    }

    public func activeRowBadgeRect(for number: Int, y: CGFloat, rowHeight: CGFloat = 18.0) -> NSRect {
        let textRect = lineNumberTextRect(for: number, y: y, rowHeight: rowHeight, isActive: true)
        let bHeight = self.badgeHeight
        let badgeY = y + max(0, (rowHeight - bHeight) / 2.0)
        let badgeLeft = textRect.minX - self.horizontalPadding
        let badgeWidth = textRect.width + 2.0 * self.horizontalPadding
        return NSRect(x: badgeLeft, y: badgeY, width: badgeWidth, height: bHeight)
    }

    private func drawLineNumber(_ number: Int, y: CGFloat, rowHeight: CGFloat = 18.0, isActive: Bool) {
        let effectiveRowHeight = rowHeight > 0 ? rowHeight : (18.0 * uiScale)
        if let range = activeRowDragRange, range.contains(number - 1) {
            let highlightRect = NSRect(x: 0, y: y, width: bounds.width, height: effectiveRowHeight)
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
            highlightRect.fill()
        }

        let textRect = lineNumberTextRect(for: number, y: y, rowHeight: effectiveRowHeight, isActive: isActive)
        let numStr = "\(number)" as NSString

        if isActive {
            let currentMode: VimEngineMode
            if let tv = (self.clientView as? VimMDTextView) ?? (self.scrollView?.documentView as? VimMDTextView),
               let session = tv.session {
                currentMode = session.mode
            } else {
                currentMode = VIM_MODE_NORMAL
            }
            let badgeColor = VimModeTheme.color(for: currentMode)
            let bHeight = self.badgeHeight
            let hPadding = self.horizontalPadding
            let badgeLeft = textRect.minX - hPadding
            let badgeRight = textRect.maxX + hPadding
            let badgeWidth = badgeRight - badgeLeft
            let badgeY = y + max(0, (effectiveRowHeight - bHeight) / 2.0)
            let badgeRect = NSRect(x: badgeLeft, y: badgeY, width: badgeWidth, height: bHeight)
            let r = badgeRect.height / 2.0
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: r, yRadius: r)
            badgeColor.setFill()
            badgePath.fill()

            numStr.draw(in: textRect, withAttributes: self.activeAttrs)
        } else {
            numStr.draw(in: textRect, withAttributes: self.inactiveAttrs)
        }
    }
}
