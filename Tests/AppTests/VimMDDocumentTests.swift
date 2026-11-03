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
    guard let container = window.contentView else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Window has no content view"])
    }
    guard let scrollView = container.subviews.compactMap({ $0 as? NSScrollView }).first else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Content view missing NSScrollView"])
    }
    guard let tv = scrollView.documentView as? VimMDTextView else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "ScrollView document view is not VimMDTextView"])
    }
    guard doc.textView === tv else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "doc.textView was not set"])
    }
    guard tv.session === doc.session else {
        throw NSError(domain: "AppTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "TextView session is not bound to document session"])
    }
    guard window.initialFirstResponder === tv else {
        throw NSError(domain: "AppTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected initialFirstResponder to be tv"])
    }
    guard doc.modeLabel?.stringValue == "NORMAL" || doc.modeLabel?.stringValue == "-- NORMAL --" else {
        throw NSError(domain: "AppTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected modeLabel 'NORMAL', got \(doc.modeLabel?.stringValue ?? "nil")"])
    }
    let expectedTitle = doc.displayName ?? "Untitled"
    guard window.title == expectedTitle else {
        throw NSError(domain: "AppTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected window title to strictly equal '\(expectedTitle)', got '\(window.title)'"])
    }
    guard !window.title.contains("[") && !window.title.contains("]") && !window.title.contains("NORMAL") else {
        throw NSError(domain: "AppTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected window title not to contain mode string or brackets, got '\(window.title)'"])
    }

    // Test mode transitions update status display and window title
    doc.session?.feedKeys("i")
    guard doc.modeLabel?.stringValue == "INSERT" || doc.modeLabel?.stringValue == "-- INSERT --" else {
        throw NSError(domain: "AppTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected modeLabel 'INSERT' after 'i', got \(doc.modeLabel?.stringValue ?? "nil")"])
    }
    guard window.title == expectedTitle else {
        throw NSError(domain: "AppTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected window title to strictly equal '\(expectedTitle)' in INSERT mode, got '\(window.title)'"])
    }
    guard !window.title.contains("[") && !window.title.contains("]") && !window.title.contains("INSERT") else {
        throw NSError(domain: "AppTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected window title not to contain INSERT mode or brackets, got '\(window.title)'"])
    }

    doc.session?.feedKeys("\u{1b}")
    guard doc.modeLabel?.stringValue == "NORMAL" || doc.modeLabel?.stringValue == "-- NORMAL --" else {
        throw NSError(domain: "AppTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected modeLabel 'NORMAL' after Esc, got \(doc.modeLabel?.stringValue ?? "nil")"])
    }
    guard window.title == expectedTitle else {
        throw NSError(domain: "AppTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected window title to strictly equal '\(expectedTitle)' after Esc, got '\(window.title)'"])
    }
    guard !window.title.contains("[") && !window.title.contains("]") && !window.title.contains("NORMAL") else {
        throw NSError(domain: "AppTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected window title not to contain NORMAL mode or brackets, got '\(window.title)'"])
    }

    doc.session?.feedKeys("v")
    guard doc.modeLabel?.stringValue == "VISUAL" || doc.modeLabel?.stringValue == "-- VISUAL --" else {
        throw NSError(domain: "AppTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected modeLabel 'VISUAL' after 'v', got \(doc.modeLabel?.stringValue ?? "nil")"])
    }
    guard window.title == expectedTitle else {
        throw NSError(domain: "AppTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected window title to strictly equal '\(expectedTitle)' in VISUAL mode, got '\(window.title)'"])
    }
    guard !window.title.contains("[") && !window.title.contains("]") && !window.title.contains("VISUAL") else {
        throw NSError(domain: "AppTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected window title not to contain VISUAL mode or brackets, got '\(window.title)'"])
    }

    doc.session?.feedKeys("\u{1b}")
    guard window.title == expectedTitle else {
        throw NSError(domain: "AppTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected window title to strictly equal '\(expectedTitle)' after Esc from VISUAL, got '\(window.title)'"])
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
    // Before any document is opened, termination should be guarded (return false)
    // to prevent premature termination when NSOpenPanel closes.
    guard appDelegate.hasOpenedDocument == false else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected hasOpenedDocument to be false initially"])
    }
    let shouldTerminateBeforeOpen = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
    guard shouldTerminateBeforeOpen == false else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected applicationShouldTerminateAfterLastWindowClosed to return false before document opened"])
    }

    // Once a document has been opened and all documents are closed, it should terminate (return true)
    appDelegate.hasOpenedDocument = true
    let shouldTerminateAfterOpen = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
    guard shouldTerminateAfterOpen == true else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected applicationShouldTerminateAfterLastWindowClosed to return true after document opened and closed"])
    }
}

