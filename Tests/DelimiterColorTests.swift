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

func colorsAreEqual(_ c1: NSColor, _ c2: NSColor) -> Bool {
    if c1 == c2 { return true }
    let rgb1 = c1.usingColorSpace(.sRGB) ?? c1
    let rgb2 = c2.usingColorSpace(.sRGB) ?? c2
    return abs(rgb1.redComponent - rgb2.redComponent) < 0.01 &&
           abs(rgb1.greenComponent - rgb2.greenComponent) < 0.01 &&
           abs(rgb1.blueComponent - rgb2.blueComponent) < 0.01 &&
           abs(rgb1.alphaComponent - rgb2.alphaComponent) < 0.01
}

// 1. View Menu Item tests
func testViewMenuDelimiterColorItemExistsAndConfigured() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let mainMenu = NSApplication.shared.mainMenu,
          mainMenu.items.count > 3,
          let viewMenu = mainMenu.items[3].submenu else {
        throw NSError(domain: "DelimiterColorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "View menu missing"])
    }

    guard let item = viewMenu.items.first(where: { $0.title == "Delimiter Color…" || $0.title == "Delimiter Color..." }) else {
        throw NSError(domain: "DelimiterColorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Delimiter Color menu item not found in View menu"])
    }

    guard item.action == #selector(AppDelegate.showDelimiterColorPicker(_:)) || item.action == #selector(AppDelegate.orderFrontColorPanel(_:)) else {
        throw NSError(domain: "DelimiterColorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected action on Delimiter Color menu item: \(String(describing: item.action))"])
    }

    guard (item.target as? AppDelegate) === appDelegate || item.target == nil else {
        throw NSError(domain: "DelimiterColorTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Target on Delimiter Color item not as expected"])
    }
}

// 2. Color Panel Presentation
func testShowDelimiterColorPickerPresentsPanelWithStoredColor() throws {
    let customColor = NSColor(calibratedRed: 0.85, green: 0.15, blue: 0.35, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = customColor

    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()
    appDelegate.showDelimiterColorPicker(nil)

    let panel = NSColorPanel.shared
    guard colorsAreEqual(panel.color, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected NSColorPanel color to match stored delimiterColor"])
    }

    // Verify target via KVC or action invocation
    if let target = panel.value(forKey: "target") as? AppDelegate {
        guard target === appDelegate else {
            throw NSError(domain: "DelimiterColorTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected NSColorPanel target to be AppDelegate"])
        }
    }

    // Simulate user choosing another color in panel
    let chosenColor = NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    panel.color = chosenColor
    appDelegate.delimiterColorDidChange(panel)

    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, chosenColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "delimiterColorDidChange did not update DelimiterColorManager"])
    }

    // Test fallback when sender is not NSColorPanel
    let fallbackColor = NSColor(calibratedRed: 0.4, green: 0.7, blue: 0.2, alpha: 1.0)
    panel.color = fallbackColor
    appDelegate.delimiterColorDidChange(nil) // sender is nil, falls back gracefully to shared color panel
    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, fallbackColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "delimiterColorDidChange with nil sender did not fallback to shared NSColorPanel"])
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

// 3. DelimiterColorManager Persistence and Corrupt Data Fallback
func testDelimiterColorManagerDefaultAndPersistence() throws {
    // 3a. Clean state returns default tertiaryLabelColor
    DelimiterColorManager.shared.resetToDefault()
    let defaultColor = DelimiterColorManager.shared.delimiterColor
    guard colorsAreEqual(defaultColor, NSColor.tertiaryLabelColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected default color to equal NSColor.tertiaryLabelColor"])
    }

    // 3b. Setting color persists to UserDefaults under VimMDDelimiterColorKey
    let targetColor = NSColor(calibratedRed: 0.25, green: 0.75, blue: 0.50, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = targetColor

    guard let persistedData = UserDefaults.standard.data(forKey: DelimiterColorManager.userDefaultsKey) else {
        throw NSError(domain: "DelimiterColorTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "No data stored in UserDefaults for VimMDDelimiterColorKey"])
    }

    guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: persistedData),
          colorsAreEqual(unarchived, targetColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Unarchived color from UserDefaults does not match targetColor"])
    }

    // 3c. Reading delimiterColor retrieves the persisted color
    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, targetColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "DelimiterColorManager.shared.delimiterColor did not return targetColor"])
    }

    // 3d. Corrupt data safely falls back to default without crashing
    DelimiterColorManager.shared.invalidateCache()
    UserDefaults.standard.set(Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x12]), forKey: DelimiterColorManager.userDefaultsKey)
    let fallbackColor = DelimiterColorManager.shared.delimiterColor
    guard colorsAreEqual(fallbackColor, NSColor.tertiaryLabelColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Corrupt data did not fallback to NSColor.tertiaryLabelColor"])
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

// 4. VimModeTheme Delimiter Color Integration
func testVimModeThemeDelimiterColorIntegration() throws {
    DelimiterColorManager.shared.resetToDefault()
    guard colorsAreEqual(VimModeTheme.delimiterColor, NSColor.tertiaryLabelColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "VimModeTheme.delimiterColor mismatch with default"])
    }

    let customColor = NSColor(calibratedRed: 0.1, green: 0.6, blue: 0.9, alpha: 1.0)
    VimModeTheme.delimiterColor = customColor
    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Setting VimModeTheme.delimiterColor did not update DelimiterColorManager"])
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

