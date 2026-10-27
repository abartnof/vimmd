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

func testDocumentSerializationAndReading() throws {
    let doc = VimMDDocument()
    let initialMarkdown = "# Document Title\nFirst paragraph of text."
    guard let inputData = initialMarkdown.data(using: .utf8) else {
        throw NSError(domain: "AppTests", code: 1, userInfo: nil)
    }

    try doc.read(from: inputData, ofType: "public.plain-text")
    guard doc.session != nil else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Document session was not initialized on read"])
    }

    let outputData = try doc.data(ofType: "public.plain-text")
    guard let serializedString = String(data: outputData, encoding: .utf8) else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed decoding output data as UTF-8"])
    }

    guard serializedString == initialMarkdown else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Serialized data mismatch: '\(serializedString)'"])
    }
}

func testDocumentDirtyState() throws {
    let doc = VimMDDocument()
    let inputData = "Initial content".data(using: .utf8)!
    try doc.read(from: inputData, ofType: "public.plain-text")

    guard !doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected fresh document not to be edited"])
    }

    // Mutate through VimSession
    doc.session?.feedKeys("iAdded\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected document to be edited after Vim mutation"])
    }

    // Clear dirty state on save
    doc.session?.clearDirty()
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected document clean after clearDirty"])
    }
}

func testQuitPipelineFromVimCommands() throws {
    // 1. ZZ trigger: save and close
    let doc1 = VimMDDocument()
    try doc1.read(from: "ZZ test".data(using: .utf8)!, ofType: "public.plain-text")
    doc1.session?.feedKeys("ZZ")
    guard doc1.session?.shouldQuit == true else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected shouldQuit after ZZ"])
    }
    doc1.handleQuitTrigger()
    guard doc1.isClosed else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected doc1 to be closed after ZZ trigger"])
    }

    // 2. ZQ trigger: close without save
    let doc2 = VimMDDocument()
    try doc2.read(from: "ZQ test".data(using: .utf8)!, ofType: "public.plain-text")
    doc2.session?.feedKeys("ZQ")
    guard doc2.session?.shouldQuit == true else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected shouldQuit after ZQ"])
    }
    doc2.handleQuitTrigger()
    guard doc2.isClosed else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected doc2 to be closed after ZQ trigger"])
    }

    // 3. :q trigger
    let doc3 = VimMDDocument()
    try doc3.read(from: "Ex q test".data(using: .utf8)!, ofType: "public.plain-text")
    doc3.session?.executeEx("q")
    guard doc3.session?.shouldQuit == true else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected shouldQuit after :q"])
    }
    doc3.handleQuitTrigger()
    guard doc3.isClosed else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected doc3 to be closed after :q trigger"])
    }

    // 4. :wq trigger
    let doc4 = VimMDDocument()
    try doc4.read(from: "Ex wq test".data(using: .utf8)!, ofType: "public.plain-text")
    doc4.session?.executeEx("wq")
    guard doc4.session?.shouldQuit == true else {
        throw NSError(domain: "AppTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected shouldQuit after :wq"])
    }
    doc4.handleQuitTrigger()
    guard doc4.isClosed else {
        throw NSError(domain: "AppTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected doc4 to be closed after :wq trigger"])
    }
}

func testMultibyteAndEmptySerialization() throws {
    // Empty document
    let emptyDoc = VimMDDocument()
    try emptyDoc.read(from: Data(), ofType: "public.plain-text")
    guard emptyDoc.session != nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty doc session not initialized"])
    }
    let emptyData = try emptyDoc.data(ofType: "public.plain-text")
    guard emptyData.isEmpty else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected empty data for empty doc"])
    }

    // Multibyte document
    let multiDoc = VimMDDocument()
    let multiMarkdown = "# 🚀 MultiByte Header\nこんにちは 世界\nEmoticon: ✨🎉"
    guard let multiData = multiMarkdown.data(using: .utf8) else {
        throw NSError(domain: "AppTests", code: 3, userInfo: nil)
    }
    try multiDoc.read(from: multiData, ofType: "public.plain-text")
    let outputData = try multiDoc.data(ofType: "public.plain-text")
    guard let resultString = String(data: outputData, encoding: .utf8) else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed decoding multibyte UTF-8"])
    }
    guard resultString == multiMarkdown else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Multibyte content mismatch: '\(resultString)'"])
    }
}

