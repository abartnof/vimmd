import AppKit
import Engine
import Views
import CBridge

open class SavedChipView: NSView {
    public var imageView: NSImageView?
    public let label: NSTextField
    public var symbolImage: NSImage?
    public let stackView: NSStackView

    public var text: String {
        get { return label.stringValue }
        set { label.stringValue = newValue }
    }

    public var stringValue: String {
        get { return label.stringValue }
        set { label.stringValue = newValue }
    }

    public override init(frame frameRect: NSRect) {
        self.label = NSTextField(labelWithString: "Saved")
        self.stackView = NSStackView()
        super.init(frame: frameRect)
        setup()
    }

    required public init?(coder: NSCoder) {
        self.label = NSTextField(labelWithString: "Saved")
        self.stackView = NSStackView()
        super.init(coder: coder)
        setup()
    }

    open override var wantsUpdateLayer: Bool {
        return true
    }

    open override func updateLayer() {
        super.updateLayer()
        updatePillColors()
    }

    open override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePillColors()
    }

    public func updatePillColors() {
        self.layer?.cornerRadius = 9.0
        self.layer?.borderWidth = 0.5
        self.layer?.masksToBounds = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.16).cgColor
            self.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.35).cgColor
        }
    }

    private func setup() {
        self.wantsLayer = true
        updatePillColors()

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = NSColor.systemGreen
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false

        if #available(macOS 11.0, *), let baseImg = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            let symbol = baseImg.withSymbolConfiguration(config) ?? baseImg
            self.symbolImage = symbol
            let iv = NSImageView(image: symbol)
            iv.contentTintColor = NSColor.systemGreen
            iv.translatesAutoresizingMaskIntoConstraints = false
            self.imageView = iv
            self.label.stringValue = "Saved"
        } else {
            self.symbolImage = nil
            self.imageView = nil
            self.label.stringValue = "✓ Saved"
        }

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if let iv = self.imageView {
            stackView.addArrangedSubview(iv)
        }
        stackView.addArrangedSubview(label)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
    }
}

@objc(VimMDDocument)
open class VimMDDocument: NSDocument {
    public static let wrapLinesPreferenceKey = "VimMDWrapLinesPreference"

    public static func syntaxType(for url: URL?, fileType: String?) -> VimMDTextView.DocumentSyntaxType {
        let ext = url?.pathExtension.lowercased()
        let type = fileType?.lowercased()

        if ext == "md" || ext == "markdown" || type == "net.daringfireball.markdown" || (type?.contains("markdown") ?? false) {
            return .markdown
        }
        if ext == "tsv" || ext == "tab" || type == "public.tab-separated-values-text" || (type?.contains("tab-separated") ?? false) || (type?.contains(".tsv") ?? false) {
            return .tsv
        }
        if ext == "csv" || type == "public.comma-separated-values-text" || (type?.contains("comma-separated") ?? false) || (type?.contains(".csv") ?? false) {
            return .csv
        }
        return .plainText
    }

    public var documentSyntaxType: VimMDTextView.DocumentSyntaxType {
        return VimMDDocument.syntaxType(for: self.fileURL, fileType: self.fileType)
    }

    public static func isTabularFormat(url: URL?, fileType: String?) -> Bool {
        let st = syntaxType(for: url, fileType: fileType)
        return st == .csv || st == .tsv
    }

    public static func isTSVFormat(url: URL?, fileType: String?) -> Bool {
        return syntaxType(for: url, fileType: fileType) == .tsv
    }

    public var isTabularDocument: Bool {
        return documentSyntaxType == .csv || documentSyntaxType == .tsv
    }

    public var isTSVDocument: Bool {
        return documentSyntaxType == .tsv
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
            context.duration = 0.2
            chip.animator().alphaValue = 1.0
        }
        chip.alphaValue = 1.0

        if let layer = chip.layer {
            let scaleAnim = CABasicAnimation(keyPath: "transform")
            let midX = chip.bounds.midX
            let midY = chip.bounds.midY
            var startT = CATransform3DMakeTranslation(midX, midY, 0)
            startT = CATransform3DScale(startT, 0.90, 0.90, 1.0)
            startT = CATransform3DTranslate(startT, -midX, -midY, 0)
            scaleAnim.fromValue = NSValue(caTransform3D: startT)
            scaleAnim.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            scaleAnim.duration = 0.18
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(scaleAnim, forKey: "savedChipScale")
        }

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