// 5. Markdown Delimiters Styling with Custom Color
func testMarkdownSyntaxResolverUsesDelimiterColor() throws {
    let customColor = NSColor(calibratedRed: 0.95, green: 0.40, blue: 0.10, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = customColor

    let resolver = MarkdownSyntaxResolver()

    // 5a. Headers: '# Header'
    let hStorage = NSMutableAttributedString(string: "# Header Title\n")
    resolver.renderSyntax(in: hStorage)
    let hAttrs = hStorage.attributes(at: 0, effectiveRange: nil)
    guard let hColor = hAttrs[.foregroundColor] as? NSColor, colorsAreEqual(hColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Header '#' delimiter did not receive custom delimiter color"])
    }

    // 5b. Bold: '**bold**'
    let bStorage = NSMutableAttributedString(string: "text **bold** text\n")
    resolver.renderSyntax(in: bStorage)
    // '**' at index 5 and 6
    let bAttrs = bStorage.attributes(at: 5, effectiveRange: nil)
    guard let bColor = bAttrs[.foregroundColor] as? NSColor, colorsAreEqual(bColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Bold '**' delimiter did not receive custom delimiter color"])
    }

    // 5c. Italic: '*italic*'
    let iStorage = NSMutableAttributedString(string: "text *italic* text\n")
    resolver.renderSyntax(in: iStorage)
    let iAttrs = iStorage.attributes(at: 5, effectiveRange: nil)
    guard let iColor = iAttrs[.foregroundColor] as? NSColor, colorsAreEqual(iColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Italic '*' delimiter did not receive custom delimiter color"])
    }

    // 5d. Code: '`code`'
    let cStorage = NSMutableAttributedString(string: "text `code` text\n")
    resolver.renderSyntax(in: cStorage)
    let cAttrs = cStorage.attributes(at: 5, effectiveRange: nil)
    guard let cColor = cAttrs[.foregroundColor] as? NSColor, colorsAreEqual(cColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Code '`' delimiter did not receive custom delimiter color"])
    }

    // 5e. Strikethrough: '~~strike~~'
    let sStorage = NSMutableAttributedString(string: "text ~~strike~~ text\n")
    resolver.renderSyntax(in: sStorage)
    let sAttrs = sStorage.attributes(at: 5, effectiveRange: nil)
    guard let sColor = sAttrs[.foregroundColor] as? NSColor, colorsAreEqual(sColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Strikethrough '~~' delimiter did not receive custom delimiter color"])
    }

    // 5f. Links: '[title](url)'
    let lStorage = NSMutableAttributedString(string: "see [link](http://example.com) now\n")
    resolver.renderSyntax(in: lStorage)
    let lAttrs = lStorage.attributes(at: 4, effectiveRange: nil) // '[' at index 4
    guard let lColor = lAttrs[.foregroundColor] as? NSColor, colorsAreEqual(lColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Link '[' delimiter did not receive custom delimiter color"])
    }

    // 5g. Table pipe: '| col1 | col2 |'
    let tStorage = NSMutableAttributedString(string: "| col1 | col2 |\n| --- | --- |\n")
    resolver.renderSyntax(in: tStorage)
    let pipeAttrs = tStorage.attributes(at: 0, effectiveRange: nil) // '|' at index 0
    guard let pipeColor = pipeAttrs[.foregroundColor] as? NSColor, colorsAreEqual(pipeColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "Table pipe '|' delimiter did not receive custom delimiter color"])
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

// 6. Tabular Delimiters Styling with Custom Color
func testTabularSyntaxResolverUsesDelimiterColor() throws {
    let customColor = NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.85, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = customColor

    let resolver = TabularSyntaxResolver()

    // 6a. CSV comma separator ','
    let csvStorage = NSMutableAttributedString(string: "Name,Age,City\nAlice,30,NYC\n")
    resolver.renderTabularSyntax(in: csvStorage, isTSV: false)
    // Comma at index 4 ('Name,')
    let csvAttrs = csvStorage.attributes(at: 4, effectiveRange: nil)
    guard let commaColor = csvAttrs[.foregroundColor] as? NSColor, colorsAreEqual(commaColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "CSV comma delimiter did not receive custom delimiter color"])
    }

    // 6b. TSV tab separator '\t'
    let tsvStorage = NSMutableAttributedString(string: "Col1\tCol2\tCol3\nVal1\tVal2\tVal3\n")
    resolver.renderTabularSyntax(in: tsvStorage, isTSV: true)
    // Tab at index 4 ('Col1\t')
    let tsvAttrs = tsvStorage.attributes(at: 4, effectiveRange: nil)
    guard let tabColor = tsvAttrs[.foregroundColor] as? NSColor, colorsAreEqual(tabColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "TSV tab delimiter did not receive custom delimiter color"])
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

