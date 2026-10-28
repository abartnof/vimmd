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
    guard (chip.layer?.cornerRadius ?? 0.0) > 0.0 else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have rounded corners"])
    }
    guard chip.layer?.backgroundColor != nil else {
        throw NSError(domain: "SaveConfirmationChipTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "savedChipView must have background color tint"])
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
