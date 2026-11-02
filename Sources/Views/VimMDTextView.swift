import AppKit
import Engine
import CBridge

open class VimMDTextView: NSTextView {
    public weak var session: VimSession? {
        didSet {
            invalidateColumnWidthsCache()
            bindSession()
        }
    }

    /// Callback invoked when a Vim quit command (e.g. :q, :wq, ZZ, ZQ) is triggered.
    public var onQuitRequested: (() -> Void)?

    /// Callback invoked when cursor position moves (typing, arrows, clicks).
    public var onCursorMoved: (() -> Void)?

    /// Callback invoked when Vim mode changes.
    public var onModeChanged: ((VimEngineMode) -> Void)?

    /// Callback invoked when wrap lines is toggled.
    public var onToggleWrapLines: (() -> Void)?

    /// Callback invoked when status bar should be refreshed (command buffer, search, messages).
    public var onStatusChanged: (() -> Void)?

    /// Callback invoked when search execution or navigation updates the search status line.
    public var onSearchNavigated: ((String) -> Void)?

    /// Callback invoked when viewport zoom / magnification changes.
    public var onMagnificationChanged: ((CGFloat) -> Void)?

    /// Callback invoked when command mode is cancelled with Escape.
    public var onCommandCancelled: (() -> Void)?

    /// Callback invoked when flash feedback status is generated (e.g. header copy).
    public var onFlashFeedback: ((String) -> Void)?

    public var wrapLines: Bool = true {
        didSet {
            applyWrapLinesSetting()
        }
    }

    // MARK: - Spreadsheet Properties

    public var freezeFirstRow: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    public var freezeFirstColumn: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    public var wrapTableCells: Bool = false {
        didSet {
            updateSyntaxStyling(force: true)
            if !wrapTableCells {
                updateFrameForUnwrappedLines()
            }
            needsDisplay = true
        }
    }

    public var activeRowDragRange: ClosedRange<Int>?
    public var activeColDragRange: ClosedRange<Int>?
    public var transientFlashRect: NSRect?

    public var customColumnWidths: [Int: CGFloat] = [:] {
        didSet {
            invalidateColumnWidthsCache()
        }
    }
    public var isResizingColumn: Bool = false
    public var resizingColumnIndex: Int?
    public var resizeStartX: CGFloat = 0.0
    public var initialColumnWidth: CGFloat = 0.0

    private var tabularTrackingArea: NSTrackingArea?
    public var isDraggingRow: Bool = false
    public var isDraggingCol: Bool = false
    private var dragStartRowIndex: Int?
    private var dragStartColIndex: Int?

    public var currentSelectedRange: NSRange = NSRange(location: 0, length: 0)
    public var activeMarkedRange: NSRange = NSRange(location: NSNotFound, length: 0)

    public let syntaxResolver = MarkdownSyntaxResolver()
    public let tabularResolver = TabularSyntaxResolver()
    private var cachedColumnWidths: [CGFloat]?

    public func invalidateColumnWidthsCache() {
        cachedColumnWidths = nil
    }

    public enum DocumentSyntaxType: Equatable {
        case markdown
        case csv
        case tsv
        case plainText
    }

    public var documentSyntaxType: DocumentSyntaxType = .markdown {
        didSet {
            if documentSyntaxType == .plainText {
                self.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                self.textColor = NSColor.textColor
                self.typingAttributes = [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor.textColor
                ]
            }
            if isTabularDocument {
                wrapTableCells = true
            }
            updateHorizontalRulerVisibility()
            updateSyntaxStyling(force: true)
        }
    }

    public var isTabularDocument: Bool {
        get {
            return documentSyntaxType == .csv || documentSyntaxType == .tsv
        }
        set {
            if newValue {
                if documentSyntaxType != .csv && documentSyntaxType != .tsv {
                    documentSyntaxType = .csv
                }
            } else {
                documentSyntaxType = .markdown
            }
        }
    }

    public var isTSV: Bool {
        get {
            return documentSyntaxType == .tsv
        }
        set {
            if newValue {
                documentSyntaxType = .tsv
            } else if documentSyntaxType == .tsv {
                documentSyntaxType = .csv
            }
        }
    }

