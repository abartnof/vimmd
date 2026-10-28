import Foundation
import AppKit
import App
import Engine
import Views
import CBridge

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

func testInitialStateOfSavedChip() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    guard let chip = doc.savedChipView else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "savedChipView must not be nil"])
    }
    guard !doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "savedChipView should initially be invisible"])
    }
    guard chip.alphaValue == 0.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "savedChipView alphaValue should initially be 0.0, got \(chip.alphaValue)"])
    }

    let text = chip.text
    guard text.contains("Saved") else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Chip text '\(text)' does not contain 'Saved'"])
    }
}

func testShowSavedChipManualCall() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    doc.showSavedChip(duration: 2.0)
    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected isSavedChipVisible == true after showSavedChip"])
    }
    guard let alpha = doc.savedChipView?.alphaValue, alpha == 1.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected alphaValue == 1.0 after showSavedChip"])
    }
}

func testSavedChipDismissalAndFadeOut() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    doc.showSavedChip(duration: 0.05)
    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip visible immediately"])
    }

    // Run runloop to let timer fire and fade out
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

    guard !doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected chip to fade out and become invisible"])
    }
    guard (doc.savedChipView?.alphaValue ?? 1.0) == 0.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected alphaValue == 0.0 after fade out"])
    }
}

func testSavedChipTriggeredOnWrite() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("chip_write_test_\(UUID().uuidString).md")
    let initialText = "# Header\nBody"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    guard !doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip invisible before write"])
    }

    // Mutate buffer
    doc.session?.feedKeys("iExtra\u{1b}")
    try doc.write(to: fileURL, ofType: "Markdown Document", for: .saveOperation, originalContentsURL: fileURL)

    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected chip visible after document write"])
    }
}

func testSavedChipTriggeredOnExSave() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("chip_ex_save_\(UUID().uuidString).md")
    let initialText = "Line 1\nLine 2"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    // Feed :w<CR>
    doc.session?.feedKeys(":w\r")

    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip visible after :w Ex command"])
    }
}

func testSavedChipTriggeredOnSaveAndQuit() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("chip_wq_\(UUID().uuidString).md")
    let initialText = "Line 1\nLine 2"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    // Feed :wq<CR>
    doc.session?.feedKeys(":wq\r")

    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip visible after :wq"])
    }
}

func testSavedChipTriggeredOnZZ() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("chip_zz_\(UUID().uuidString).md")
    let initialText = "Line A\nLine B"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    // Mutate and press ZZ
    doc.session?.feedKeys("iEdited\u{1b}ZZ")

    guard doc.isSavedChipVisible else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip visible after ZZ"])
    }
}

func testSavedChipAppearanceAndStyling() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    guard let chip = doc.savedChipView else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "savedChipView must not be nil"])
    }

    guard chip.wantsLayer else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have wantsLayer enabled"])
    }
    guard let cornerRadius = chip.layer?.cornerRadius, cornerRadius == 9.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have cornerRadius == 9.0, got \(String(describing: chip.layer?.cornerRadius))"])
    }
    guard let borderWidth = chip.layer?.borderWidth, borderWidth == 0.5 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have borderWidth == 0.5, got \(String(describing: chip.layer?.borderWidth))"])
    }
    guard chip.layer?.borderColor != nil else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have non-nil borderColor"])
    }
    guard chip.layer?.backgroundColor != nil else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have background color tint"])
    }
}

func testSavedChipSFSymbolAndStackView() throws {
    let chip = SavedChipView(frame: NSRect(x: 0, y: 0, width: 78, height: 18))
    
    // Check if system symbols are supported
    let sysSymbolAvailable: Bool
    if #available(macOS 11.0, *) {
        sysSymbolAvailable = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved") != nil
    } else {
        sysSymbolAvailable = false
    }

    if sysSymbolAvailable {
        guard let iv = chip.imageView else {
            throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected chip.imageView to be non-nil when SF Symbols are supported"])
        }
        guard chip.symbolImage != nil else {
            throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected chip.symbolImage to be non-nil"])
        }
        guard iv.image == chip.symbolImage else {
            throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected chip.imageView.image == chip.symbolImage"])
        }
        guard chip.text == "Saved" else {
            throw NSError(domain: "SaveConfirmationChipTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected chip.text == 'Saved', got '\(chip.text)'"])
        }
    } else {
        guard chip.text == "✓ Saved" else {
            throw NSError(domain: "SaveConfirmationChipTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected fallback text '✓ Saved', got '\(chip.text)'"])
        }
    }

    guard chip.label.textColor == NSColor.systemGreen else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected label.textColor == NSColor.systemGreen"])
    }
}

func testSavedChipStatusBarDimensions() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    guard let chip = doc.savedChipView else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "savedChipView must not be nil"])
    }

    guard chip.frame.width >= 76 && chip.frame.width <= 80 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected chip width between 76 and 80, got \(chip.frame.width)"])
    }
    guard chip.frame.height == 18.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected chip height == 18.0, got \(chip.frame.height)"])
    }
}

var passed = 0
var failed = 0
let tests: [(String, () throws -> Void)] = [
    ("testInitialStateOfSavedChip", testInitialStateOfSavedChip),
    ("testShowSavedChipManualCall", testShowSavedChipManualCall),
    ("testSavedChipDismissalAndFadeOut", testSavedChipDismissalAndFadeOut),
    ("testSavedChipTriggeredOnWrite", testSavedChipTriggeredOnWrite),
    ("testSavedChipTriggeredOnExSave", testSavedChipTriggeredOnExSave),
    ("testSavedChipTriggeredOnSaveAndQuit", testSavedChipTriggeredOnSaveAndQuit),
    ("testSavedChipTriggeredOnZZ", testSavedChipTriggeredOnZZ),
    ("testSavedChipAppearanceAndStyling", testSavedChipAppearanceAndStyling),
    ("testSavedChipSFSymbolAndStackView", testSavedChipSFSymbolAndStackView),
    ("testSavedChipStatusBarDimensions", testSavedChipStatusBarDimensions),
]

for (name, test) in tests {
    if runTest(name: name, test: test) {
        passed += 1
    } else {
        failed += 1
    }
}

print("Result: \(passed)/\(tests.count) tests passed.")
if failed > 0 {
    exit(1)
}