func testDocumentLossyDecoding() throws {
    let doc = VimMDDocument()
    // Non-strict UTF-8 bytes (invalid continuation sequence 0xFF 0xFE)
    let nonStrictBytes = Data([0x23, 0x20, 0x54, 0x69, 0x74, 0x6c, 0x65, 0x0a, 0xff, 0xfe, 0x41, 0x42])
    try doc.read(from: nonStrictBytes, ofType: "public.plain-text")
    guard doc.session != nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session should be initialized even with non-strict UTF-8 data"])
    }
    guard let buffer = doc.session?.serializeBuffer(), buffer.contains("Title") else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Serialized buffer missing valid characters"])
    }
}

func testInfoPlistDocumentExtensions() throws {
    let rootPath = FileManager.default.currentDirectoryPath
    let plistPath = "\(rootPath)/build/VimMD.app/Contents/Info.plist"
    guard let plistData = FileManager.default.contents(atPath: plistPath),
          let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read Info.plist at \(plistPath)"])
    }

    guard let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]], !docTypes.isEmpty else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing CFBundleDocumentTypes in Info.plist"])
    }

    let firstType = docTypes[0]
    guard let extensions = firstType["CFBundleTypeExtensions"] as? [String] else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing CFBundleTypeExtensions in CFBundleDocumentTypes"])
    }

    guard extensions.contains("md") && extensions.contains("markdown") &&
          extensions.contains("tsv") && extensions.contains("csv") &&
          extensions.contains("sh") && extensions.contains("txt") &&
          extensions.contains("json") else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "CFBundleTypeExtensions missing common formats: \(extensions)"])
    }

    guard let contentTypes = firstType["LSItemContentTypes"] as? [String],
          contentTypes.contains("public.plain-text"),
          contentTypes.contains("public.comma-separated-values-text"),
          contentTypes.contains("public.tab-separated-values-text"),
          contentTypes.contains("public.source-code"),
          contentTypes.contains("public.shell-script") else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "LSItemContentTypes missing common types: \(String(describing: firstType["LSItemContentTypes"]))"])
    }

    // UTExportedTypeDeclarations or UTImportedTypeDeclarations
    let hasUTI = (plist["UTExportedTypeDeclarations"] as? [[String: Any]]) != nil ||
                 (plist["UTImportedTypeDeclarations"] as? [[String: Any]]) != nil
    guard hasUTI else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing UTExportedTypeDeclarations or UTImportedTypeDeclarations in Info.plist"])
    }
}

func testMultipleCommonFileFormats() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let formats: [(ext: String, content: String)] = [
        ("tsv", "col1\tcol2\tcol3\nval1\tval2\tval3"),
        ("csv", "name,age,city\nAlice,30,New York\nBob,25,San Francisco"),
        ("sh", "#!/bin/bash\necho 'hello world'\nexit 0"),
        ("txt", "Simple plain text file\nSecond line."),
        ("json", "{\n  \"status\": \"ok\",\n  \"count\": 42\n}"),
        ("py", "def greet(name):\n    return f\"Hello, {name}!\"\n")
    ]

    for format in formats {
        let fileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).\(format.ext)")
        try format.content.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let doc = try VimMDDocument(contentsOf: fileURL, ofType: "public.plain-text")
        guard let session = doc.session else {
            throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed initializing session for format .\(format.ext)"])
        }
        guard session.serializeBuffer() == format.content else {
            throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Content mismatch for format .\(format.ext): expected '\(format.content)', got '\(session.serializeBuffer())'"])
        }
    }
}

