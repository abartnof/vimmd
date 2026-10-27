import AppKit
import Engine
import Views

@objc(VimMDDocument)
open class VimMDDocument: NSDocument {
    public var session: VimSession?
    public var textView: VimMDTextView?
    public var isClosed: Bool = false

    override public init() {
        self.session = VimSession(initialText: "")
        super.init()
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
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "VimMDDocument", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode input data as UTF-8"])
        }
        let newSession = VimSession(initialText: string)
        self.session = newSession
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
        window.title = self.displayName ?? "Untitled"

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 800, height: 600))
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
            self.session = VimSession(initialText: "")
        }
        tv.session = self.session
        tv.onQuitRequested = { [weak self] in
            self?.handleQuitTrigger()
        }

        scrollView.documentView = tv
        window.contentView = scrollView

        self.textView = tv

        let windowController = NSWindowController(window: window)
        self.addWindowController(windowController)
    }

    override open func close() {
        self.isClosed = true
        super.close()
    }

    public func handleQuitTrigger() {
        guard let session = session, session.shouldQuit else { return }
        if !session.isDirty && self.fileURL != nil {
            self.save(self)
        }
        self.close()
    }
}
