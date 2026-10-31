import Foundation
import AppKit
import App
import Engine
import Views

func runTest(name: String, test: () throws -> Void) -> Bool {
    print("[RUN ] \(name)")
    do {
        try test()
        print("[PASS] \(name)")
        return true
    } catch {
        print("[FAIL] \(name): \(error)")
        return false
    }
}

func testViewMenuHierarchyAndPositioning() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let mainMenu = NSApplication.shared.mainMenu else {
        throw NSError(domain: "ViewMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "mainMenu is nil"])
    }

    // Expected order: [VimMD] [File] [Edit] [View] [Window] [Help]
    guard mainMenu.items.count >= 6 else {
        throw NSError(domain: "ViewMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected at least 6 menu items, got \(mainMenu.items.count)"])
    }

    let fileMenuTitle = mainMenu.items[1].submenu?.title
    let editMenuTitle = mainMenu.items[2].submenu?.title
    let viewMenuTitle = mainMenu.items[3].submenu?.title
    let windowMenuTitle = mainMenu.items[4].submenu?.title
    let helpMenuTitle = mainMenu.items[5].submenu?.title

    guard fileMenuTitle == "File" else {
        throw NSError(domain: "ViewMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Item 1 is not File: \(String(describing: fileMenuTitle))"])
    }
    guard editMenuTitle == "Edit" else {
        throw NSError(domain: "ViewMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Item 2 is not Edit: \(String(describing: editMenuTitle))"])
    }
    guard viewMenuTitle == "View" else {
        throw NSError(domain: "ViewMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Item 3 is not View: \(String(describing: viewMenuTitle))"])
    }
    guard windowMenuTitle == "Window" else {
        throw NSError(domain: "ViewMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Item 4 is not Window: \(String(describing: windowMenuTitle))"])
    }
    guard helpMenuTitle == "Help" else {
        throw NSError(domain: "ViewMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Item 5 is not Help: \(String(describing: helpMenuTitle))"])
    }
}

func testAppearanceSubmenuAndModeSwitching() throws {
    // Clear any previous preference
    UserDefaults.standard.removeObject(forKey: AppDelegate.appearancePreferenceKey)

    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let mainMenu = NSApplication.shared.mainMenu,
          mainMenu.items.count > 3,
          let viewMenu = mainMenu.items[3].submenu else {
        throw NSError(domain: "ViewMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "View menu missing"])
    }

    guard let appearanceItem = viewMenu.items.first(where: { $0.title == "Appearance" }),
          let appearanceSubmenu = appearanceItem.submenu else {
        throw NSError(domain: "ViewMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Appearance submenu missing from View menu"])
    }

    guard let matchSystemItem = appearanceSubmenu.items.first(where: { $0.title == "Match System" }),
          let lightItem = appearanceSubmenu.items.first(where: { $0.title == "Light" }),
          let darkItem = appearanceSubmenu.items.first(where: { $0.title == "Dark" }) else {
        throw NSError(domain: "ViewMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected Match System, Light, and Dark items in Appearance submenu"])
    }

    // Default should be Match System (nil appearance)
    guard NSApp.appearance == nil else {
        throw NSError(domain: "ViewMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected NSApp.appearance == nil by default"])
    }
    guard matchSystemItem.state == .on && lightItem.state == .off && darkItem.state == .off else {
        throw NSError(domain: "ViewMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected Match System checkmark .on, others .off"])
    }

    // Switch to Light
    appDelegate.setAppearanceLight(nil)
    guard NSApp.appearance?.name == .aqua else {
        throw NSError(domain: "ViewMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected NSApp.appearance == .aqua, got \(String(describing: NSApp.appearance?.name))"])
    }
    guard matchSystemItem.state == .off && lightItem.state == .on && darkItem.state == .off else {
        throw NSError(domain: "ViewMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected Light checkmark .on, others .off"])
    }
    guard UserDefaults.standard.string(forKey: AppDelegate.appearancePreferenceKey)?.lowercased() == "light" else {
        throw NSError(domain: "ViewMenuTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected preference 'light' persisted, got \(String(describing: UserDefaults.standard.string(forKey: AppDelegate.appearancePreferenceKey)))"])
    }

    // Switch to Dark
    appDelegate.setAppearanceDark(nil)
    guard NSApp.appearance?.name == .darkAqua else {
        throw NSError(domain: "ViewMenuTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected NSApp.appearance == .darkAqua, got \(String(describing: NSApp.appearance?.name))"])
    }
    guard matchSystemItem.state == .off && lightItem.state == .off && darkItem.state == .on else {
        throw NSError(domain: "ViewMenuTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected Dark checkmark .on, others .off"])
    }
    guard UserDefaults.standard.string(forKey: AppDelegate.appearancePreferenceKey)?.lowercased() == "dark" else {
        throw NSError(domain: "ViewMenuTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected preference 'dark' persisted"])
    }

    // Switch back to Match System
    appDelegate.setAppearanceMatchSystem(nil)
    guard NSApp.appearance == nil else {
        throw NSError(domain: "ViewMenuTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected NSApp.appearance == nil for Match System"])
    }
    guard matchSystemItem.state == .on && lightItem.state == .off && darkItem.state == .off else {
        throw NSError(domain: "ViewMenuTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected Match System checkmark .on"])
    }

    // Test restoring preference on new AppDelegate instance
    UserDefaults.standard.set("Dark", forKey: AppDelegate.appearancePreferenceKey)
    let freshDelegate = AppDelegate()
    freshDelegate.setupMainMenu()
    guard NSApp.appearance?.name == .darkAqua else {
        throw NSError(domain: "ViewMenuTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected restored appearance to be .darkAqua"])
    }

    // Clean up
    UserDefaults.standard.removeObject(forKey: AppDelegate.appearancePreferenceKey)
    freshDelegate.setAppearanceMatchSystem(nil)
}