func testDesignatedInitializers() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let tempURL = tempDir.appendingPathComponent("init_test_\(UUID().uuidString).md")
    try "Init Content".write(to: tempURL, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    // 1. init(contentsOf:ofType:)
    let docFromURL = try VimMDDocument(contentsOf: tempURL, ofType: "public.plain-text")
    guard docFromURL.session != nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "session was nil after init(contentsOf:ofType:)"])
    }
    guard docFromURL.session?.serializeBuffer() == "Init Content" else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Buffer mismatch after init(contentsOf:ofType:)"])
    }

    // 2. init(type:)
    let docFromType = try VimMDDocument(type: "public.plain-text")
    guard docFromType.session != nil else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "session was nil after init(type:)"])
    }
}

func testBinaryContainsVimMDDocumentSymbol() throws {
    let rootPath = FileManager.default.currentDirectoryPath
    let binaryPath = "\(rootPath)/build/VimMD.app/Contents/MacOS/VimMD"
    guard FileManager.default.fileExists(atPath: binaryPath) else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary does not exist at \(binaryPath)"])
    }

    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nm")
    process.arguments = [binaryPath]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard output.contains("VimMDDocument") else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Binary at \(binaryPath) does NOT contain VimMDDocument symbol! Dead-stripped or missing link."])
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

func testDocumentExSaveAndQuitActions() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("ex_test_\(UUID().uuidString).md")
    defer {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // 1. :w triggers save and clears dirty
    try "Original File".write(to: fileURL, atomically: true, encoding: .utf8)
    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "public.plain-text")
    doc.makeWindowControllers()
    doc.session?.feedKeys("iMutated \u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document should be edited"])
    }
    doc.session?.feedKeys(":w\r")
    guard !doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: ":w should save and clear dirty"])
    }
    let diskContentAfterW = try String(contentsOf: fileURL, encoding: .utf8)
    guard diskContentAfterW.hasPrefix("Mutated Original") else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected disk content to update after :w, got \(diskContentAfterW)"])
    }

    // 2. :q refuses to close dirty document
    doc.session?.feedKeys("iMoreChanges\u{1b}")
    guard doc.isDocumentEdited else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Document should be edited again"])
    }
    doc.session?.feedKeys(":q\r")
    guard !doc.isClosed else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: ":q must not close a dirty document!"])
    }

    // 3. :q! closes dirty document without saving
    doc.session?.feedKeys(":q!\r")
    guard doc.isClosed else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: ":q! should close dirty document"])
    }
    let diskContentAfterQBang = try String(contentsOf: fileURL, encoding: .utf8)
    guard !diskContentAfterQBang.contains("MoreChanges") else {
        throw NSError(domain: "AppTests", code: 7, userInfo: [NSLocalizedDescriptionKey: ":q! should NOT save changes to disk"])
    }

    // 4. :e! reloads disk contents
    let doc2 = try VimMDDocument(contentsOf: fileURL, ofType: "public.plain-text")
    doc2.makeWindowControllers()
    try "Externally Modified Disk Content".write(to: fileURL, atomically: true, encoding: .utf8)
    doc2.session?.feedKeys(":e!\r")
    guard doc2.session?.serializeBuffer() == "Externally Modified Disk Content" else {
        throw NSError(domain: "AppTests", code: 8, userInfo: [NSLocalizedDescriptionKey: ":e! should reload contents from disk"])
    }

    // 5. :wq saves then closes
    doc2.session?.feedKeys("iNewText \u{1b}")
    doc2.session?.feedKeys(":wq\r")
    guard doc2.isClosed else {
        throw NSError(domain: "AppTests", code: 9, userInfo: [NSLocalizedDescriptionKey: ":wq should close document"])
    }
    let diskContentAfterWQ = try String(contentsOf: fileURL, encoding: .utf8)
    guard diskContentAfterWQ.hasPrefix("NewText ") else {
        throw NSError(domain: "AppTests", code: 10, userInfo: [NSLocalizedDescriptionKey: ":wq should save before closing"])
    }
}

func testStatusBarWriteUntitledFeedback() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    guard doc.fileURL == nil else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected fileURL to be nil for new untitled doc"])
    }

    doc.session?.feedKeys(":w\r")
    guard let msg = doc.currentStatusMessage, msg.contains("E32: No file name") else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected status message with 'E32: No file name', got '\(String(describing: doc.currentStatusMessage))'"])
    }
    guard doc.isCurrentStatusMessageWarning else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected status message to be flagged as warning"])
    }
    guard doc.messageLabel?.stringValue.contains("E32: No file name") == true else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected messageLabel to show 'E32: No file name', got '\(String(describing: doc.messageLabel?.stringValue))'"])
    }
}

