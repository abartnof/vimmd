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

    public var currentSelectedRange: NSRange = NSRange(location: 0, length: 0)
    public var activeMarkedRange: NSRange = NSRange(location: NSNotFound, length: 0)

    private func bindSession() {
        guard let session = session else { return }
        self.string = session.serializeBuffer()
        session.onLineDeltaWithRange = { [weak self] startLine, deletedCount, newLines, targetRange in
            self?.applyDelta(targetRange: targetRange, newLines: newLines)
        }
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

        synchronizeCaretWithSession()
    }

    public func applyDelta(startLine: Int, deletedCount: Int, newLines: [String]) {
        guard let session = session else { return }
        let targetRange = session.lineIndexTable.characterRange(startLine: startLine, count: deletedCount)
        applyDelta(targetRange: targetRange, newLines: newLines)
    }

    public func synchronizeCaretWithSession() {
        guard let session = session else { return }
        let offset = session.cursorUtf16Offset
        let docLength = (self.string as NSString).length
        let clamped = max(0, min(docLength, offset))
        self.currentSelectedRange = NSRange(location: clamped, length: 0)
        self.setSelectedRange(self.currentSelectedRange)
    }

    override open func keyDown(with event: NSEvent) {
        guard let session = session else {
            super.keyDown(with: event)
            return
        }

        if session.mode == VIM_MODE_NORMAL || session.mode == VIM_MODE_VISUAL {
            if let chars = event.characters {
                session.feedKeys(chars)
                synchronizeCaretWithSession()
                if session.shouldQuit {
                    onQuitRequested?()
                }
            }
            return
        }

        // Insert mode
        if event.keyCode == 53 || event.characters == "\u{1b}" {
            session.feedKeys("\u{1b}")
            unmarkText()
            synchronizeCaretWithSession()
            return
        }

        // In insert mode, pass through input context or feed directly
        if let inputContext = self.inputContext {
            inputContext.handleEvent(event)
        } else if let chars = event.characters {
            insertText(chars, replacementRange: self.selectedRange())
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