func testWrapLinesMenuItemConfiguration() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let mainMenu = NSApplication.shared.mainMenu,
          mainMenu.items.count > 3,
          let viewMenu = mainMenu.items[3].submenu else {
        throw NSError(domain: "ViewMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "View menu missing"])
    }

    guard let wrapLinesItem = viewMenu.items.first(where: { $0.title == "Wrap Lines" }) else {
        throw NSError(domain: "ViewMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Wrap Lines item missing from View menu"])
    }

    guard wrapLinesItem.keyEquivalent == "w" else {
        throw NSError(domain: "ViewMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected keyEquivalent 'w', got '\(wrapLinesItem.keyEquivalent)'"])
    }

    guard wrapLinesItem.keyEquivalentModifierMask == [.command, .option] else {
        throw NSError(domain: "ViewMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected modifierMask [.command, .option], got \(wrapLinesItem.keyEquivalentModifierMask)"])
    }

    guard wrapLinesItem.action == #selector(AppDelegate.toggleWrapLines(_:)) else {
        throw NSError(domain: "ViewMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected action toggleWrapLines:, got \(String(describing: wrapLinesItem.action))"])
    }
}

func testDocumentWrapLinesPolicyPerFormat() throws {
    let tempDir = FileManager.default.temporaryDirectory

    // 1. CSV Document defaults to wrapLines == true (with horizontal scroller enabled)
    let csvURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).csv")
    try "col1,col2,col3\nval1,val2,val3".write(to: csvURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: csvURL) }

    let csvDoc = try VimMDDocument(contentsOf: csvURL, ofType: "public.comma-separated-values-text")
    guard csvDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected CSV document wrapLines == true"])
    }
    csvDoc.makeWindowControllers()
    guard let csvTextView = csvDoc.textView else {
        throw NSError(domain: "ViewMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "CSV textView nil"])
    }
    guard csvTextView.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "CSV textView.wrapLines expected true"])
    }
    guard csvTextView.enclosingScrollView?.hasHorizontalScroller == true else {
        throw NSError(domain: "ViewMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "CSV scrollView.hasHorizontalScroller expected true"])
    }

    // 2. TSV Document defaults to wrapLines == true (with horizontal scroller enabled)
    let tsvURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).tsv")
    try "col1\tcol2\tcol3\nval1\tval2\tval3".write(to: tsvURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tsvURL) }

    let tsvDoc = try VimMDDocument(contentsOf: tsvURL, ofType: "public.tab-separated-values-text")
    guard tsvDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected TSV document wrapLines == true"])
    }
    tsvDoc.makeWindowControllers()
    guard tsvDoc.textView?.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "TSV textView.wrapLines expected true"])
    }
    guard tsvDoc.textView?.enclosingScrollView?.hasHorizontalScroller == true else {
        throw NSError(domain: "ViewMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "TSV scrollView.hasHorizontalScroller expected true"])
    }

    // 3. Markdown Document defaults to wrapLines == true (or persisted preference)
    UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    let mdURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).md")
    try "# Header\nParagraph".write(to: mdURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: mdURL) }

    let mdDoc = try VimMDDocument(contentsOf: mdURL, ofType: "net.daringfireball.markdown")
    guard mdDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected Markdown document wrapLines == true"])
    }
    mdDoc.makeWindowControllers()
    guard mdDoc.textView?.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Markdown textView.wrapLines expected true"])
    }
    guard mdDoc.textView?.enclosingScrollView?.hasHorizontalScroller == false else {
        throw NSError(domain: "ViewMenuTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Markdown scrollView.hasHorizontalScroller expected false"])
    }

    // 4. Plain text Document defaults to wrapLines == true
    let txtURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).txt")
    try "Plain text".write(to: txtURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: txtURL) }

    let txtDoc = try VimMDDocument(contentsOf: txtURL, ofType: "public.plain-text")
    guard txtDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected Plain Text document wrapLines == true"])
    }

    // 5. If user persisted wrapLines preference == false, Markdown respects it
    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    let mdDoc2 = try VimMDDocument(contentsOf: mdURL, ofType: "net.daringfireball.markdown")
    guard mdDoc2.wrapLines == false else {
        throw NSError(domain: "ViewMenuTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected Markdown document to respect persisted wrapLines == false"])
    }

    // Clean up
    UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
}

func testWrapLinesToggleAndPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory
    UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)

    // A. Non-tabular document toggle: updates textView and persists preference
    let mdURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).md")
    try "# Title".write(to: mdURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: mdURL) }

    let mdDoc = try VimMDDocument(contentsOf: mdURL, ofType: "net.daringfireball.markdown")
    mdDoc.makeWindowControllers()
    guard mdDoc.wrapLines == true && mdDoc.textView?.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial state should be wrapLines == true"])
    }

    // Toggle wrap lines off
    mdDoc.toggleWrapLines(nil)
    guard mdDoc.wrapLines == false && mdDoc.textView?.wrapLines == false else {
        throw NSError(domain: "ViewMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "After toggle, wrapLines should be false"])
    }
    guard (UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey) as? Bool) == false else {
        throw NSError(domain: "ViewMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected false persisted in UserDefaults"])
    }

    // Toggle wrap lines back on
    mdDoc.toggleWrapLines(nil)
    guard mdDoc.wrapLines == true && mdDoc.textView?.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "After second toggle, wrapLines should be true"])
    }
    guard (UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey) as? Bool) == true else {
        throw NSError(domain: "ViewMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected true persisted in UserDefaults"])
    }

    // B. Tabular document toggle: toggles document wrapLines but DOES NOT overwrite global preference
    UserDefaults.standard.set(true, forKey: VimMDDocument.wrapLinesPreferenceKey)
    let csvURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).csv")
    try "a,b,c".write(to: csvURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: csvURL) }

    let csvDoc = try VimMDDocument(contentsOf: csvURL, ofType: "public.comma-separated-values-text")
    csvDoc.makeWindowControllers()
    guard csvDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "CSV should start with wrapLines == true"])
    }

    csvDoc.toggleWrapLines(nil)
    guard csvDoc.wrapLines == false && csvDoc.textView?.wrapLines == false else {
        throw NSError(domain: "ViewMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "CSV wrapLines should now be false"])
    }
    // Check that UserDefaults was NOT changed to false by CSV or overwritten
    guard (UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey) as? Bool) == true else {
        throw NSError(domain: "ViewMenuTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "CSV toggle must not corrupt global preference"])
    }

    // Toggle back to true on CSV
    csvDoc.toggleWrapLines(nil)
    guard csvDoc.wrapLines == true else {
        throw NSError(domain: "ViewMenuTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "CSV wrapLines should be true again"])
    }
    // Global preference should STILL be true
    guard (UserDefaults.standard.object(forKey: VimMDDocument.wrapLinesPreferenceKey) as? Bool) == true else {
        throw NSError(domain: "ViewMenuTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "CSV toggle to false must NOT set global preference to false"])
    }

    // Clean up
    UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
}

print("=== View Menu and Line Wrap Policy Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testViewMenuHierarchyAndPositioning", testViewMenuHierarchyAndPositioning),
    ("testAppearanceSubmenuAndModeSwitching", testAppearanceSubmenuAndModeSwitching),
    ("testWrapLinesMenuItemConfiguration", testWrapLinesMenuItemConfiguration),
    ("testDocumentWrapLinesPolicyPerFormat", testDocumentWrapLinesPolicyPerFormat),
    ("testWrapLinesToggleAndPersistence", testWrapLinesToggleAndPersistence)
]

for (name, test) in tests {
    total += 1
    if runTest(name: name, test: test) {
        passed += 1
    }
}

print("Result: \(passed)/\(total) tests passed.")
if passed != total {
    exit(1)
}
