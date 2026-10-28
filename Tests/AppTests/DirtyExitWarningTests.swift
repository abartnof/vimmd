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

func testDirtyDocumentQuitBlockedWithE37() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    try doc.read(from: "Initial clean content\n".data(using: .utf8)!, ofType: "public.plain-text")

    // Dirty the document
    doc.session?.feedKeys("iMutated\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should be dirty/edited"])
    }

    // Attempt :q<CR>
    doc.session?.feedKeys(":q\r")
    doc.handleQuitTrigger()

    guard !doc.isClosed else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Dirty document should NOT close on :q"])
    }

    guard let msg = doc.currentStatusMessage, msg.contains("E37: No write since last change (add ! to override)") else {
        throw NSError(domain: "DirtyExitWarningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected E37 warning message, got: '\(doc.currentStatusMessage ?? "")'"])
    }
    guard doc.isCurrentStatusMessageWarning else {
        throw NSError(domain: "DirtyExitWarningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected status message to have warning style"])
    }
}

func testCleanDocumentQuitSucceeds() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    try doc.read(from: "Clean document\n".data(using: .utf8)!, ofType: "public.plain-text")

    guard !doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should initially be clean"])
    }

    // Trigger :q<CR>
    doc.session?.feedKeys(":q\r")
    doc.handleQuitTrigger()

    guard doc.isClosed else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Clean document should close on :q"])
    }
}

func testForceQuitSucceedsWhenDirty() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    try doc.read(from: "Clean document\n".data(using: .utf8)!, ofType: "public.plain-text")

    // Dirty the document
    doc.session?.feedKeys("iUnsaved edits\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should be dirty"])
    }

    // Trigger :q!<CR>
    doc.session?.feedKeys(":q!\r")
    doc.handleQuitTrigger()

    guard doc.isClosed else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Force quit :q! should close even when dirty"])
    }
}

func testIsDocumentEditedTracksDirtyState() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("dirty_track_test_\(UUID().uuidString).md")
    let initialText = "Clean line 1\nClean line 2\n"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    // 1. Initial state
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should not be edited initially"])
    }

    // 2. Edit -> dirty
    doc.session?.feedKeys("iDirty\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Document should be edited after insert"])
    }

    // 3. Save -> clean
    try doc.write(to: fileURL, ofType: "Markdown Document", for: .saveOperation, originalContentsURL: fileURL)
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Document should not be edited after write/save"])
    }

    // 4. Edit again -> dirty
    doc.session?.feedKeys("iMore\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Document should be edited after second insert"])
    }

    // 5. Undo -> clean
    doc.session?.feedKeys("u")
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Document should not be edited after undo to clean state"])
    }
}

func testReloadForceResetsDirtyState() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("reload_test_\(UUID().uuidString).md")
    let initialText = "Original content\n"
    try initialText.write(to: fileURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "Markdown Document")
    doc.makeWindowControllers()

    // Dirty the document
    doc.session?.feedKeys("iUnsaved modifications\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should be dirty"])
    }

    // Execute :e!<CR>
    doc.session?.feedKeys(":e!\r")
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Document should be clean after :e!"])
    }
}

func testAutosavesInPlaceIsFalse() throws {
    guard !VimMDDocument.autosavesInPlace else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "VimMDDocument.autosavesInPlace must be false"])
    }
}

func testQuitAllBlockedWhenDirty() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    try doc.read(from: "Dirty doc for qa\n".data(using: .utf8)!, ofType: "public.plain-text")

    doc.session?.feedKeys("iChange\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should be dirty"])
    }

    // Trigger :qa<CR>
    doc.session?.feedKeys(":qa\r")
    doc.handleQuitTrigger()

    guard !doc.isClosed else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Dirty document should not close on :qa"])
    }
    guard let msg = doc.currentStatusMessage, msg.contains("E37: No write since last change (add ! to override)") else {
        throw NSError(domain: "DirtyExitWarningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected E37 warning on :qa, got '\(doc.currentStatusMessage ?? "")'"])
    }
}

class TestCloseDelegate: NSObject {
    var shouldCloseCalled = false
    var shouldCloseValue = false

    @objc func document(_ doc: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        shouldCloseCalled = true
        shouldCloseValue = shouldClose
    }
}

func testCanCloseCleanDocumentAllowsClose() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    try doc.read(from: "Clean doc\n".data(using: .utf8)!, ofType: "public.plain-text")

    let delegate = TestCloseDelegate()
    let selector = #selector(TestCloseDelegate.document(_:shouldClose:contextInfo:))

    doc.canClose(withDelegate: delegate, shouldClose: selector, contextInfo: nil)

    guard delegate.shouldCloseCalled else {
        throw NSError(domain: "DirtyExitWarningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected delegate callback to be called"])
    }
    guard delegate.shouldCloseValue == true else {
        throw NSError(domain: "DirtyExitWarningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected clean document to allow closing"])
    }
}

var passed = 0
var failed = 0
let tests: [(String, () throws -> Void)] = [
    ("testDirtyDocumentQuitBlockedWithE37", testDirtyDocumentQuitBlockedWithE37),
    ("testCleanDocumentQuitSucceeds", testCleanDocumentQuitSucceeds),
    ("testForceQuitSucceedsWhenDirty", testForceQuitSucceedsWhenDirty),
    ("testIsDocumentEditedTracksDirtyState", testIsDocumentEditedTracksDirtyState),
    ("testReloadForceResetsDirtyState", testReloadForceResetsDirtyState),
    ("testAutosavesInPlaceIsFalse", testAutosavesInPlaceIsFalse),
    ("testQuitAllBlockedWhenDirty", testQuitAllBlockedWhenDirty),
    ("testCanCloseCleanDocumentAllowsClose", testCanCloseCleanDocumentAllowsClose),
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
