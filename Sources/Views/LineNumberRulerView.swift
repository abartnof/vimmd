import AppKit
import Engine

open class LineNumberRulerView: NSRulerView {
    override open var isFlipped: Bool {
        return true
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
        self.ruleThickness = 36.0
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func rulerNeedsRedraw(_ notification: Notification) {
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
        let sampleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: sampleFont]).width
        let targetThickness = ceil(CGFloat(digits) * digitWidth + 18.0)

        if abs(self.ruleThickness - targetThickness) > 0.5 {
            self.ruleThickness = targetThickness
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
            drawLineNumber(1, y: textView.textContainerInset.height, isActive: (activeLine == 1))
            return
        }

        // Visible glyphs in text view
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else {
            drawLineNumber(1, y: textView.textContainerInset.height, isActive: (activeLine == 1))
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
                self.drawLineNumber(lineNumber, y: rectInRuler.minY, isActive: isActive)
            }
        }

        // Extra empty line fragment if text ends with newline
        if layoutManager.extraLineFragmentTextContainer != nil {
            let extraRect = layoutManager.extraLineFragmentRect
            let extraRectInRuler = self.convert(extraRect, from: textView)
            let extraLineNumber = lastDrawnLine > 0 ? (lastDrawnLine + 1) : 2
            let isActive = (extraLineNumber == activeLine)
            drawLineNumber(extraLineNumber, y: extraRectInRuler.minY, isActive: isActive)
        }
    }

    private func drawLineNumber(_ number: Int, y: CGFloat, isActive: Bool) {
        let font = isActive
            ? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            : NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let color = isActive ? NSColor.controlAccentColor : NSColor.secondaryLabelColor

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let numStr = "\(number)" as NSString
        let rightMargin: CGFloat = 8.0
        let drawWidth = max(0, self.bounds.width - rightMargin - 4.0)
        let drawRect = NSRect(x: 4.0, y: y, width: drawWidth, height: font.pointSize + 4.0)
        numStr.draw(in: drawRect, withAttributes: attrs)
    }
}
