import AppKit

public enum AppearanceMode: String, CaseIterable {
    case matchSystem = "Match System"
    case light = "Light"
    case dark = "Dark"
}

open class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    public static let appearancePreferenceKey = "VimMDAppearancePreference"
    public static let wrapLinesPreferenceKey = "VimMDWrapLinesPreference"

    public var hasOpenedDocument: Bool = false
    public var hasLaunchedWithTargetFile: Bool = false
    public var openDocumentInvokedCount: Int = 0

    public var matchSystemMenuItem: NSMenuItem?
    public var lightMenuItem: NSMenuItem?
    public var darkMenuItem: NSMenuItem?
    public var wrapLinesMenuItem: NSMenuItem?
    public var zoomInMenuItem: NSMenuItem?
    public var zoomOutMenuItem: NSMenuItem?
    public var actualSizeMenuItem: NSMenuItem?
    public var viewMenuItem: NSMenuItem?

    public var currentAppearanceMode: AppearanceMode {
        get {
            guard let stored = UserDefaults.standard.string(forKey: AppDelegate.appearancePreferenceKey) else {
                return .matchSystem
            }
            switch stored.lowercased() {
            case "light", "aqua":
                return .light
            case "dark", "darkaqua":
                return .dark
            default:
                return .matchSystem
            }
        }
        set {
            setAppearance(mode: newValue)
        }
    }

    public func setAppearance(mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: AppDelegate.appearancePreferenceKey)
        applyAppearanceMode(mode)
    }

    public func applyAppearanceMode(_ mode: AppearanceMode) {
        switch mode {
        case .matchSystem:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        updateAppearanceMenuCheckmarks(mode: mode)
    }

    public func updateAppearanceMenuCheckmarks(mode: AppearanceMode) {
        matchSystemMenuItem?.state = (mode == .matchSystem) ? .on : .off
        lightMenuItem?.state = (mode == .light) ? .on : .off
        darkMenuItem?.state = (mode == .dark) ? .on : .off
    }

    public func updateWrapLinesMenuItemState() {
        guard let item = wrapLinesMenuItem else { return }
        if let doc = NSDocumentController.shared.currentDocument as? VimMDDocument {
            item.state = doc.wrapLines ? .on : .off
        } else {
            let pref = UserDefaults.standard.object(forKey: AppDelegate.wrapLinesPreferenceKey) as? Bool ?? true
            item.state = pref ? .on : .off
        }
    }

    @IBAction public func setAppearanceMatchSystem(_ sender: Any?) {
        setAppearance(mode: .matchSystem)
    }

    @IBAction public func setAppearanceLight(_ sender: Any?) {
        setAppearance(mode: .light)
    }

    @IBAction public func setAppearanceDark(_ sender: Any?) {
        setAppearance(mode: .dark)
    }

    @IBAction public func toggleWrapLines(_ sender: Any?) {
        if let doc = NSDocumentController.shared.currentDocument as? VimMDDocument {
            doc.toggleWrapLines(sender)
        } else {
            let currentPref = UserDefaults.standard.object(forKey: AppDelegate.wrapLinesPreferenceKey) as? Bool ?? true
            let newPref = !currentPref
            UserDefaults.standard.set(newPref, forKey: AppDelegate.wrapLinesPreferenceKey)
            updateWrapLinesMenuItemState()
        }
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem == wrapLinesMenuItem || menuItem.action == #selector(toggleWrapLines(_:)) {
            updateWrapLinesMenuItemState()
            return true
        }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return hasOpenedDocument && NSDocumentController.shared.documents.isEmpty
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        return false
    }

    public func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        presentOpenDocument()
        return true
    }

    open func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        hasOpenedDocument = true
        hasLaunchedWithTargetFile = true
        let fileURL = URL(fileURLWithPath: filename)
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
        return true
    }

    open func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            _ = self.application(sender, openFile: filename)
        }
    }

    open func presentOpenDocument() {
        openDocumentInvokedCount += 1
        NSDocumentController.shared.openDocument(nil)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        for arg in CommandLine.arguments.dropFirst() {
            if !arg.hasPrefix("-") {
                hasLaunchedWithTargetFile = true
                break
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.hasLaunchedWithTargetFile && NSDocumentController.shared.documents.isEmpty {
                self.presentOpenDocument()
            }
        }
    }

    public func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let hideItem = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let appearanceMenuItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "Appearance")

        let matchSystemItem = NSMenuItem(title: "Match System", action: #selector(setAppearanceMatchSystem(_:)), keyEquivalent: "")
        matchSystemItem.target = self
        appearanceMenu.addItem(matchSystemItem)
        self.matchSystemMenuItem = matchSystemItem

        let lightItem = NSMenuItem(title: "Light", action: #selector(setAppearanceLight(_:)), keyEquivalent: "")
        lightItem.target = self
        appearanceMenu.addItem(lightItem)
        self.lightMenuItem = lightItem

        let darkItem = NSMenuItem(title: "Dark", action: #selector(setAppearanceDark(_:)), keyEquivalent: "")
        darkItem.target = self
        appearanceMenu.addItem(darkItem)
        self.darkMenuItem = darkItem

        appearanceMenuItem.submenu = appearanceMenu
        viewMenu.addItem(appearanceMenuItem)

        viewMenu.addItem(NSMenuItem.separator())

        let wrapLinesItem = NSMenuItem(title: "Wrap Lines", action: #selector(toggleWrapLines(_:)), keyEquivalent: "w")
        wrapLinesItem.keyEquivalentModifierMask = [.command, .option]
        wrapLinesItem.target = nil
        viewMenu.addItem(wrapLinesItem)
        self.wrapLinesMenuItem = wrapLinesItem

        viewMenu.addItem(NSMenuItem.separator())

        let zoomInItem = NSMenuItem(title: "Zoom In", action: Selector(("zoomIn:")), keyEquivalent: "+")
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.target = nil
        viewMenu.addItem(zoomInItem)
        self.zoomInMenuItem = zoomInItem

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: Selector(("zoomOut:")), keyEquivalent: "-")
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.target = nil
        viewMenu.addItem(zoomOutItem)
        self.zoomOutMenuItem = zoomOutItem

        let actualSizeItem = NSMenuItem(title: "Actual Size", action: Selector(("actualSize:")), keyEquivalent: "0")
        actualSizeItem.keyEquivalentModifierMask = [.command]
        actualSizeItem.target = nil
        viewMenu.addItem(actualSizeItem)
        self.actualSizeMenuItem = actualSizeItem

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)
        self.viewMenuItem = viewMenuItem

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 6. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "\(appName) Help", action: #selector(NSApplication.showHelp(_:)), keyEquivalent: "?")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.helpMenu = helpMenu

        applyAppearanceMode(currentAppearanceMode)
        updateWrapLinesMenuItemState()
    }
}