func testStatusBarWriteSuccessFeedback() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("status_save_test_\(UUID().uuidString).md")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    try "Line 1\nLine 2\nLine 3".write(to: fileURL, atomically: true, encoding: .utf8)
    let doc = try VimMDDocument(contentsOf: fileURL, ofType: "public.plain-text")
    doc.makeWindowControllers()

    doc.session?.feedKeys("iUpdated \u{1b}")
    doc.session?.feedKeys(":w\r")

    guard let msg = doc.currentStatusMessage else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected currentStatusMessage after successful write"])
    }
    guard msg.contains("written") && msg.contains(fileURL.lastPathComponent) else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected write confirmation with filename and 'written', got '\(msg)'"])
    }
    guard msg.contains("3L") || msg.contains("L,") else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected line count indicator in write message: '\(msg)'"])
    }
    guard !doc.isCurrentStatusMessageWarning else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Successful write should not be marked as warning"])
    }
}

func testStatusBarShowsLastErrorOnBlockedQuit() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    doc.session?.feedKeys("iChange\u{1b}")
    guard doc.session?.isDirty == true else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session should be dirty"])
    }

    // Attempting :q on dirty doc
    doc.session?.feedKeys(":q\r")
    guard !doc.isClosed else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Document should not close"])
    }

    guard let msg = doc.currentStatusMessage, msg.contains("E37") else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected status message with 'E37', got '\(String(describing: doc.currentStatusMessage))'"])
    }
    guard doc.isCurrentStatusMessageWarning else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected status message to be warning"])
    }
}

func testShowStatusMessageMethod() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()
    doc.showStatusMessage("Test Status Alert", isWarning: true)

    guard doc.currentStatusMessage == "Test Status Alert" else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Status message not recorded"])
    }
    guard doc.isCurrentStatusMessageWarning else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Status message should be warning"])
    }
    guard doc.messageLabel?.stringValue == "Test Status Alert" else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "messageLabel not updated"])
    }
}

func testDocumentScrollViewDynamicHeightAndScroller() throws {
    let doc = VimMDDocument()
    let multiline = (1...100).map { "## Section \($0)\nThis is multiline markdown paragraph number \($0)." }.joined(separator: "\n")
    guard let data = multiline.data(using: .utf8) else {
        throw NSError(domain: "AppTests", code: 1, userInfo: nil)
    }
    try doc.read(from: data, ofType: "public.plain-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView not created"])
    }
    guard let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Enclosing scroll view not found"])
    }

    guard scrollView.hasVerticalScroller else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "ScrollView vertical scroller should be enabled"])
    }

    // TextView frame height must accurately expand to accommodate 100 lines (> 1000pt)
    guard tv.frame.size.height > scrollView.contentSize.height else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "TextView frame height \(tv.frame.size.height) did not expand past scroll view content height \(scrollView.contentSize.height)"])
    }
}

func testDocumentLineNumberRulerConfiguration() throws {
    let doc = VimMDDocument()
    doc.makeWindowControllers()

    guard let windowController = doc.windowControllers.first,
          let window = windowController.window,
          let contentView = window.contentView else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Window hierarchy missing"])
    }

    var foundScrollView: NSScrollView?
    func findScrollView(in view: NSView) {
        if let sv = view as? NSScrollView {
            foundScrollView = sv
            return
        }
        for sub in view.subviews {
            findScrollView(in: sub)
        }
    }
    findScrollView(in: contentView)

    guard let scrollView = foundScrollView else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "NSScrollView not found in document window"])
    }

    guard scrollView.hasVerticalRuler else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "scrollView.hasVerticalRuler is false"])
    }
    guard scrollView.rulersVisible else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "scrollView.rulersVisible is false"])
    }
    guard scrollView.verticalRulerView is LineNumberRulerView else {
        throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "scrollView.verticalRulerView is not LineNumberRulerView"])
    }
}