// 7. Live Updates Broadcast to Open TextViews
func testLiveUpdateBroadcastReRendersOpenDocumentsAndViews() throws {
    DelimiterColorManager.shared.resetToDefault()

    let initialColor = DelimiterColorManager.shared.delimiterColor

    let mdTextView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    mdTextView.documentSyntaxType = .markdown
    mdTextView.string = "# Header Delimiter\n**Bold Text**\n"
    mdTextView.updateSyntaxStyling(force: true)

    let csvTextView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
    csvTextView.documentSyntaxType = .csv
    csvTextView.string = "Alpha,Beta,Gamma\n"
    csvTextView.updateSyntaxStyling(force: true)

    // Initial check: delimiters styled with initialColor
    if let mdStorage = mdTextView.textStorage {
        let hColor = mdStorage.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? NSColor
        guard let hc = hColor, colorsAreEqual(hc, initialColor) else {
            throw NSError(domain: "DelimiterColorTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Initial markdown delimiter color mismatch"])
        }
    }
    if let csvStorage = csvTextView.textStorage {
        let commaColor = csvStorage.attributes(at: 5, effectiveRange: nil)[.foregroundColor] as? NSColor
        guard let cc = commaColor, colorsAreEqual(cc, initialColor) else {
            throw NSError(domain: "DelimiterColorTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Initial CSV delimiter color mismatch"])
        }
    }

    // Live tweak color via DelimiterColorManager (as when user moves slider in NSColorPanel)
    let newColor = NSColor(calibratedRed: 0.12, green: 0.88, blue: 0.44, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = newColor

    // Delimiters should immediately update without manual reload
    if let mdStorage = mdTextView.textStorage {
        let updatedHColor = mdStorage.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? NSColor
        guard let uhc = updatedHColor, colorsAreEqual(uhc, newColor) else {
            throw NSError(domain: "DelimiterColorTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Live update did not re-render markdown delimiter to new color"])
        }
    }
    if let csvStorage = csvTextView.textStorage {
        let updatedCommaColor = csvStorage.attributes(at: 5, effectiveRange: nil)[.foregroundColor] as? NSColor
        guard let ucc = updatedCommaColor, colorsAreEqual(ucc, newColor) else {
            throw NSError(domain: "DelimiterColorTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Live update did not re-render CSV delimiter to new color"])
        }
    }

    // Clean up
    DelimiterColorManager.shared.resetToDefault()
}

func testDelimiterColorManagerInMemoryCaching() throws {
    DelimiterColorManager.shared.resetToDefault()
    let initialColor = DelimiterColorManager.shared.delimiterColor
    guard colorsAreEqual(initialColor, NSColor.tertiaryLabelColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Expected default initial color"])
    }

    let customColor = NSColor(calibratedRed: 0.6, green: 0.2, blue: 0.8, alpha: 1.0)
    DelimiterColorManager.shared.delimiterColor = customColor

    // Delete underlying persistence entry directly from UserDefaults
    UserDefaults.standard.removeObject(forKey: DelimiterColorManager.userDefaultsKey)

    // Cached value should still be returned without hitting UserDefaults
    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, customColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected in-memory cache to return customColor even after UserDefaults key removal"])
    }

    // Invalidating cache forces reload from UserDefaults (which was removed, so falls back to default)
    DelimiterColorManager.shared.invalidateCache()
    guard colorsAreEqual(DelimiterColorManager.shared.delimiterColor, NSColor.tertiaryLabelColor) else {
        throw NSError(domain: "DelimiterColorTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected reload after cache invalidation to return defaultColor"])
    }

    DelimiterColorManager.shared.resetToDefault()
}

// Runner
print("=========================================")
print(" Delimiter Color Unit Tests (Milestone Y)")
print("=========================================")

var allPassed = true
let tests: [(String, () throws -> Void)] = [
    ("testViewMenuDelimiterColorItemExistsAndConfigured", testViewMenuDelimiterColorItemExistsAndConfigured),
    ("testShowDelimiterColorPickerPresentsPanelWithStoredColor", testShowDelimiterColorPickerPresentsPanelWithStoredColor),
    ("testDelimiterColorManagerDefaultAndPersistence", testDelimiterColorManagerDefaultAndPersistence),
    ("testDelimiterColorManagerInMemoryCaching", testDelimiterColorManagerInMemoryCaching),
    ("testVimModeThemeDelimiterColorIntegration", testVimModeThemeDelimiterColorIntegration),
    ("testMarkdownSyntaxResolverUsesDelimiterColor", testMarkdownSyntaxResolverUsesDelimiterColor),
    ("testTabularSyntaxResolverUsesDelimiterColor", testTabularSyntaxResolverUsesDelimiterColor),
    ("testLiveUpdateBroadcastReRendersOpenDocumentsAndViews", testLiveUpdateBroadcastReRendersOpenDocumentsAndViews)
]

var passedCount = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passedCount += 1
    } else {
        allPassed = false
    }
}

print("Result: \(passedCount)/\(tests.count) tests passed.")
if !allPassed {
    exit(1)
}
