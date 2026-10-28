import AppKit
import Engine
import CBridge

open class VimMDTextView: NSTextView {
    public weak var session: VimSession? {
        didSet {
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

    public var wrapLines: Bool = true {
        didSet {
            applyWrapLinesSetting()
        }
    }

    public var currentSelectedRange: NSRange = NSRange(location: 0, length: 0)
    public var activeMarkedRange: NSRange = NSRange(location: NSNotFound, length: 0)

    public let syntaxResolver = MarkdownSyntaxResolver()

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

    private func setupDefaults() {
        self.isVerticallyResizable = true
        self.isHorizontallyResizable = false
        self.autoresizingMask = [.width]
        self.textContainer?.widthTracksTextView = true
        self.textContainer?.containerSize = NSSize(width: self.frame.width, height: CGFloat.greatestFiniteMagnitude)
    }

    override open func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if self.superview != nil {
            applyWrapLinesSetting()
        }
    }

    public func applyWrapLinesSetting() {
        guard let textContainer = self.textContainer else { return }
        if wrapLines {
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
    }

    public func updateFrameForUnwrappedLines() {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let viewportWidth = enclosingScrollView?.contentSize.width ?? self.frame.width
        let viewportHeight = enclosingScrollView?.contentSize.height ?? minSize.height
        let targetWidth = max(viewportWidth, ceil(usedRect.size.width + self.textContainerInset.width * 2 + 50.0))
        let targetHeight = max(viewportHeight, ceil(usedRect.size.height + self.textContainerInset.height * 2))
        self.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
    }

    @objc open func toggleWrapLines(_ sender: Any? = nil) {
        if let callback = onToggleWrapLines {
            callback()
        } else {
            self.wrapLines = !self.wrapLines
        }
    }

    public func updateFrameHeightToFitText() {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        if !wrapLines {
            updateFrameForUnwrappedLines()
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let viewportHeight = enclosingScrollView?.contentSize.height ?? minSize.height
        let targetHeight = max(viewportHeight, ceil(usedRect.size.height + self.textContainerInset.height * 2))
        if abs(self.frame.size.height - targetHeight) > 1.0 {
            self.setFrameSize(NSSize(width: self.frame.size.width, height: targetHeight))
        }
    }

    override open func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - self.frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged && wrapLines {
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
        guard let storage = self.textStorage else { return }
        let currentMode = session?.mode ?? VIM_MODE_NORMAL
        let isInsert = (currentMode == VIM_MODE_INSERT)
        let activeLine = session?.cursorPosition.line

        storage.beginEditing()
        syntaxResolver.renderSyntax(
            in: storage,
            activeLineIndex: activeLine,
            isInsertMode: isInsert
        )
        storage.endEditing()
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
            self?.applyDelta(targetRange: targetRange, newLines: newLines)
        }
        session.onModeChanged = { [weak self] mode in
            self?.updateSyntaxStyling()
            self?.onModeChanged?(mode)
        }
        updateSyntaxStyling(force: true)
        updateFrameHeightToFitText()
        synchronizeCaretWithSession()
    }

    public func applyDelta(targetRange: NSRange, newLines: [String]) {
        let replacement = newLines.joined(separator: "\n")

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

    public func applyDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        guard let session = session else { return }
        let targetRange = session.lineIndexTable.characterRange(startLine: startLine, count: deletedCount)
        applyDelta(targetRange: targetRange, newLines: newLines)
    }

    public func synchronizeCaretWithSession() {
        guard let session = session else { return }
        if session.mode == VIM_MODE_VISUAL, let visualRange = session.visualSelectionRange {
            self.currentSelectedRange = visualRange
            self.setSelectedRange(visualRange)
            self.scrollRangeToVisible(visualRange)
        } else {
            let offset = session.cursorUtf16Offset
            let docLength = (self.string as NSString).length
            let clamped = max(0, min(docLength, offset))
            self.currentSelectedRange = NSRange(location: clamped, length: 0)
            self.setSelectedRange(self.currentSelectedRange)
            self.scrollRangeToVisible(self.currentSelectedRange)
        }
        if session.mode == VIM_MODE_INSERT {
            updateSyntaxStyling()
        }
        self.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override open func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
        self.currentSelectedRange = charRange
    }

    override open func mouseDown(with event: NSEvent) {
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

    override open func keyDown(with event: NSEvent) {
        guard let session = session else {
            super.keyDown(with: event)
            return
        }

        // Intercept macOS Cmd+Z (Undo) and Cmd+Shift+Z (Redo)
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "z" {
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
            if let chars = event.characters {
                session.feedKeys(chars)
                synchronizeCaretWithSession()
                onCursorMoved?()
                if session.shouldQuit {
                    onQuitRequested?()
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
            return
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
            synchronizeCaretWithSession()
            onCursorMoved?()
            return
        } else if event.keyCode == 48 { // Tab
            session.feedKeys("\t")
            synchronizeCaretWithSession()
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
            onCursorMoved?()
        }
    }

    override open func deleteBackward(_ sender: Any?) {
        guard let session = session, session.mode == VIM_MODE_INSERT else { return }
        session.feedKeys("\u{7f}")
        synchronizeCaretWithSession()
        onCursorMoved?()
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
        if item.action == #selector(VimMDTextView.undo(_:)) {
            return session?.canUndo ?? false
        }
        if item.action == #selector(VimMDTextView.redo(_:)) {
            return session?.canRedo ?? false
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

        if session.mode == VIM_MODE_INSERT {
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

        if session?.mode == VIM_MODE_INSERT {
            session?.feedKeys(text)
            synchronizeCaretWithSession()
        }
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

