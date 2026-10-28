import AppKit
import Engine
import Views
import CBridge

@objc(VimMDDocument)
open class VimMDDocument: NSDocument {
    public var session: VimSession?
    public var textView: VimMDTextView?
    public var isClosed: Bool = false
    public var modeLabel: NSTextField?
    public var posLabel: NSTextField?

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
    }

    override public init() {
        let s = VimSession(initialText: "")
        self.session = s
        super.init()
        bindSessionSystemAction(s)
    }

    public convenience init(type typeName: String) throws {
        self.init()
        self.fileType = typeName
    }

    public convenience init(contentsOf url: URL, ofType typeName: String) throws {
        self.init()
        self.fileURL = url
        self.fileType = typeName
        let data = try Data(contentsOf: url)
        try self.read(from: data, ofType: typeName)
    }

    private func bindSessionSystemAction(_ s: VimSession) {
        s.onSystemAction = { [weak self] action in
            self?.handleSystemAction(action)
        }
        s.onModeChanged = { [weak self] _ in
            self?.updateStatusDisplay()
        }
    }

    override open class var autosavesInPlace: Bool {
        return true
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
        let string = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let newSession = VimSession(initialText: string)
        self.session = newSession
        bindSessionSystemAction(newSession)
        if let tv = self.textView {
            tv.session = newSession
        }
    }

    override open func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
        session?.clearDirty()
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
        scrollView.hasHorizontalScroller = false

        let contentSize = scrollView.contentSize
        let tv = VimMDTextView(frame: NSRect(origin: .zero, size: contentSize))
        tv.minSize = NSSize(width: 0.0, height: contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true

        if self.session == nil {
            let s = VimSession(initialText: "")
            self.session = s
            bindSessionSystemAction(s)
        }
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

        // 2. Status bar at bottom
        let statusFrame = NSRect(x: 0, y: 0, width: contentBounds.width, height: statusHeight)
        let statusBar = NSView(frame: statusFrame)
        statusBar.autoresizingMask = [.width, .maxYMargin]

        let modeLbl = NSTextField(frame: NSRect(x: 8, y: 3, width: 200, height: 16))
        modeLbl.isEditable = false
        modeLbl.isBordered = false
        modeLbl.backgroundColor = .clear
        modeLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        modeLbl.textColor = NSColor.secondaryLabelColor
        modeLbl.stringValue = "-- NORMAL --"
        statusBar.addSubview(modeLbl)
        self.modeLabel = modeLbl

        let posLbl = NSTextField(frame: NSRect(x: max(208, contentBounds.width - 208), y: 3, width: 200, height: 16))
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
                } catch {
                    NSLog("Failed to save document: %@", error.localizedDescription)
                }
            } else if NSApplication.shared.mainWindow != nil && NSApplication.shared.isRunning {
                self.save(self)
            }

        case VIM_ACTION_SAVE_ALL:
            NSDocumentController.shared.saveAllDocuments(self)

        case VIM_ACTION_SAVE_AND_QUIT:
            if let url = self.fileURL {
                do {
                    try self.write(to: url, ofType: self.fileType ?? "public.plain-text", for: .saveOperation, originalContentsURL: url)
                    self.updateChangeCount(.changeCleared)
                    session.clearDirty()
                } catch {
                    NSLog("Failed to save document: %@", error.localizedDescription)
                }
            } else if NSApplication.shared.mainWindow != nil && NSApplication.shared.isRunning {
                self.save(self)
            }
            self.close()

        case VIM_ACTION_QUIT:
            if !session.isDirty {
                self.close()
            }

        case VIM_ACTION_QUIT_FORCE:
            self.close()

        case VIM_ACTION_QUIT_ALL:
            let allDocs = NSDocumentController.shared.documents
            let anyDirty = allDocs.contains { ($0 as? VimMDDocument)?.isDocumentEdited == true }
            if !anyDirty {
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
            if !session.isDirty {
                self.close()
            }
        }
    }
}