    override public init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        setupDefaults()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDefaults()
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupDefaults()
    }

    override open var usesRuler: Bool {
        get { return false }
        set {}
    }

    private func setupDefaults() {
        super.usesRuler = false
        self.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        self.textColor = NSColor.textColor
        self.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.textColor
        ]
        self.isVerticallyResizable = true
        self.isHorizontallyResizable = false
        self.autoresizingMask = [.width]
        self.textContainer?.widthTracksTextView = true
        self.textContainer?.containerSize = NSSize(width: self.frame.width, height: CGFloat.greatestFiniteMagnitude)
        self.insertionPointColor = VimModeTheme.color(for: VIM_MODE_NORMAL)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(delimiterColorDidChangeNotification(_:)),
            name: DelimiterColorManager.didChangeNotification,
            object: nil
        )
    }

    @objc private func delimiterColorDidChangeNotification(_ notification: Notification) {
        if Thread.isMainThread {
            self.updateSyntaxStyling(force: true)
            self.needsDisplay = true
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateSyntaxStyling(force: true)
                self.needsDisplay = true
            }
        }
    }

    override open func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if self.superview != nil {
            applyWrapLinesSetting()
            updateHorizontalRulerVisibility()
            if let contentView = enclosingScrollView?.contentView {
                contentView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollViewDidScroll(_:)),
                    name: NSView.boundsDidChangeNotification,
                    object: contentView
                )
            }
        }
    }

    public func updateHorizontalRulerVisibility() {
        self.usesRuler = false
        guard let sv = enclosingScrollView else { return }
        if isTabularDocument {
            if sv.horizontalRulerView == nil {
                let colRuler = ColumnLetterRulerView(scrollView: sv, orientation: .horizontalRuler)
                colRuler.clientView = self
                sv.horizontalRulerView = colRuler
            }
            sv.hasHorizontalRuler = true
            sv.rulersVisible = true
        } else {
            sv.hasHorizontalRuler = false
        }
    }

    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            let isAtTopLeft = session == nil || (session?.cursorPosition.line == 1 && (session?.cursorPosition.byteCol ?? 1) <= 1)
            if isAtTopLeft {
                pinViewportToTopLeft()
                DispatchQueue.main.async { [weak self] in
                    if self?.session == nil || (self?.session?.cursorPosition.line == 1 && (self?.session?.cursorPosition.byteCol ?? 1) <= 1) {
                        self?.pinViewportToTopLeft()
                    }
                }
            }
        }
    }

    public func pinViewportToTopLeft() {
        if self.frame.origin != .zero {
            self.setFrameOrigin(.zero)
        }
        self.scrollToBeginningOfDocument(nil)
        self.setSelectedRange(NSRange(location: 0, length: 0))
        if let session = self.session {
            session.setCursor(line: 1, byteCol: 1)
            synchronizeCaretWithSession()
            onCursorMoved?()
        }
        if let scrollView = self.enclosingScrollView {
            let rulerOffset: CGFloat = (scrollView.hasVerticalRuler && scrollView.rulersVisible) ? -(scrollView.verticalRulerView?.ruleThickness ?? 0) : 0
            scrollView.contentView.scroll(to: NSPoint(x: rulerOffset, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    /// After `scrollRangeToVisible`, repairs the clip view's vertical origin.
    ///
    /// NOTE: the negative-y behavior (clip `bounds.origin.y` of about -35 / -29.5 after keyboard
    /// navigation to Row 1 in a spreadsheet with the attached `ColumnLetterRulerView`) was
    /// established empirically, verified by the reproducing tests in
    /// `Row1KeyboardNavigationVisibilityTests`; it is not derived from AppKit documentation.
    ///
    /// - Tabular documents on line 1: pin y to 0 (x preserved) so Row 1 is never hidden, but only
    ///   when the caret remains visible at y == 0 (a tall wrapped first row must not lose the caret).
    /// - Everything else: only clamp a negative y back to 0, so wrapped prose with a long first
    ///   line keeps the caret on-screen.
    private func keepTopRowVisibleIfNeeded(line: Int, caretLocation: Int) {
        guard let scrollView = self.enclosingScrollView else { return }
        let clip = scrollView.contentView
        if isTabularDocument && line == 1 {
            let caretBottom = insertionBaseRect(at: caretLocation).maxY
            if caretBottom <= clip.bounds.height {
                if abs(clip.bounds.origin.y) > 0.001 {
                    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
                }
                scrollView.reflectScrolledClipView(clip)
                return
            }
        }
        if clip.bounds.origin.y < 0 {
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    public func resetScrollToTopLeft() {
        if self.frame.origin != .zero {
            self.setFrameOrigin(.zero)
        }
        self.scrollToBeginningOfDocument(nil)
        if let scrollView = self.enclosingScrollView {
            let rulerOffset: CGFloat = (scrollView.hasVerticalRuler && scrollView.rulersVisible) ? -(scrollView.verticalRulerView?.ruleThickness ?? 0) : 0
            scrollView.contentView.scroll(to: NSPoint(x: rulerOffset, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        if freezeFirstRow || freezeFirstColumn {
            self.needsDisplay = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override open func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = tabularTrackingArea {
            removeTrackingArea(old)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        tabularTrackingArea = tracking
    }

    public func applyWrapLinesSetting() {
        guard let textContainer = self.textContainer else { return }
        if wrapLines && !isTabularDocument {
            let contentWidth = enclosingScrollView?.contentSize.width ?? self.frame.width
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            self.isHorizontallyResizable = false
            self.autoresizingMask = [.width]
            if let scrollView = self.enclosingScrollView {
                scrollView.hasHorizontalScroller = false
                if abs(self.frame.width - contentWidth) > 0.5 {
                    self.setFrameSize(NSSize(width: contentWidth, height: self.frame.height))
                }
            }
            updateFrameHeightToFitText()
        } else {
            self.autoresizingMask = []
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            self.isHorizontallyResizable = true
            self.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if let scrollView = self.enclosingScrollView {
                scrollView.hasHorizontalScroller = true
            }
            updateFrameForUnwrappedLines()
        }
        if let session = self.session, session.cursorPosition.line == 1 && session.cursorPosition.byteCol <= 1 {
            resetScrollToTopLeft()
        }
    }

    public func updateFrameForUnwrappedLines() {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let viewportWidth = enclosingScrollView?.contentSize.width ?? self.frame.width
        let viewportHeight = enclosingScrollView?.contentSize.height ?? minSize.height

        var tableWidth: CGFloat = 0.0
        if isTabularDocument {
            tableWidth = columnWidths().reduce(0, +)
        }

        let targetWidth = max(viewportWidth, max(tableWidth, usedRect.size.width) + self.textContainerInset.width * 2 + 50.0)
        let targetHeight = max(viewportHeight, ceil(usedRect.size.height + self.textContainerInset.height * 2))
        self.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        if self.frame.origin != .zero {
            self.setFrameOrigin(.zero)
        }
        if let session = self.session, session.cursorPosition.line == 1 && session.cursorPosition.byteCol <= 1 {
            resetScrollToTopLeft()
        }
    }

    @objc open func toggleWrapLines(_ sender: Any? = nil) {
        if let callback = onToggleWrapLines {
            callback()
        } else {
            self.wrapLines = !self.wrapLines
        }
    }

    @objc open func toggleFreezeFirstRow(_ sender: Any? = nil) {
        self.freezeFirstRow = !self.freezeFirstRow
    }

    @objc open func toggleFreezeFirstColumn(_ sender: Any? = nil) {
        self.freezeFirstColumn = !self.freezeFirstColumn
    }

    @objc open func toggleWrapTableCells(_ sender: Any? = nil) {
        self.wrapTableCells = !self.wrapTableCells
    }

    public func updateFrameHeightToFitText() {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        if !wrapLines || isTabularDocument {
            updateFrameForUnwrappedLines()
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let viewportHeight = enclosingScrollView?.contentSize.height ?? minSize.height
        let targetHeight = max(viewportHeight, ceil(usedRect.size.height + self.textContainerInset.height * 2))
        if abs(self.frame.size.height - targetHeight) > 1.0 {
            self.setFrameSize(NSSize(width: self.frame.size.width, height: targetHeight))
            if self.frame.origin != .zero {
                self.setFrameOrigin(.zero)
            }
        }
    }

    override open func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - self.frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged && wrapLines && !isTabularDocument {
            updateFrameHeightToFitText()
        }
    }

    override open func scrollWheel(with event: NSEvent) {
        if let scrollView = self.enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    public func updateSyntaxStyling(force: Bool = false) {
        invalidateColumnWidthsCache()
        guard let storage = self.textStorage else { return }
        storage.beginEditing()
        switch documentSyntaxType {
        case .csv:
            tabularResolver.renderTabularSyntax(in: storage, isTSV: false, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)
        case .tsv:
            tabularResolver.renderTabularSyntax(in: storage, isTSV: true, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)
        case .plainText:
            let fullRange = NSRange(location: 0, length: storage.length)
            let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            if storage.length > 0 {
                storage.setAttributes([
                    .font: monoFont,
                    .foregroundColor: NSColor.textColor
                ], range: fullRange)
            }
        case .markdown:
            let currentMode = session?.mode ?? VIM_MODE_NORMAL
            let isInsert = (currentMode == VIM_MODE_INSERT || currentMode == VIM_MODE_REPLACE)
            let activeLine = session?.cursorPosition.line

            syntaxResolver.renderSyntax(
                in: storage,
                activeLineIndex: activeLine,
                isInsertMode: isInsert
            )
        }
        storage.endEditing()
        if isTabularDocument {
            enclosingScrollView?.horizontalRulerView?.needsDisplay = true
        }
    }

    override open var acceptsFirstResponder: Bool {
        return true
    }

    override open func becomeFirstResponder() -> Bool {
        self.needsDisplay = true
        return true
    }

    override open func resignFirstResponder() -> Bool {
        self.needsDisplay = true
        return true
    }

    private func bindSession() {
        guard let session = session else { return }
        self.string = session.serializeBuffer()
        session.onLineDeltaWithRange = { [weak self] startLine, deletedCount, newLines, targetRange in
            self?.applyDelta(startLine: startLine, deletedCount: deletedCount, targetRange: targetRange, newLines: newLines)
        }
        session.onModeChanged = { [weak self] mode in
            self?.updateSyntaxStyling()
            self?.updateCaretAppearance()
            self?.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            self?.onModeChanged?(mode)
        }
        session.onStatusChanged = { [weak self] in
            self?.onStatusChanged?()
        }
        updateSyntaxStyling(force: true)
        updateFrameHeightToFitText()
        synchronizeCaretWithSession()
        resetScrollToTopLeft()
    }

    public func applyDelta(startLine: Int = 0, deletedCount: Int = -1, targetRange: NSRange, newLines: [String]) {
        var replacement = newLines.joined(separator: "\n")
        let docLength = (self.textStorage?.length ?? (self.string as NSString).length)
        if deletedCount == 0 && !newLines.isEmpty && docLength > 0 {
            if targetRange.location < docLength {
                replacement += "\n"
            } else {
                let currentStr = (self.textStorage?.string ?? self.string) as NSString
                let prevChar = targetRange.location > 0 && targetRange.location <= currentStr.length
                    ? currentStr.character(at: targetRange.location - 1)
                    : (currentStr.length > 0 ? currentStr.character(at: currentStr.length - 1) : 0)
                if prevChar == 10 || prevChar == 13 {
                    replacement += "\n"
                } else {
                    replacement = "\n" + replacement
                }
            }
        }

        if let storage = self.textStorage {
            storage.beginEditing()
            if targetRange.location <= storage.length && targetRange.location + targetRange.length <= storage.length {
                storage.replaceCharacters(in: targetRange, with: replacement)
            }
            storage.endEditing()
        } else {
            let nsString = (self.string as NSString)
            if targetRange.location <= nsString.length && targetRange.location + targetRange.length <= nsString.length {
                self.string = nsString.replacingCharacters(in: targetRange, with: replacement)
            }
        }

        updateSyntaxStyling(force: true)
        updateFrameHeightToFitText()
        if let ruler = self.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.updateThickness(for: self)
            ruler.needsDisplay = true
        }
        synchronizeCaretWithSession()
    }

    public func applyDelta(targetRange: NSRange, newLines: [String]) {
        applyDelta(startLine: 0, deletedCount: -1, targetRange: targetRange, newLines: newLines)
    }

    public func applyDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        guard let session = session else { return }
        let targetRange = session.lineIndexTable.characterRange(startLine: startLine, count: deletedCount)
        applyDelta(startLine: startLine, deletedCount: deletedCount, targetRange: targetRange, newLines: newLines)
    }

    public func synchronizeCaretWithSession() {
        guard let session = session else { return }
        if session.mode == VIM_MODE_VISUAL, let visualRange = session.visualSelectionRange {
            self.currentSelectedRange = visualRange
            self.setSelectedRange(visualRange)
            self.scrollRangeToVisible(visualRange)
            keepTopRowVisibleIfNeeded(line: session.cursorPosition.line, caretLocation: visualRange.location)
        } else {
            let offset = session.cursorUtf16Offset
            let docLength = (self.string as NSString).length
            let clamped = max(0, min(docLength, offset))
            self.currentSelectedRange = NSRange(location: clamped, length: 0)
            self.setSelectedRange(self.currentSelectedRange)
            if clamped == 0 || (session.cursorPosition.line == 1 && session.cursorPosition.byteCol <= 1) {
                resetScrollToTopLeft()
            } else {
                self.scrollRangeToVisible(self.currentSelectedRange)
                keepTopRowVisibleIfNeeded(line: session.cursorPosition.line, caretLocation: clamped)
            }
        }
        if session.mode == VIM_MODE_INSERT || session.mode == VIM_MODE_REPLACE {
            updateSyntaxStyling()
        }
        updateCaretAppearance()
        self.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    // MARK: - Caret Morphology & Geometry

    public var caretMorphology: CursorMorphology {
        let mode = session?.mode ?? VIM_MODE_NORMAL
        return VimModeTheme.cursorMorphology(for: mode)
    }

    public var currentCaretRect: NSRect {
        let charIndex = selectedRange().location
        let cellWidth = glyphCellWidth(at: charIndex)
        let baseRect = insertionBaseRect(at: charIndex)
        return VimModeTheme.calculateCursorRect(for: caretMorphology, proposedRect: baseRect, cellWidth: cellWidth)
    }

    public var lastDrawnCursorRect: NSRect?

    public func fontAt(characterIndex: Int) -> NSFont {
        let fallbackFont = self.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        guard let storage = self.textStorage, storage.length > 0 else {
            return fallbackFont
        }
        let clamped = max(0, min(storage.length - 1, characterIndex))
        return (storage.attribute(.font, at: clamped, effectiveRange: nil) as? NSFont) ?? fallbackFont
    }

    public func glyphCellWidth(at charIndex: Int) -> CGFloat {
        let effectiveFont = fontAt(characterIndex: charIndex)
        let defaultWidth = (("M" as NSString).size(withAttributes: [.font: effectiveFont])).width

        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else {
            return defaultWidth
        }
        layoutManager.ensureLayout(for: textContainer)
        let nsString = self.string as NSString
        guard nsString.length > 0 && layoutManager.numberOfGlyphs > 0 else {
            return defaultWidth
        }
        guard charIndex >= 0 && charIndex < nsString.length else {
            return defaultWidth
        }
        let charRange = nsString.rangeOfComposedCharacterSequence(at: charIndex)
        let sub = nsString.substring(with: charRange)
        if sub.contains("\n") || sub.contains("\r") {
            return defaultWidth
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound && glyphRange.location + glyphRange.length <= layoutManager.numberOfGlyphs else {
            return defaultWidth
        }
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return (rect.width > 0 && rect.width < 200) ? rect.width : defaultWidth
    }

    public func insertionBaseRect(at charIndex: Int) -> NSRect {
        let effectiveFont = fontAt(characterIndex: charIndex)
        let defaultHeight = effectiveFont.pointSize + 3.0

        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 2.0, height: defaultHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let nsString = self.string as NSString
        guard nsString.length > 0 && layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 2.0, height: defaultHeight)
        }

        let clampedIndex = max(0, min(nsString.length, charIndex))

        if clampedIndex == nsString.length {
            let lastChar = nsString.character(at: nsString.length - 1)
            if lastChar == 10 || lastChar == 13 {
                let extraRect = layoutManager.extraLineFragmentRect
                if extraRect.height > 0 {
                    return NSRect(
                        x: textContainerInset.width,
                        y: extraRect.origin.y + textContainerInset.height,
                        width: 2.0,
                        height: extraRect.height
                    )
                } else {
                    let lastGlyph = layoutManager.numberOfGlyphs - 1
                    let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
                    return NSRect(
                        x: textContainerInset.width,
                        y: lineRect.maxY + textContainerInset.height,
                        width: 2.0,
                        height: lineRect.height > 0 ? lineRect.height : defaultHeight
                    )
                }
            } else {
                let lastGlyph = layoutManager.numberOfGlyphs - 1
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
                let lastGlyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: lastGlyph, length: 1), in: textContainer)
                return NSRect(
                    x: lastGlyphRect.maxX + textContainerInset.width,
                    y: lineRect.origin.y + textContainerInset.height,
                    width: 2.0,
                    height: lineRect.height > 0 ? lineRect.height : defaultHeight
                )
            }
        }

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 2.0, height: defaultHeight)
        }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let point = layoutManager.location(forGlyphAt: glyphIndex)
        let originX = point.x + textContainerInset.width
        let originY = lineRect.origin.y + textContainerInset.height
        let height = lineRect.height > 0 ? lineRect.height : defaultHeight
        return NSRect(x: originX, y: originY, width: 2.0, height: height)
    }

    public func updateCaretAppearance() {
        let mode = session?.mode ?? VIM_MODE_NORMAL
        self.insertionPointColor = VimModeTheme.color(for: mode)
        if let oldRect = lastDrawnCursorRect {
            self.setNeedsDisplay(oldRect)
        }
        let newRect = self.currentCaretRect
        self.setNeedsDisplay(newRect)
        self.updateInsertionPointStateAndRestartTimer(true)
    }

    override open func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let mode = session?.mode ?? VIM_MODE_NORMAL
        let morph = VimModeTheme.cursorMorphology(for: mode)
        let modeColor = VimModeTheme.color(for: mode)
        let charIndex = selectedRange().location
        let cellWidth = glyphCellWidth(at: charIndex)
        let cursorRect = VimModeTheme.calculateCursorRect(for: morph, proposedRect: rect, cellWidth: cellWidth)

        let nsStr = self.string as NSString
        let hasValidChar = charIndex >= 0 && charIndex < nsStr.length

        if flag {
            modeColor.setFill()
            cursorRect.fill()

            if morph == .block && hasValidChar {
                let charRange = nsStr.rangeOfComposedCharacterSequence(at: charIndex)
                let sub = nsStr.substring(with: charRange)
                if !sub.contains("\n") && !sub.contains("\r") && !sub.trimmingCharacters(in: .whitespaces).isEmpty {
                    let effectiveFont = fontAt(characterIndex: charIndex)
                    let invColor = NSColor.textBackgroundColor
                    let attr: [NSAttributedString.Key: Any] = [
                        .font: effectiveFont,
                        .foregroundColor: invColor
                    ]
                    let strSize = (sub as NSString).size(withAttributes: attr)
                    let textY = cursorRect.origin.y + max(0, (cursorRect.height - strSize.height) / 2.0)
                    (sub as NSString).draw(at: NSPoint(x: cursorRect.origin.x, y: textY), withAttributes: attr)
                }
            }
        } else {
            self.backgroundColor.setFill()
            cursorRect.fill()

            // Only redraw character when restoring from a block cursor.
            // Never draw characters inside the 2pt vertical bar or underline!
            if morph == .block && hasValidChar {
                let charRange = nsStr.rangeOfComposedCharacterSequence(at: charIndex)
                let sub = nsStr.substring(with: charRange)
                if !sub.contains("\n") && !sub.contains("\r") && !sub.trimmingCharacters(in: .whitespaces).isEmpty {
                    let effectiveFont = fontAt(characterIndex: charIndex)
                    let attr: [NSAttributedString.Key: Any] = [
                        .font: effectiveFont,
                        .foregroundColor: self.textColor ?? NSColor.textColor
                    ]
                    let strSize = (sub as NSString).size(withAttributes: attr)
                    let textY = cursorRect.origin.y + max(0, (cursorRect.height - strSize.height) / 2.0)
                    (sub as NSString).draw(at: NSPoint(x: cursorRect.origin.x, y: textY), withAttributes: attr)
                }
            }
        }
        lastDrawnCursorRect = cursorRect
    }

    override open func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        self.currentSelectedRange = charRange
    }

    // MARK: - Spreadsheet Geometry & Calculations

    public func columnWidths() -> [CGFloat] {
        if let cached = cachedColumnWidths {
            return cached
        }
        guard let storage = self.textStorage else { return [] }
        let widths = tabularResolver.calculateColumnWidths(in: storage, isTSV: isTSV, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)
        cachedColumnWidths = widths
        return widths
    }

    public func isPointInHeaderRow(_ point: NSPoint) -> Bool {
        guard isTabularDocument else { return false }
        let r0 = rowRect(for: 0)
        let r0Height = r0?.height ?? 18.0
        let inNormalHeader = (rowIndex(at: point) == 0) || (point.y >= 0 && point.y <= (r0?.maxY ?? r0Height))
        if inNormalHeader {
            return true
        }
        let vRect = self.visibleRect
        if freezeFirstRow && vRect.origin.y > 0 {
            if point.y >= vRect.origin.y && point.y <= vRect.origin.y + r0Height {
                return true
            }
        }
        return false
    }

    public func dividerColumnIndex(at point: NSPoint, hitTolerance: CGFloat = 4.0) -> Int? {
        guard isPointInHeaderRow(point) else { return nil }
        let widths = columnWidths()
        guard !widths.isEmpty else { return nil }
        var currentX = textContainerInset.width
        for (i, w) in widths.enumerated() {
            currentX += w
            if abs(point.x - currentX) <= hitTolerance {
                return i
            }
        }
        return nil
    }

    public func rowRect(for rowIndex: Int) -> NSRect? {
        guard let storage = self.textStorage else { return nil }
        let fullString = storage.string as NSString
        guard fullString.length > 0 else {
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: bounds.width, height: 18.0)
        }

        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)
        guard rowIndex >= 0 && rowIndex < recordRanges.count else {
            let y = CGFloat(rowIndex) * 18.0 + textContainerInset.height
            return NSRect(x: textContainerInset.width, y: y, width: bounds.width, height: 18.0)
        }

        let recordRange = recordRanges[rowIndex]
        let glyphRange = layoutManager.glyphRange(forCharacterRange: recordRange, actualCharacterRange: nil)
        var rowBoundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        if rowBoundingRect.height == 0 {
            rowBoundingRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        }
        rowBoundingRect.origin.x = textContainerInset.width
        rowBoundingRect.origin.y += textContainerInset.height
        rowBoundingRect.size.width = max(bounds.width, layoutManager.usedRect(for: textContainer).width)
        if rowBoundingRect.height == 0 { rowBoundingRect.size.height = 18.0 }
        return rowBoundingRect
    }

    public func columnRect(for colIndex: Int) -> NSRect? {
        let widths = columnWidths()
        guard colIndex >= 0 && colIndex < widths.count else { return nil }

        var startX = textContainerInset.width
        for i in 0..<colIndex {
            startX += widths[i]
        }
        let colWidth = widths[colIndex]
        let totalHeight = max(bounds.height, layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? bounds.height)
        return NSRect(x: startX, y: textContainerInset.height, width: colWidth, height: totalHeight)
    }

    public func rowIndex(at point: NSPoint, clamped: Bool = false) -> Int? {
        guard let storage = self.textStorage else { return clamped ? 0 : nil }
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return clamped ? 0 : nil }

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)
        guard !recordRanges.isEmpty else { return clamped ? 0 : nil }

        if let firstRect = rowRect(for: 0) {
            if point.y < firstRect.minY {
                return clamped ? 0 : nil
            }
        }

        for currentRecord in 0..<recordRanges.count {
            if let rect = rowRect(for: currentRecord) {
                if point.y >= rect.minY && point.y <= rect.maxY {
                    return currentRecord
                }
                if currentRecord + 1 < recordRanges.count, let nextRect = rowRect(for: currentRecord + 1) {
                    if point.y > rect.maxY && point.y < nextRect.minY {
                        return currentRecord
                    }
                }
            }
        }

        if clamped {
            return recordRanges.count - 1
        }
        return nil
    }

    public func columnIndex(at point: NSPoint, clamped: Bool = false) -> Int? {
        let widths = columnWidths()
        guard !widths.isEmpty else { return clamped ? 0 : nil }

        let startX = textContainerInset.width
        if point.x < startX {
            return clamped ? 0 : nil
        }

        var currentX = startX
        for (i, w) in widths.enumerated() {
            let nextX = currentX + w
            if point.x >= currentX && point.x <= nextX {
                return i
            }
            currentX = nextX
        }

        if clamped {
            return widths.count - 1
        }
        return nil
    }

    public func positionCaret(atRow r: Int, column c: Int, intraCellOffset: Int = 0) {
        guard let storage = self.textStorage else { return }
        let fullString = storage.string as NSString
        guard fullString.length > 0 else {
            self.setSelectedRange(NSRange(location: 0, length: 0))
            if let session = self.session {
                session.setCursor(line: 1, byteCol: 1)
                synchronizeCaretWithSession()
                onCursorMoved?()
            }
            return
        }

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)
        guard !recordRanges.isEmpty else { return }
        let clampedRow = max(0, min(recordRanges.count - 1, r))
        let lr = recordRanges[clampedRow]

        var contentLength = lr.length
        while contentLength > 0 {
            let char = fullString.character(at: lr.location + contentLength - 1)
            if char == 10 || char == 13 {
                contentLength -= 1
            } else {
                break
            }
        }
        let contentRange = NSRange(location: lr.location, length: contentLength)
        let (fields, _) = tabularResolver.parseLine(in: fullString, range: contentRange, isTSV: isTSV)

        let targetOffset: Int
        if fields.isEmpty {
            targetOffset = contentRange.location
        } else {
            let clampedCol = max(0, min(fields.count - 1, c))
            let targetField = fields[clampedCol]
            let clampedIntra = max(0, min(targetField.range.length, intraCellOffset))
            targetOffset = targetField.range.location + clampedIntra
        }

        self.setSelectedRange(NSRange(location: targetOffset, length: 0))
        if let session = self.session {
            let vimPos = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: targetOffset)
            session.setCursor(line: vimPos.line, byteCol: vimPos.byteCol)
            synchronizeCaretWithSession()
            onCursorMoved?()
        }
    }

    public func positionCaret(at point: NSPoint) {
        let r = rowIndex(at: point, clamped: true) ?? 0
        let c = columnIndex(at: point, clamped: true) ?? 0
        positionCaret(atRow: r, column: c)
    }

    public func totalTabularRows() -> Int {
        guard let storage = self.textStorage else { return 0 }
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return 0 }
        return tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV).count
    }

    public func currentTabularCellDetails() -> (row: Int, column: Int, intraCellOffset: Int)? {
        guard isTabularDocument, let storage = self.textStorage else { return nil }
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return (row: 0, column: 0, intraCellOffset: 0) }

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)
        guard !recordRanges.isEmpty else { return (row: 0, column: 0, intraCellOffset: 0) }

        let offset = session?.cursorUtf16Offset ?? selectedRange().location

        var foundRow = 0
        for (r, lr) in recordRanges.enumerated() {
            if offset >= lr.location && offset < (lr.location + lr.length) {
                foundRow = r
                break
            } else if offset == (lr.location + lr.length) && r == recordRanges.count - 1 {
                foundRow = r
                break
            }
        }
        if offset >= fullString.length {
            foundRow = recordRanges.count - 1
        }

        let lr = recordRanges[foundRow]
        var contentLength = lr.length
        while contentLength > 0 {
            let char = fullString.character(at: lr.location + contentLength - 1)
            if char == 10 || char == 13 {
                contentLength -= 1
            } else {
                break
            }
        }
        let contentRange = NSRange(location: lr.location, length: contentLength)
        let (fields, _) = tabularResolver.parseLine(in: fullString, range: contentRange, isTSV: isTSV)

        guard !fields.isEmpty else {
            return (row: foundRow, column: 0, intraCellOffset: 0)
        }

        var foundCol = 0
        for i in 0..<fields.count {
            if i < fields.count - 1 {
                let nextFieldStart = fields[i + 1].range.location
                if offset >= fields[i].range.location && offset < nextFieldStart {
                    foundCol = i
                    break
                }
            } else {
                if offset >= fields[i].range.location {
                    foundCol = i
                    break
                }
            }
        }
        let currentField = fields[foundCol]
        let intraCellOffset = max(0, offset - currentField.range.location)
        return (row: foundRow, column: foundCol, intraCellOffset: intraCellOffset)
    }

    public func currentTabularCell() -> (row: Int, column: Int)? {
        guard let details = currentTabularCellDetails() else { return nil }
        return (row: details.row, column: details.column)
    }

    public func updateStatusDisplay() {
        onStatusChanged?()
    }

    // MARK: - Spreadsheet Cursors & Hover Gestures

    public static func makeDownwardArrowCursor() -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 7, y: 2))
            path.line(to: NSPoint(x: 13, y: 2))
            path.line(to: NSPoint(x: 13, y: 10))
            path.line(to: NSPoint(x: 18, y: 10))
            path.line(to: NSPoint(x: 10, y: 18))
            path.line(to: NSPoint(x: 2, y: 10))
            path.line(to: NSPoint(x: 7, y: 10))
            path.close()

            NSColor.white.setFill()
            path.fill()
            NSColor.black.setStroke()
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            path.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 10, y: 18))
    }

    public static func makeRightwardArrowCursor() -> NSCursor {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2, y: 7))
            path.line(to: NSPoint(x: 10, y: 7))
            path.line(to: NSPoint(x: 10, y: 2))
            path.line(to: NSPoint(x: 18, y: 10))
            path.line(to: NSPoint(x: 10, y: 18))
            path.line(to: NSPoint(x: 10, y: 13))
            path.line(to: NSPoint(x: 2, y: 13))
            path.close()

            NSColor.white.setFill()
            path.fill()
            NSColor.black.setStroke()
            path.lineWidth = 1.5
            path.lineJoinStyle = .round
            path.stroke()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: 18, y: 10))
    }

    public static var downwardArrowCursor: NSCursor = makeDownwardArrowCursor()

    public static var rightwardArrowCursor: NSCursor = makeRightwardArrowCursor()

    public func cursorForPoint(_ point: NSPoint) -> NSCursor? {
        guard isTabularDocument else { return nil }
        if isResizingColumn {
            return NSCursor.resizeLeftRight
        }
        if isPointInHeaderRow(point) {
            if dividerColumnIndex(at: point) != nil {
                return NSCursor.resizeLeftRight
            }
        }
        return nil
    }

    override open func cursorUpdate(with event: NSEvent) {
        if isTabularDocument {
            let pt = convert(event.locationInWindow, from: nil)
            if let cursor = cursorForPoint(pt) {
                cursor.set()
                return
            }
        }
        super.cursorUpdate(with: event)
    }

    override open func mouseMoved(with event: NSEvent) {
        if isTabularDocument {
            let pt = convert(event.locationInWindow, from: nil)
            if let cursor = cursorForPoint(pt) {
                cursor.set()
                return
            } else {
                NSCursor.iBeam.set()
            }
        }
        super.mouseMoved(with: event)
    }

    // MARK: - Spreadsheet Click & Drag Selection

    public func handleTabularMouseDown(at point: NSPoint, clickCount: Int = 1) -> Bool {
        guard isTabularDocument else { return false }
        self.window?.makeFirstResponder(self)

        if isPointInHeaderRow(point) {
            if let divCol = dividerColumnIndex(at: point) {
                if clickCount == 2 {
                    customColumnWidths.removeValue(forKey: divCol)
                    isResizingColumn = false
                    resizingColumnIndex = nil
                    isDraggingCol = false
                    updateSyntaxStyling(force: true)
                    if !wrapTableCells {
                        updateFrameForUnwrappedLines()
                    }
                    needsDisplay = true
                    return true
                } else {
                    let widths = columnWidths()
                    let initialW = divCol < widths.count ? widths[divCol] : 60.0
                    isResizingColumn = true
                    resizingColumnIndex = divCol
                    resizeStartX = point.x
                    initialColumnWidth = initialW
                    isDraggingCol = false
                    needsDisplay = true
                    return true
                }
            }
            return false
        }
        return false
    }

    public func handleTabularMouseDragged(to point: NSPoint) {
        guard isTabularDocument else { return }
        if isResizingColumn, let i = resizingColumnIndex {
            let deltaX = point.x - resizeStartX
            let newWidth = max(30.0, initialColumnWidth + deltaX)
            if newWidth.isFinite && !newWidth.isNaN {
                customColumnWidths[i] = newWidth
                updateSyntaxStyling(force: true)
                if !wrapTableCells {
                    updateFrameForUnwrappedLines()
                }
                needsDisplay = true
            }
            return
        }
        if isDraggingCol, let start = dragStartColIndex {
            if let current = columnIndex(at: point) {
                let minC = min(start, current)
                let maxC = max(start, current)
                activeColDragRange = minC...maxC
                needsDisplay = true
            }
        } else if isDraggingRow, let start = dragStartRowIndex {
            if let current = rowIndex(at: point), current > 0 {
                let minR = min(start, current)
                let maxR = max(start, current)
                activeRowDragRange = minR...maxR
                needsDisplay = true
            }
        }
    }

    public func handleTabularMouseUp(at point: NSPoint) {
        guard isTabularDocument else { return }
        if isResizingColumn {
            isResizingColumn = false
            resizingColumnIndex = nil
            needsDisplay = true
            return
        }
        if isDraggingCol, let range = activeColDragRange {
            _ = copyColumnRange(from: range.lowerBound, to: range.upperBound)
            isDraggingCol = false
            dragStartColIndex = nil
            activeColDragRange = nil
            flashHighlight()
        } else if isDraggingRow, let range = activeRowDragRange {
            _ = copyRowRange(from: range.lowerBound, to: range.upperBound)
            isDraggingRow = false
            dragStartRowIndex = nil
            activeRowDragRange = nil
            flashHighlight()
        }
    }

    @discardableResult
    public func copyColumnRange(from startCol: Int, to endCol: Int) -> String {
        guard let storage = self.textStorage else { return "" }
        let minCol = min(startCol, endCol)
        let maxCol = max(startCol, endCol)
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return "" }

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)

        var resultLines: [String] = []
        let delimStr = isTSV ? "\t" : ","
        var firstColHeaderTitle = ""

        for (lIdx, lr) in recordRanges.enumerated() {
            var contentLength = lr.length
            while contentLength > 0 {
                let char = fullString.character(at: lr.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }
            let cr = NSRange(location: lr.location, length: contentLength)
            let (fields, _) = tabularResolver.parseLine(in: fullString, range: cr, isTSV: isTSV)

            var rowCols: [String] = []
            for c in minCol...maxCol {
                if c < fields.count {
                    let fr = fields[c].range
                    let cellVal = fullString.substring(with: fr)
                    rowCols.append(cellVal)
                    if lIdx == 0 && c == minCol {
                        firstColHeaderTitle = cellVal
                    }
                } else {
                    rowCols.append("")
                }
            }
            resultLines.append(rowCols.joined(separator: delimStr))
        }

        let joined = resultLines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)

        if let colStartRect = columnRect(for: minCol), let colEndRect = columnRect(for: maxCol) {
            self.transientFlashRect = NSRect(x: colStartRect.minX, y: 0, width: colEndRect.maxX - colStartRect.minX, height: bounds.height)
        }

        let feedback: String
        if minCol == maxCol {
            if !firstColHeaderTitle.isEmpty {
                feedback = "Column '\(firstColHeaderTitle)' copied to clipboard"
            } else {
                let letter = ColumnLetterRulerView.columnLetter(for: minCol)
                feedback = "Column \(letter) copied to clipboard"
            }
        } else {
            let startLetter = ColumnLetterRulerView.columnLetter(for: minCol)
            let endLetter = ColumnLetterRulerView.columnLetter(for: maxCol)
            feedback = "Columns \(startLetter)–\(endLetter) copied to clipboard"
        }
        onFlashFeedback?(feedback)
        needsDisplay = true
        return joined
    }

    @discardableResult
    public func copyRowRange(from startRow: Int, to endRow: Int) -> String {
        guard let storage = self.textStorage else { return "" }
        let minR = min(startRow, endRow)
        let maxR = max(startRow, endRow)
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return "" }

        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)

        var selectedLines: [String] = []
        for r in minR...maxR {
            guard r < recordRanges.count else { continue }
            let lr = recordRanges[r]
            var contentLength = lr.length
            while contentLength > 0 {
                let char = fullString.character(at: lr.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }
            let cr = NSRange(location: lr.location, length: contentLength)
            let lineText = fullString.substring(with: cr)
            selectedLines.append(lineText)
        }

        let joined = selectedLines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(joined, forType: .string)

        if let rowStartRect = rowRect(for: minR), let rowEndRect = rowRect(for: maxR) {
            self.transientFlashRect = NSRect(x: 0, y: rowStartRect.minY, width: bounds.width, height: rowEndRect.maxY - rowStartRect.minY)
        }

        let feedback: String
        if minR == maxR {
            feedback = "Row \(minR + 1) copied to clipboard"
        } else {
            feedback = "Rows \(minR + 1)–\(maxR + 1) copied to clipboard"
        }
        onFlashFeedback?(feedback)
        needsDisplay = true
        return joined
    }

    public func flashHighlight() {
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.transientFlashRect = nil
            self?.needsDisplay = true
        }
    }

    // MARK: - Dynamic Row Schema Alignment

    public func alignNewRowSchemaIfNeeded() {
        guard isTabularDocument, let session = session else { return }
        let buffer = session.serializeBuffer()
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return }

        let firstLine = String(lines[0])
        let delimChar: Character = isTSV ? "\t" : ","
        let headerCols = firstLine.split(separator: delimChar, omittingEmptySubsequences: false).count
        guard headerCols > 1 else { return }

        let curLineIdx = session.cursorPosition.line - 1
        if curLineIdx >= 0 && curLineIdx < lines.count {
            let curLineStr = String(lines[curLineIdx])
            if curLineStr.isEmpty {
                let placeholders = String(repeating: delimChar, count: headerCols - 1)
                session.feedKeys(placeholders)
                session.feedKeys("\u{1b}0i")
                synchronizeCaretWithSession()
            }
        }
    }

    // MARK: - Drawing: Gridlines & Frozen Panes

    override open func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isTabularDocument {
            drawGridlines(in: dirtyRect)
            drawSelectionAndFlash(in: dirtyRect)
            drawFrozenPanes(in: dirtyRect)
            drawResizeGuide(in: dirtyRect)
        }
    }

    public func drawGridlines(in dirtyRect: NSRect) {
        let widths = columnWidths()
        guard !widths.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.0

        // Vertical column dividers
        var x = textContainerInset.width
        let totalHeight = max(bounds.height, layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? bounds.height)
        for w in widths {
            x += w
            if x >= dirtyRect.minX - 5 && x <= dirtyRect.maxX + 5 {
                path.move(to: NSPoint(x: floor(x) + 0.5, y: 0))
                path.line(to: NSPoint(x: floor(x) + 0.5, y: totalHeight))
            }
        }

        // Horizontal row dividers
        guard let storage = self.textStorage else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        let fullString = storage.string as NSString
        let recordRanges = tabularResolver.parseRecordRanges(in: fullString, isTSV: isTSV)
        for (lineIdx, _) in recordRanges.enumerated() {
            if let rect = rowRect(for: lineIdx) {
                let y = rect.maxY
                if y >= dirtyRect.minY - 5 && y <= dirtyRect.maxY + 5 {
                    path.move(to: NSPoint(x: 0, y: floor(y) + 0.5))
                    path.line(to: NSPoint(x: bounds.width, y: floor(y) + 0.5))
                }
            }
        }

        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    public func drawSelectionAndFlash(in dirtyRect: NSRect) {
        if let rRange = activeRowDragRange {
            if let rStart = rowRect(for: rRange.lowerBound), let rEnd = rowRect(for: rRange.upperBound) {
                let highlightRect = NSRect(x: 0, y: rStart.minY, width: bounds.width, height: rEnd.maxY - rStart.minY)
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
                highlightRect.fill()
            }
        }
        if let cRange = activeColDragRange {
            if let cStart = columnRect(for: cRange.lowerBound), let cEnd = columnRect(for: cRange.upperBound) {
                let highlightRect = NSRect(x: cStart.minX, y: 0, width: cEnd.maxX - cStart.minX, height: bounds.height)
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill()
                highlightRect.fill()
            }
        }
        if let flash = transientFlashRect {
            NSColor.systemBlue.withAlphaComponent(0.2).setFill()
            flash.fill()
        }
    }

    public func drawResizeGuide(in dirtyRect: NSRect) {
        guard isResizingColumn, let resizingCol = resizingColumnIndex else { return }
        let widths = columnWidths()
        guard resizingCol >= 0 && resizingCol < widths.count else { return }
        var x = textContainerInset.width
        for k in 0...resizingCol {
            x += widths[k]
        }
        NSGraphicsContext.saveGraphicsState()
        NSColor.controlAccentColor.setStroke()
        let guidePath = NSBezierPath()
        guidePath.lineWidth = 2.0
        let totalHeight = max(bounds.height, layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? bounds.height)
        guidePath.move(to: NSPoint(x: floor(x), y: 0))
        guidePath.line(to: NSPoint(x: floor(x), y: totalHeight))
        guidePath.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    public func drawFrozenPanes(in dirtyRect: NSRect) {
        let vRect = self.visibleRect

        if freezeFirstRow && vRect.origin.y > 0, let row0 = rowRect(for: 0) {
            let pinnedHeaderRect = NSRect(x: vRect.origin.x, y: vRect.origin.y, width: vRect.width, height: row0.height)
            NSColor.windowBackgroundColor.setFill()
            pinnedHeaderRect.fill()
            NSColor.quaternaryLabelColor.setFill()
            pinnedHeaderRect.fill()

            if let storage = self.textStorage {
                let fullStr = storage.string as NSString
                if fullStr.length > 0 {
                    let lr = fullStr.lineRange(for: NSRange(location: 0, length: 0))
                    let headerAttr = storage.attributedSubstring(from: lr)
                    headerAttr.draw(in: NSRect(x: textContainerInset.width, y: vRect.origin.y, width: bounds.width, height: row0.height))
                }
            }

            NSColor.separatorColor.setStroke()
            let sep = NSBezierPath()
            sep.lineWidth = 1.0
            sep.move(to: NSPoint(x: vRect.origin.x, y: pinnedHeaderRect.maxY))
            sep.line(to: NSPoint(x: pinnedHeaderRect.maxX, y: pinnedHeaderRect.maxY))
            sep.stroke()
        }

        if freezeFirstColumn && vRect.origin.x > 0, let col0 = columnRect(for: 0) {
            let pinnedColRect = NSRect(x: vRect.origin.x, y: vRect.origin.y, width: col0.width, height: vRect.height)
            NSColor.windowBackgroundColor.setFill()
            pinnedColRect.fill()

            NSColor.separatorColor.setStroke()
            let sep = NSBezierPath()
            sep.lineWidth = 1.0
            sep.move(to: NSPoint(x: pinnedColRect.maxX, y: vRect.origin.y))
            sep.line(to: NSPoint(x: pinnedColRect.maxX, y: pinnedColRect.maxY))
            sep.stroke()
        }
    }

    // MARK: - Mouse & Keyboard Event Handling

    override open func mouseDown(with event: NSEvent) {
        self.window?.makeFirstResponder(self)
        if isTabularDocument {
            let pt = convert(event.locationInWindow, from: nil)
            if handleTabularMouseDown(at: pt, clickCount: event.clickCount) {
                return
            }
            let r = rowIndex(at: pt, clamped: true) ?? 0
            let c = columnIndex(at: pt, clamped: true) ?? 0
            positionCaret(atRow: r, column: c)
            return
        }

        super.mouseDown(with: event)
        guard let session = session else { return }
        let charIndex = self.selectedRange().location
        if charIndex != NSNotFound {
            let vimPos = session.lineIndexTable.vimPosition(fromDocumentUtf16Offset: charIndex)
            session.setCursor(line: vimPos.line, byteCol: vimPos.byteCol)
            synchronizeCaretWithSession()
            onCursorMoved?()
        }
    }

    override open func mouseDragged(with event: NSEvent) {
        if isTabularDocument && (isDraggingCol || isDraggingRow || isResizingColumn) {
            let pt = convert(event.locationInWindow, from: nil)
            handleTabularMouseDragged(to: pt)
            return
        }
        super.mouseDragged(with: event)
    }

    override open func mouseUp(with event: NSEvent) {
        if isTabularDocument && (isDraggingCol || isDraggingRow || isResizingColumn) {
            let pt = convert(event.locationInWindow, from: nil)
            handleTabularMouseUp(at: pt)
            return
        }
        super.mouseUp(with: event)
    }

    override open func keyDown(with event: NSEvent) {
        guard let session = session else {
            super.keyDown(with: event)
            return
        }

        // Intercept macOS Cmd shortcuts
        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers ?? ""
            if key == "=" || key == "+" {
                zoomIn(nil)
                return
            } else if key == "-" {
                zoomOut(nil)
                return
            } else if key == "0" {
                actualSize(nil)
                return
            }
            if key == "z" {
                if event.modifierFlags.contains(.shift) {
                    session.redo()
                } else {
                    session.undo()
                }
                synchronizeCaretWithSession()
                updateSyntaxStyling(force: true)
                if let ruler = self.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
                    ruler.updateThickness(for: self)
                    ruler.needsDisplay = true
                }
                onCursorMoved?()
                return
            }
            super.keyDown(with: event)
            return
        }

        if session.mode == VIM_MODE_NORMAL || session.mode == VIM_MODE_VISUAL || session.mode == VIM_MODE_COMMAND {
            let wasCommand = (session.mode == VIM_MODE_COMMAND)
            let isNormal = (session.mode == VIM_MODE_NORMAL)

            // Cell-relative vertical navigation in spreadsheets for Normal mode
            if isNormal && isTabularDocument && !session.hasPendingCommand {
                let chars = event.characters ?? ""
                let isDown = (chars == "j" || event.keyCode == 125 || chars == "\u{F701}")
                let isUp = (chars == "k" || event.keyCode == 126 || chars == "\u{F700}")

                var parsedCount: Int? = nil
                var isDownCount = false
                var isUpCount = false
                if !isDown && !isUp && chars.count > 1 {
                    if let lastChar = chars.last, (lastChar == "j" || lastChar == "k") {
                        let prefix = chars.dropLast()
                        if let c = Int(prefix), c > 0 {
                            parsedCount = c
                            if lastChar == "j" { isDownCount = true }
                            if lastChar == "k" { isUpCount = true }
                        }
                    }
                }

                if isDown || isUp || isDownCount || isUpCount {
                    if let currentCell = currentTabularCellDetails() {
                        let count = parsedCount ?? max(1, session.commandCount)
                        session.clearCommandCount()
                        let direction = (isDown || isDownCount) ? 1 : -1
                        let totalRows = totalTabularRows()
                        let targetRow = max(0, min(totalRows - 1, currentCell.row + direction * count))
                        positionCaret(atRow: targetRow, column: currentCell.column, intraCellOffset: currentCell.intraCellOffset)
                        updateStatusDisplay()
                        return
                    }
                }
            }

            if let chars = event.characters, !chars.isEmpty {
                let isSearchNav = isNormal && (chars == "n" || chars == "N" || chars == "p")
                let isSearchCR = wasCommand && (chars == "\r" || chars == "\n")
                let searchBuf = wasCommand ? session.commandLineBuffer : ""
                let isSearchCmd = searchBuf.hasPrefix("/")
                let searchPat = isSearchCmd ? String(searchBuf.dropFirst()) : ""

                session.feedKeys(chars)

                if isNormal && (chars == "o" || chars == "O") && isTabularDocument {
                    alignNewRowSchemaIfNeeded()
                }

                if isSearchCR && session.lastError == nil {
                    let activePat = searchPat.isEmpty ? (session.lastSearchPattern ?? "") : searchPat
                    if !activePat.isEmpty {
                        onSearchNavigated?("/\(activePat)")
                    }
                } else if isSearchNav && session.lastError == nil, let pat = session.lastSearchPattern {
                    onSearchNavigated?("/\(pat)")
                }

                if wasCommand && (chars == "\u{1b}") {
                    onCommandCancelled?()
                }

                synchronizeCaretWithSession()
                onCursorMoved?()
                onStatusChanged?()
                if session.shouldQuit {
                    onQuitRequested?()
                }
                return
            }
            if session.mode == VIM_MODE_COMMAND {
                if event.keyCode == 51 { // Backspace
                    session.feedKeys("\u{7f}")
                    synchronizeCaretWithSession()
                    onCursorMoved?()
                    onStatusChanged?()
                    return
                } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
                    let searchBuf = session.commandLineBuffer
                    let isSearchCmd = searchBuf.hasPrefix("/")
                    let searchPat = isSearchCmd ? String(searchBuf.dropFirst()) : ""

                    session.feedKeys("\r")

                    if isSearchCmd && session.lastError == nil {
                        let activePat = searchPat.isEmpty ? (session.lastSearchPattern ?? "") : searchPat
                        if !activePat.isEmpty {
                            onSearchNavigated?("/\(activePat)")
                        }
                    }

                    synchronizeCaretWithSession()
                    onCursorMoved?()
                    onStatusChanged?()
                    if session.shouldQuit {
                        onQuitRequested?()
                    }
                    return
                } else if event.keyCode == 53 { // Escape
                    onCommandCancelled?()
                    session.feedKeys("\u{1b}")
                    synchronizeCaretWithSession()
                    onCursorMoved?()
                    onStatusChanged?()
                    return
                }
            }
            return
        }

        // Insert mode
        // 1. Escape key
        if event.keyCode == 53 || event.characters == "\u{1b}" {
            session.feedKeys("\u{1b}")
            unmarkText()
            synchronizeCaretWithSession()
            onCursorMoved?()
            onStatusChanged?()
            return
        }

        // 1b. Spreadsheet cell-relative arrow keys
        if isTabularDocument {
            let chars = event.characters ?? ""
            let isDown = (event.keyCode == 125 || chars == "\u{F701}")
            let isUp = (event.keyCode == 126 || chars == "\u{F700}")
            if isDown || isUp {
                if let currentCell = currentTabularCellDetails() {
                    let direction = isDown ? 1 : -1
                    let totalRows = totalTabularRows()
                    let targetRow = max(0, min(totalRows - 1, currentCell.row + direction))
                    positionCaret(atRow: targetRow, column: currentCell.column, intraCellOffset: currentCell.intraCellOffset)
                    updateStatusDisplay()
                    return
                }
            }
        }

        // 2. Active IME composition
        if hasMarkedText() {
            if inputContext?.handleEvent(event) == true {
                return
            }
        }

        // 3. Direct Vim editing keys: Backspace, Return, Tab
        if event.keyCode == 51 { // Backspace
            session.feedKeys("\u{7f}")
            synchronizeCaretWithSession()
            onCursorMoved?()
            return
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            session.feedKeys("\r")
            if isTabularDocument {
                alignNewRowSchemaIfNeeded()
            }
            synchronizeCaretWithSession()
            onCursorMoved?()
            return
        } else if event.keyCode == 48 { // Tab
            session.feedKeys("\t")
            synchronizeCaretWithSession()
            if isTabularDocument {
                updateSyntaxStyling(force: true)
                if !wrapTableCells {
                    updateFrameForUnwrappedLines()
                }
            }
            onCursorMoved?()
            return
        }

        // 4. Delegate to inputContext if it handles the event
        if let inputContext = self.inputContext, inputContext.handleEvent(event) {
            return
        }

        // 5. Normal typing fallback
        if let chars = event.characters, !chars.isEmpty {
            session.feedKeys(chars)
            synchronizeCaretWithSession()
            if isTabularDocument && (chars.contains(",") || chars.contains("\t")) {
                updateSyntaxStyling(force: true)
                if !wrapTableCells {
                    updateFrameForUnwrappedLines()
                }
            }
            onCursorMoved?()
        }
    }

    override open func deleteBackward(_ sender: Any?) {
        guard let session = session, session.mode == VIM_MODE_INSERT || session.mode == VIM_MODE_COMMAND || session.mode == VIM_MODE_REPLACE else { return }
        session.feedKeys("\u{7f}")
        synchronizeCaretWithSession()
        onCursorMoved?()
    }

    // MARK: - Viewport Zoom Controls

    @objc @IBAction open func zoomIn(_ sender: Any?) {
        guard let sv = enclosingScrollView else { return }
        let current = sv.magnification
        let target = min(3.0, current + 0.1)
        sv.magnification = target
        onMagnificationChanged?(target)
    }

    @objc @IBAction open func zoomOut(_ sender: Any?) {
        guard let sv = enclosingScrollView else { return }
        let current = sv.magnification
        let target = max(0.5, current - 0.1)
        sv.magnification = target
        onMagnificationChanged?(target)
    }

    @objc @IBAction open func actualSize(_ sender: Any?) {
        guard let sv = enclosingScrollView else { return }
        let target: CGFloat = 1.0
        sv.magnification = target
        onMagnificationChanged?(target)
    }

    // MARK: - Undo & Redo Integration

    private var customUndoManager: UndoManager?

    override open var undoManager: UndoManager? {
        if customUndoManager == nil {
            customUndoManager = VimUndoManagerProxy(sessionProvider: { [weak self] in self?.session })
        }
        return customUndoManager
    }

    @objc @IBAction open func undo(_ sender: Any?) {
        guard let session = session else { return }
        session.undo()
        synchronizeCaretWithSession()
        updateSyntaxStyling(force: true)
        if let ruler = self.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.updateThickness(for: self)
            ruler.needsDisplay = true
        }
        onCursorMoved?()
    }

    @objc @IBAction open func redo(_ sender: Any?) {
        guard let session = session else { return }
        session.redo()
        synchronizeCaretWithSession()
        updateSyntaxStyling(force: true)
        if let ruler = self.enclosingScrollView?.verticalRulerView as? LineNumberRulerView {
            ruler.updateThickness(for: self)
            ruler.needsDisplay = true
        }
        onCursorMoved?()
    }

    override open func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleWrapLines(_:)) {
            if let menuItem = item as? NSMenuItem {
                menuItem.state = self.wrapLines ? .on : .off
            }
            return true
        }
        if item.action == #selector(toggleFreezeFirstRow(_:)) {
            guard isTabularDocument else { return false }
            if let menuItem = item as? NSMenuItem {
                menuItem.state = self.freezeFirstRow ? .on : .off
            }
            return true
        }
        if item.action == #selector(toggleFreezeFirstColumn(_:)) {
            guard isTabularDocument else { return false }
            if let menuItem = item as? NSMenuItem {
                menuItem.state = self.freezeFirstColumn ? .on : .off
            }
            return true
        }
        if item.action == #selector(toggleWrapTableCells(_:)) {
            guard isTabularDocument else { return false }
            if let menuItem = item as? NSMenuItem {
                menuItem.state = self.wrapTableCells ? .on : .off
            }
            return true
        }
        if item.action == #selector(VimMDTextView.undo(_:)) {
            return session?.canUndo ?? false
        }
        if item.action == #selector(VimMDTextView.redo(_:)) {
            return session?.canRedo ?? false
        }
        if item.action == #selector(VimMDTextView.zoomIn(_:)) ||
           item.action == #selector(VimMDTextView.zoomOut(_:)) ||
           item.action == #selector(VimMDTextView.actualSize(_:)) {
            return enclosingScrollView?.allowsMagnification ?? true
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Clipboard Synchronization

    override open func copy(_ sender: Any?) {
        guard let session = session else {
            super.copy(sender)
            return
        }

        if session.mode == VIM_MODE_VISUAL {
            session.feedKeys("y")
            synchronizeCaretWithSession()
            onCursorMoved?()
        } else {
            let range = self.selectedRange()
            if range.length > 0 {
                let nsStr = self.string as NSString
                if range.location + range.length <= nsStr.length {
                    let sub = nsStr.substring(with: range)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(sub, forType: .string)
                    session.setYankBuffer(text: sub, linewise: false)
                }
            } else {
                session.feedKeys("yy")
                synchronizeCaretWithSession()
                onCursorMoved?()
            }
        }
    }

    override open func paste(_ sender: Any?) {
        guard let session = session else {
            super.paste(sender)
            return
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }

        if session.mode == VIM_MODE_INSERT || session.mode == VIM_MODE_REPLACE {
            session.feedKeys(text)
            synchronizeCaretWithSession()
            onCursorMoved?()
        } else if session.mode == VIM_MODE_VISUAL {
            session.feedKeys("p")
            synchronizeCaretWithSession()
            onCursorMoved?()
        } else {
            session.feedKeys("p")
            synchronizeCaretWithSession()
            onCursorMoved?()
        }
    }

    // MARK: - NSTextInputClient overrides

    override open func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attr = string as? NSAttributedString {
            text = attr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }

        if session?.mode == VIM_MODE_INSERT || session?.mode == VIM_MODE_REPLACE {
            session?.feedKeys(text)
            synchronizeCaretWithSession()
        }
    }

    public var modeLabelText: String {
        guard let session = session else { return "" }
        return VimModeTheme.statusLabelText(for: session.mode)
    }

    override open func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attr = string as? NSAttributedString {
            text = attr.string
        } else if let str = string as? String {
            text = str
        } else {
            return
        }
        let loc = self.selectedRange().location
        self.activeMarkedRange = NSRange(location: loc, length: (text as NSString).length)
    }

    override open func unmarkText() {
        self.activeMarkedRange = NSRange(location: NSNotFound, length: 0)
    }

    override open func selectedRange() -> NSRange {
        return currentSelectedRange
    }

    override open func markedRange() -> NSRange {
        return activeMarkedRange
    }

    override open func hasMarkedText() -> Bool {
        return activeMarkedRange.location != NSNotFound
    }

    override open func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let nsString = self.string as NSString
        guard range.location < nsString.length else { return nil }
        let length = min(range.length, nsString.length - range.location)
        let sub = nsString.substring(with: NSRange(location: range.location, length: length))
        actualRange?.pointee = NSRange(location: range.location, length: length)
        return NSAttributedString(string: sub)
    }

    override open func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor]
    }

    override open func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        return self.frame
    }

    override open func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
}

private class VimUndoManagerProxy: UndoManager {
    private let sessionProvider: () -> VimSession?

    init(sessionProvider: @escaping () -> VimSession?) {
        self.sessionProvider = sessionProvider
        super.init()
    }

    override var canUndo: Bool {
        return sessionProvider()?.canUndo ?? false
    }

    override var canRedo: Bool {
        return sessionProvider()?.canRedo ?? false
    }

    override func undo() {
        sessionProvider()?.undo()
    }

    override func redo() {
        sessionProvider()?.redo()
    }
}