    public var previousMode: VimEngineMode = VIM_MODE_NORMAL

    public func updateStatusDisplay() {
        guard let session = session else { return }
        let currentMode = session.mode
        let mode = session.modeString
        let pos = session.cursorPosition
        posLabel?.stringValue = "Ln \(pos.line), Col \(pos.byteCol)"
        if let win = self.windowControllers.first?.window {
            let baseTitle = self.displayName ?? "Untitled"
            win.title = "\(baseTitle) — [\(mode)]"
        }

        let rightBound = savedChipView?.frame.origin.x ?? (posLabel?.frame.origin.x ?? 300)

        if currentMode == VIM_MODE_COMMAND {
            modeLabel?.isHidden = true
            modeLabel?.stringValue = ""

            let promptWidth = max(60, rightBound - 16)
            messageLabel?.frame = NSRect(x: 8, y: 3, width: promptWidth, height: 16)
            messageLabel?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
            messageLabel?.textColor = NSColor.labelColor
            let cmd = session.commandLineBuffer
            messageLabel?.stringValue = cmd
        } else {
            modeLabel?.isHidden = false
            modeLabel?.stringValue = "-- \(mode) --"

            let normalMsgWidth = max(60, rightBound - 165)
            messageLabel?.frame = NSRect(x: 155, y: 3, width: normalMsgWidth, height: 16)
            messageLabel?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)

            if let err = session.lastError, !err.isEmpty {
                let warningText = err.hasPrefix("[Warning]") ? err : "[Warning] \(err)"
                showStatusMessage(warningText, isWarning: true)
            } else {
                if previousMode == VIM_MODE_COMMAND && currentMode == VIM_MODE_NORMAL {
                    if let pattern = session.lastSearchPattern, !pattern.isEmpty {
                        currentStatusMessage = "/\(pattern)"
                        isCurrentStatusMessageWarning = false
                    }
                }
                messageLabel?.stringValue = currentStatusMessage ?? ""
                messageLabel?.textColor = isCurrentStatusMessageWarning ? NSColor.systemOrange : NSColor.secondaryLabelColor
            }
        }
        previousMode = currentMode
    }

    override public init() {
        let s = VimSession(initialText: "")
        self.session = s
        let chip = SavedChipView(frame: NSRect(x: 0, y: 0, width: 78, height: 18))
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
            tv.documentSyntaxType = self.documentSyntaxType
            tv.wrapLines = self.wrapLines
            tv.updateFrameHeightToFitText()
        }
        self.updateChangeCount(.changeCleared)
    }

    override open func read(from url: URL, ofType typeName: String) throws {
        self.fileURL = url
        self.fileType = typeName
        configureWrapLinesPolicy()
        self.textView?.documentSyntaxType = self.documentSyntaxType
        try super.read(from: url, ofType: typeName)
        self.updateChangeCount(.changeCleared)
    }

    override open func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        self.fileURL = url
        self.fileType = typeName
        self.textView?.documentSyntaxType = self.documentSyntaxType
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
        tv.documentSyntaxType = self.documentSyntaxType
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
        tv.onStatusChanged = { [weak self] in
            self?.updateStatusDisplay()
        }
        tv.onSearchNavigated = { [weak self] msg in
            self?.showStatusMessage(msg, isWarning: false)
        }
        tv.onCommandCancelled = { [weak self] in
            self?.currentStatusMessage = ""
            self?.isCurrentStatusMessageWarning = false
            self?.updateStatusDisplay()
        }
        self.session?.onModeChanged = { [weak self] _ in
            self?.syncDirtyState()
            self?.updateStatusDisplay()
        }
        self.session?.onStatusChanged = { [weak self] in
            self?.syncDirtyState()
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

        let chipWidth: CGFloat = 78.0
        let chipHeight: CGFloat = 18.0
        let posWidth: CGFloat = 110.0
        let posRightMargin: CGFloat = 8.0

        let chipX = max(160, contentBounds.width - posRightMargin - posWidth - chipWidth - 10)
        let chip = self.savedChipView ?? SavedChipView(frame: NSRect(x: chipX, y: 2, width: chipWidth, height: chipHeight))
        chip.frame = NSRect(x: chipX, y: 2, width: chipWidth, height: chipHeight)
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