func testDocumentWindowControllerSetup() throws {
    let doc = VimMDDocument()
    try doc.read(from: "# Window Setup\nContent line".data(using: .utf8)!, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard doc.windowControllers.count == 1 else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected exactly 1 window controller"])
    }
    guard let window = doc.windowControllers.first?.window else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Window controller has no window"])
    }
    guard let scrollView = window.contentView as? NSScrollView else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Window content view is not NSScrollView"])
    }
    guard let tv = scrollView.documentView as? VimMDTextView else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "ScrollView document view is not VimMDTextView"])
    }
    guard doc.textView === tv else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "doc.textView was not set"])
    }
    guard tv.session === doc.session else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "TextView session is not bound to document session"])
    }
}

func testDocumentAtomicWriteAndClearDirty() throws {
    let doc = VimMDDocument()
    try doc.read(from: "Initial disk content".data(using: .utf8)!, ofType: "public.plain-text")

    // Mutate
    doc.session?.feedKeys("iMutated \u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected document to be edited"])
    }

    let tempDir = FileManager.default.temporaryDirectory
    let tempFileURL = tempDir.appendingPathComponent("vimmd_test_\(UUID().uuidString).md")
    defer {
        try? FileManager.default.removeItem(at: tempFileURL)
    }

    try doc.write(to: tempFileURL, ofType: "public.plain-text", for: .saveOperation, originalContentsURL: nil)

    guard !doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected document dirty state cleared after write"])
    }

    let writtenContent = try String(contentsOf: tempFileURL, encoding: .utf8)
    guard writtenContent == "Mutated Initial disk content" else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Written content mismatch: '\(writtenContent)'"])
    }
}

func testAppDelegateTerminationPolicy() throws {
    let appDelegate = AppDelegate()
    let shouldTerminate = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
    guard shouldTerminate == true else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected applicationShouldTerminateAfterLastWindowClosed to return true"])
    }
}

func testAppDelegateMenuBarSetup() throws {
    let appDelegate = AppDelegate()
    appDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    guard let mainMenu = NSApplication.shared.mainMenu else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected mainMenu to be set"])
    }
    guard mainMenu.items.count >= 3 else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected standard menus (App, File, Edit, etc.), got \(mainMenu.items.count)"])
    }
}

func testDefaultInitHasSession() throws {
    let doc = VimMDDocument()
    guard doc.session != nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected VimMDDocument() default init to have a non-nil session"])
    }
}

func testObjCRuntimeClassName() throws {
    guard NSClassFromString("VimMDDocument") != nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected NSClassFromString(\"VimMDDocument\") to resolve without mangling"])
    }
}

func testAppDelegateShouldOpenUntitledFile() throws {
    let appDelegate = AppDelegate()
    guard appDelegate.applicationShouldOpenUntitledFile(NSApplication.shared) == false else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected applicationShouldOpenUntitledFile to return false"])
    }
}

print("=== App Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testDocumentSerializationAndReading", testDocumentSerializationAndReading),
    ("testDocumentDirtyState", testDocumentDirtyState),
    ("testQuitPipelineFromVimCommands", testQuitPipelineFromVimCommands),
    ("testMultibyteAndEmptySerialization", testMultibyteAndEmptySerialization),
    ("testDocumentWindowControllerSetup", testDocumentWindowControllerSetup),
    ("testDocumentAtomicWriteAndClearDirty", testDocumentAtomicWriteAndClearDirty),
    ("testAppDelegateTerminationPolicy", testAppDelegateTerminationPolicy),
    ("testAppDelegateMenuBarSetup", testAppDelegateMenuBarSetup),
    ("testDefaultInitHasSession", testDefaultInitHasSession),
    ("testObjCRuntimeClassName", testObjCRuntimeClassName),
    ("testAppDelegateShouldOpenUntitledFile", testAppDelegateShouldOpenUntitledFile)
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
