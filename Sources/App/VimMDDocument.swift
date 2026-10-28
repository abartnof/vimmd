import AppKit
import Engine
import Views
import CBridge

open class SavedChipView: NSView {
    public let label: NSTextField

    public var text: String {
        get { return label.stringValue }
        set { label.stringValue = newValue }
    }

    public var stringValue: String {
        get { return label.stringValue }
        set { label.stringValue = newValue }
    }

    public override init(frame frameRect: NSRect) {
        let lbl = NSTextField(labelWithString: "✓ Saved")
        self.label = lbl
        super.init(frame: frameRect)
        setup()
    }

    required public init?(coder: NSCoder) {
        let lbl = NSTextField(labelWithString: "✓ Saved")
        self.label = lbl
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.wantsLayer = true
        self.layer?.cornerRadius = 8.0
        self.layer?.masksToBounds = true
        self.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.18).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = NSColor.systemGreen
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
    }
}

@objc(VimMDDocument)
open class VimMDDocument: NSDocument {
    public static let wrapLinesPreferenceKey = "VimMDWrapLinesPreference"

    public static func isTabularFormat(url: URL?, fileType: String?) -> Bool {
        if let ext = url?.pathExtension.lowercased(), ext == "csv" || ext == "tsv" {
            return true
        }
        if let type = fileType?.lowercased(),
           type.contains("comma-separated") || type.contains("tab-separated") || type.contains(".csv") || type.contains(".tsv") {
            return true
        }
        return false
    }

    public static func isTSVFormat(url: URL?, fileType: String?) -> Bool {
        if let ext = url?.pathExtension.lowercased(), ext == "tsv" || ext == "tab" {
            return true
        }
        if let type = fileType?.lowercased(),
           type.contains("tab-separated") || type.contains(".tsv") || type.contains("tab") {
            return true
        }
        return false
    }

    public var isTabularDocument: Bool {
        return VimMDDocument.isTabularFormat(url: self.fileURL, fileType: self.fileType)
    }

    public var isTSVDocument: Bool {
        return VimMDDocument.isTSVFormat(url: self.fileURL, fileType: self.fileType)
    }

    public var wrapLines: Bool = true {
        didSet {
            textView?.wrapLines = wrapLines
            (NSApplication.shared.delegate as? AppDelegate)?.updateWrapLinesMenuItemState()
        }
    }