func testDocumentTabularSyntaxIntegration() throws {
    // 1. CSV Document
    let csvDoc = VimMDDocument()
    csvDoc.fileURL = URL(fileURLWithPath: "/tmp/test.csv")
    csvDoc.fileType = "public.comma-separated-values-text"
    let csvData = "col1,col2\nval1,val2".data(using: .utf8)!
    try csvDoc.read(from: csvData, ofType: "public.comma-separated-values-text")
    csvDoc.makeWindowControllers()

    guard let csvTv = csvDoc.textView else {
        throw NSError(domain: "AppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV textView nil"])
    }
    guard csvTv.isTabularDocument else {
        throw NSError(domain: "AppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected isTabularDocument == true for CSV"])
    }
    guard !csvTv.isTSV else {
        throw NSError(domain: "AppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected isTSV == false for CSV"])
    }
    guard csvTv.wrapLines else {
        throw NSError(domain: "AppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected wrapLines == true for CSV"])
    }

    // Check header styling in textStorage
    if let storage = csvTv.textStorage {
        let f0 = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        guard let font0 = f0, NSFontManager.shared.traits(of: font0).contains(.boldFontMask) else {
            throw NSError(domain: "AppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected bold font on CSV header in textView"])
        }
    }

    // 2. TSV Document
    let tsvDoc = VimMDDocument()
    tsvDoc.fileURL = URL(fileURLWithPath: "/tmp/test.tsv")
    tsvDoc.fileType = "public.tab-separated-values-text"
    let tsvData = "colA\tcolB\nvalA\tvalB".data(using: .utf8)!
    try tsvDoc.read(from: tsvData, ofType: "public.tab-separated-values-text")
    tsvDoc.makeWindowControllers()

    guard let tsvTv = tsvDoc.textView else {
        throw NSError(domain: "AppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "TSV textView nil"])
    }
    guard tsvTv.isTabularDocument else {
        throw NSError(domain: "AppTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected isTabularDocument == true for TSV"])
    }
    guard tsvTv.isTSV else {
        throw NSError(domain: "AppTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected isTSV == true for TSV"])
    }

    // 3. Markdown Document
    let mdDoc = VimMDDocument()
    mdDoc.fileURL = URL(fileURLWithPath: "/tmp/test.md")
    mdDoc.fileType = "net.daringfireball.markdown"
    let mdData = "# Header\nHello".data(using: .utf8)!
    try mdDoc.read(from: mdData, ofType: "net.daringfireball.markdown")
    mdDoc.makeWindowControllers()

    guard let mdTv = mdDoc.textView else {
        throw NSError(domain: "AppTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "MD textView nil"])
    }
    guard !mdTv.isTabularDocument else {
        throw NSError(domain: "AppTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected isTabularDocument == false for MD"])
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
    ("testDocumentLossyDecoding", testDocumentLossyDecoding),
    ("testInfoPlistDocumentExtensions", testInfoPlistDocumentExtensions),
    ("testDesignatedInitializers", testDesignatedInitializers),
    ("testBinaryContainsVimMDDocumentSymbol", testBinaryContainsVimMDDocumentSymbol),
    ("testMultipleCommonFileFormats", testMultipleCommonFileFormats),
    ("testAppDelegateMenuBarSetup", testAppDelegateMenuBarSetup),
    ("testDefaultInitHasSession", testDefaultInitHasSession),
    ("testObjCRuntimeClassName", testObjCRuntimeClassName),
    ("testAppDelegateShouldOpenUntitledFile", testAppDelegateShouldOpenUntitledFile),
    ("testDocumentExSaveAndQuitActions", testDocumentExSaveAndQuitActions),
    ("testStatusBarWriteUntitledFeedback", testStatusBarWriteUntitledFeedback),
    ("testStatusBarWriteSuccessFeedback", testStatusBarWriteSuccessFeedback),
    ("testStatusBarShowsLastErrorOnBlockedQuit", testStatusBarShowsLastErrorOnBlockedQuit),
    ("testShowStatusMessageMethod", testShowStatusMessageMethod),
    ("testDocumentScrollViewDynamicHeightAndScroller", testDocumentScrollViewDynamicHeightAndScroller),
    ("testDocumentLineNumberRulerConfiguration", testDocumentLineNumberRulerConfiguration),
    ("testDocumentTabularSyntaxIntegration", testDocumentTabularSyntaxIntegration)
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