    public func configureWrapLinesPolicy() {
        if isTabularDocument {
            self.wrapLines = false
        } else {
            self.wrapLines = UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey) as? Bool ?? true
        }
    }

    public var session: VimSession?
    public var textView: VimMDTextView?
    public var isClosed: Bool = false
    public var modeLabel: NSTextField?
    public var posLabel: NSTextField?
    public var messageLabel: NSTextField?
    public var savedChipView: SavedChipView?
    public var isSavedChipVisible: Bool {
        guard let chip = savedChipView else { return false }
        return chip.alphaValue > 0.0 && !chip.isHidden
    }
    public var savedChipTimer: Timer?
    public var currentStatusMessage: String?
    public var isCurrentStatusMessageWarning: Bool = false

    public func showSavedChip(duration: TimeInterval = 2.0) {
        guard let chip = self.savedChipView else { return }
        savedChipTimer?.invalidate()
        savedChipTimer = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            chip.animator().alphaValue = 1.0
        }
        chip.alphaValue = 1.0

        if duration > 0 {
            savedChipTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self, weak chip] _ in
                guard let chip = chip else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    chip.animator().alphaValue = 0.0
                }, completionHandler: {
                    chip.alphaValue = 0.0
                })
                chip.alphaValue = 0.0
                self?.savedChipTimer = nil
            }
        }
    }

    public func hideSavedChip(animated: Bool = false) {
        savedChipTimer?.invalidate()
        savedChipTimer = nil
        guard let chip = self.savedChipView else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                chip.animator().alphaValue = 0.0
            }, completionHandler: {
                chip.alphaValue = 0.0
            })
        }
        chip.alphaValue = 0.0
    }

    public func showStatusMessage(_ text: String, isWarning: Bool = false) {
        self.currentStatusMessage = text
        self.isCurrentStatusMessageWarning = isWarning
        guard let label = self.messageLabel else { return }
        label.stringValue = text
        label.textColor = isWarning ? NSColor.systemOrange : NSColor.secondaryLabelColor
    }

    public func updateStatusDisplay() {
        guard let session = session else { return }
        let mode = session.modeString
        let pos = session.cursorPosition
        modeLabel?.stringValue = "-- \(mode) --"
        posLabel?.stringValue = "Ln \(pos.line), Col \(pos.byteCol)"
        if let win = self.windowControllers.first?.window {
            let baseTitle = self.displayName ?? "Untitled"
            win.title = "\(baseTitle) — [\(mode)]"
        }
        if session.mode == VIM_MODE_COMMAND {
            let cmd = session.commandLineBuffer
            messageLabel?.stringValue = cmd
            messageLabel?.textColor = NSColor.labelColor
        } else if let err = session.lastError, !err.isEmpty {
            let warningText = err.hasPrefix("[Warning]") ? err : "[Warning] \(err)"
            showStatusMessage(warningText, isWarning: true)
        } else {
            messageLabel?.stringValue = currentStatusMessage ?? ""
            messageLabel?.textColor = isCurrentStatusMessageWarning ? NSColor.systemOrange : NSColor.secondaryLabelColor
        }
    }

    override public init() {
        let s = VimSession(initialText: "")
        self.session = s
        let chip = SavedChipView(frame: NSRect(x: 0, y: 0, width: 70, height: 16))
        chip.alphaValue = 0.0
        self.savedChipView = chip
        super.init()
        configureWrapLinesPolicy()
        bindSessionSystemAction(s)
    }

    public convenience init(type typeName: String) throws {
        self.init()
        self.fileType = typeName
        configureWrapLinesPolicy()
    }

    public convenience init(contentsOf url: URL, ofType typeName: String) throws {
        self.init()
        self.fileURL = url
        self.fileType = typeName
        configureWrapLinesPolicy()
        let data = try Data(contentsOf: url)
        try self.read(from: data, ofType: typeName)
    }

    private func bindSessionSystemAction(_ s: VimSession) {
        s.onSystemAction = { [weak self] action in
            self?.handleSystemAction(action)
        }
        s.onModeChanged = { [weak self] _ in
            self?.syncDirtyState()
            self?.updateStatusDisplay()
        }
        s.onStatusChanged = { [weak self] in
            self?.syncDirtyState()
            self?.updateStatusDisplay()
        }
        s.onLineDeltaWithRange = { [weak self] _, _, _, _ in
            self?.syncDirtyState()
        }
    }

    public func syncDirtyState() {
        guard let s = session else { return }
        if s.isDirty {
            if !super.isDocumentEdited {
                self.updateChangeCount(.changeDone)
            }
        } else {
            if super.isDocumentEdited {
                self.updateChangeCount(.changeCleared)
            }
        }
    }

    override open class var autosavesInPlace: Bool {
        return false
    }

    override open var isDocumentEdited: Bool {
        return session?.isDirty ?? false
    }

    override open func data(ofType typeName: String) throws -> Data {
        guard let session = session else {
            return Data()
        }
        let content = session.serializeBuffer()
        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "VimMDDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode document buffer as UTF-8"])
        }
        return data
    }

    override open func read(from data: Data, ofType typeName: String) throws {
        self.fileType = typeName
        configureWrapLinesPolicy()
        let string = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let newSession = VimSession(initialText: string)
        self.session = newSession
        bindSessionSystemAction(newSession)
        if let tv = self.textView {
            tv.session = newSession
            tv.isTabularDocument = self.isTabularDocument
            tv.isTSV = self.isTSVDocument
            tv.wrapLines = self.wrapLines
            tv.updateFrameHeightToFitText()
        }
        self.updateChangeCount(.changeCleared)
    }

    override open func read(from url: URL, ofType typeName: String) throws {
        self.fileURL = url
        self.fileType = typeName
        configureWrapLinesPolicy()
        self.textView?.isTabularDocument = self.isTabularDocument
        self.textView?.isTSV = self.isTSVDocument
        try super.read(from: url, ofType: typeName)
        self.updateChangeCount(.changeCleared)
    }

    override open func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        self.fileURL = url
        self.fileType = typeName
        self.textView?.isTabularDocument = self.isTabularDocument
        self.textView?.isTSV = self.isTSVDocument
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
        session?.clearDirty()
        self.updateChangeCount(.changeCleared)
        showSavedChip()
    }

    @IBAction override open func save(_ sender: Any?) {
        super.save(sender)
        showSavedChip()
    }

    override open func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let dirty = self.isDocumentEdited || (self.session?.isDirty ?? false)
        if dirty && !super.isDocumentEdited {
            self.updateChangeCount(.changeDone)
        } else if !dirty && super.isDocumentEdited {
            self.updateChangeCount(.changeCleared)
        }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    override open func shouldCloseWindowController(_ windowController: NSWindowController, delegate: Any?, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        let dirty = self.isDocumentEdited || (self.session?.isDirty ?? false)
        if dirty && !super.isDocumentEdited {
            self.updateChangeCount(.changeDone)
        } else if !dirty && super.isDocumentEdited {
            self.updateChangeCount(.changeCleared)
        }
        super.shouldCloseWindowController(windowController, delegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    override open func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let baseTitle = self.displayName ?? "Untitled"
        window.title = "\(baseTitle) — [NORMAL]"

        let contentBounds = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let statusHeight: CGFloat = 22.0

        // 1. Scroll view
        let scrollFrame = NSRect(x: 0, y: statusHeight, width: contentBounds.width, height: max(0, contentBounds.height - statusHeight))
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !self.wrapLines
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.5
        scrollView.maxMagnification = 3.0

        let contentSize = scrollView.contentSize
        let tv = VimMDTextView(frame: NSRect(origin: .zero, size: contentSize))
        tv.minSize = NSSize(width: 0.0, height: contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = !self.wrapLines
        tv.autoresizingMask = self.wrapLines ? [.width] : []
        tv.textContainer?.containerSize = NSSize(width: self.wrapLines ? contentSize.width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = self.wrapLines

        if self.session == nil {
            let s = VimSession(initialText: "")
            self.session = s
            bindSessionSystemAction(s)
        }
        tv.isTabularDocument = self.isTabularDocument
        tv.isTSV = self.isTSVDocument
        tv.session = self.session
        tv.onQuitRequested = { [weak self] in
            self?.handleQuitTrigger()
        }
        tv.onCursorMoved = { [weak self] in
            self?.updateStatusDisplay()
        }
        tv.onModeChanged = { [weak self] _ in
            self?.updateStatusDisplay()
        }
        self.session?.onModeChanged = { [weak self] _ in
            self?.updateStatusDisplay()
        }

        scrollView.documentView = tv
        tv.wrapLines = self.wrapLines
        tv.onToggleWrapLines = { [weak self] in
            self?.toggleWrapLines(nil)
        }
        tv.updateFrameHeightToFitText()

        // Configure LineNumberRulerView gutter
        let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        ruler.clientView = tv
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        ruler.updateThickness(for: tv)

        // 2. Status bar at bottom
        let statusFrame = NSRect(x: 0, y: 0, width: contentBounds.width, height: statusHeight)
        let statusBar = NSView(frame: statusFrame)
        statusBar.autoresizingMask = [.width, .maxYMargin]

        let modeLbl = NSTextField(frame: NSRect(x: 8, y: 3, width: 140, height: 16))
        modeLbl.isEditable = false
        modeLbl.isBordered = false
        modeLbl.backgroundColor = .clear
        modeLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        modeLbl.textColor = NSColor.secondaryLabelColor
        modeLbl.stringValue = "-- NORMAL --"
        statusBar.addSubview(modeLbl)
        self.modeLabel = modeLbl

        let chipWidth: CGFloat = 70.0
        let chipHeight: CGFloat = 16.0
        let posWidth: CGFloat = 110.0
        let posRightMargin: CGFloat = 8.0

        let chipX = max(160, contentBounds.width - posRightMargin - posWidth - chipWidth - 10)
        let chip = self.savedChipView ?? SavedChipView(frame: NSRect(x: chipX, y: 3, width: chipWidth, height: chipHeight))
        chip.frame = NSRect(x: chipX, y: 3, width: chipWidth, height: chipHeight)
        chip.autoresizingMask = [.minXMargin]
        statusBar.addSubview(chip)
        self.savedChipView = chip

        let posLbl = NSTextField(frame: NSRect(x: contentBounds.width - posRightMargin - posWidth, y: 3, width: posWidth, height: 16))
        posLbl.autoresizingMask = [.minXMargin]
        posLbl.isEditable = false
        posLbl.isBordered = false
        posLbl.backgroundColor = .clear
        posLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        posLbl.textColor = NSColor.secondaryLabelColor
        posLbl.alignment = .right
        posLbl.stringValue = "Ln 1, Col 1"
        statusBar.addSubview(posLbl)
        self.posLabel = posLbl

        let msgWidth = max(60, chipX - 165)
        let msgLbl = NSTextField(frame: NSRect(x: 155, y: 3, width: msgWidth, height: 16))
        msgLbl.autoresizingMask = [.width]
        msgLbl.isEditable = false
        msgLbl.isBordered = false
        msgLbl.backgroundColor = .clear
        msgLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        msgLbl.textColor = isCurrentStatusMessageWarning ? NSColor.systemOrange : NSColor.secondaryLabelColor
        msgLbl.stringValue = currentStatusMessage ?? ""
        statusBar.addSubview(msgLbl)
        self.messageLabel = msgLbl

        let containerView = NSView(frame: contentBounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.addSubview(scrollView)
        containerView.addSubview(statusBar)
        window.contentView = containerView

        self.textView = tv

        window.isReleasedWhenClosed = false
        (NSApplication.shared.delegate as? AppDelegate)?.hasOpenedDocument = true

        window.initialFirstResponder = tv
        window.makeFirstResponder(tv)

        let windowController = NSWindowController(window: window)
        self.addWindowController(windowController)

        updateStatusDisplay()
    }

    override open func close() {
        guard !self.isClosed else { return }
        self.isClosed = true
        super.close()
    }

    public func handleSystemAction(_ action: VimSystemAction) {
        guard let session = session else { return }
        defer { session.clearPendingAction() }
        switch action {
        case VIM_ACTION_SAVE, VIM_ACTION_SAVE_FORCE:
            if let url = self.fileURL {
                do {
                    try self.write(to: url, ofType: self.fileType ?? "public.plain-text", for: .saveOperation, originalContentsURL: url)
                    self.updateChangeCount(.changeCleared)
                    session.clearDirty()
                    showSavedChip()
                    let lineCount = session.lineIndexTable.lineCount
                    let content = session.serializeBuffer()
                    let byteCount = content.utf8.count
                    let filename = url.lastPathComponent
                    showStatusMessage("\"\(filename)\" \(lineCount)L, \(byteCount)B written", isWarning: false)
                } catch {
                    NSLog("Failed to save document: %@", error.localizedDescription)
                    showStatusMessage("[Warning] E212: Cannot open file for writing: \(error.localizedDescription)", isWarning: true)
                }
            } else {
                showStatusMessage("[Warning] E32: No file name", isWarning: true)
                if NSApplication.shared.mainWindow != nil && NSApplication.shared.isRunning {
                    self.save(self)
                }
            }

        case VIM_ACTION_SAVE_ALL:
            NSDocumentController.shared.saveAllDocuments(self)

        case VIM_ACTION_SAVE_AND_QUIT:
            if let url = self.fileURL {
                do {
                    try self.write(to: url, ofType: self.fileType ?? "public.plain-text", for: .saveOperation, originalContentsURL: url)
                    self.updateChangeCount(.changeCleared)
                    session.clearDirty()
                    showSavedChip()
                    let lineCount = session.lineIndexTable.lineCount
                    let content = session.serializeBuffer()
                    let byteCount = content.utf8.count
                    let filename = url.lastPathComponent
                    showStatusMessage("\"\(filename)\" \(lineCount)L, \(byteCount)B written", isWarning: false)
                    self.close()
                } catch {
                    NSLog("Failed to save document: %@", error.localizedDescription)
                    showStatusMessage("[Warning] E212: Cannot open file for writing: \(error.localizedDescription)", isWarning: true)
                }
            } else {
                showStatusMessage("[Warning] E32: No file name", isWarning: true)
                if NSApplication.shared.mainWindow != nil && NSApplication.shared.isRunning {
                    self.save(self)
                }
            }

        case VIM_ACTION_QUIT:
            if session.isDirty || self.isDocumentEdited {
                showStatusMessage("[Warning] E37: No write since last change (add ! to override)", isWarning: true)
            } else {
                self.close()
            }

        case VIM_ACTION_QUIT_FORCE:
            self.close()

        case VIM_ACTION_QUIT_ALL:
            let allDocs = NSDocumentController.shared.documents
            let anyDirty = allDocs.contains { ($0 as? VimMDDocument)?.isDocumentEdited == true || (($0 as? VimMDDocument)?.session?.isDirty ?? false) }
            if anyDirty || session.isDirty || self.isDocumentEdited {
                showStatusMessage("[Warning] E37: No write since last change (add ! to override)", isWarning: true)
            } else {
                NSApplication.shared.terminate(nil)
            }

        case VIM_ACTION_QUIT_ALL_FORCE:
            NSApplication.shared.terminate(nil)

        case VIM_ACTION_RELOAD_FORCE:
            if let url = self.fileURL {
                do {
                    let data = try Data(contentsOf: url)
                    try self.read(from: data, ofType: self.fileType ?? "public.plain-text")
                    self.textView?.session = self.session
                    self.updateChangeCount(.changeCleared)
                } catch {
                    NSLog("Failed to reload document: %@", error.localizedDescription)
                }
            } else {
                self.session?.clearDirty()
                self.updateChangeCount(.changeCleared)
            }

        default:
            break
        }
    }

    public func handleQuitTrigger() {
        guard !self.isClosed else { return }
        guard let session = session else { return }
        let action = session.pendingAction
        if action != VIM_ACTION_NONE {
            handleSystemAction(action)
        } else if session.shouldQuit {
            if session.isDirty || self.isDocumentEdited {
                showStatusMessage("[Warning] E37: No write since last change (add ! to override)", isWarning: true)
            } else {
                self.close()
            }
        }
        if let err = session.lastError, !err.isEmpty {
            let warningText = err.hasPrefix("[Warning]") ? err : "[Warning] \(err)"
            showStatusMessage(warningText, isWarning: true)
        }
    }

    @IBAction open func toggleWrapLines(_ sender: Any?) {
        self.wrapLines = !self.wrapLines
        if !isTabularDocument {
            UserDefaults.standard.set(self.wrapLines, forKey: VimMDDocument.wrapLinesPreferenceKey)
        }
        (NSApplication.shared.delegate as? AppDelegate)?.updateWrapLinesMenuItemState()
    }

    override open func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWrapLines(_:)) {
            menuItem.state = self.wrapLines ? .on : .off
            return true
        }
        return super.validateMenuItem(menuItem)
    }
}
