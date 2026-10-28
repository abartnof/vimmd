import Foundation
import AppKit
import App

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

func testOpenFileSetsLaunchFlagAndSuppressesPicker() throws {
    let appDelegate = AppDelegate()
    guard !appDelegate.hasLaunchedWithTargetFile else {
        throw NSError(domain: "FinderLaunchTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "hasLaunchedWithTargetFile should initially be false"])
    }

    let fakePath = "/tmp/test_vimmd_sample.md"
    let handled = appDelegate.application(NSApplication.shared, openFile: fakePath)
    guard handled else {
        throw NSError(domain: "FinderLaunchTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "application(_:openFile:) returned false"])
    }

    guard appDelegate.hasLaunchedWithTargetFile else {
        throw NSError(domain: "FinderLaunchTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "hasLaunchedWithTargetFile was not set to true after openFile"])
    }
    guard appDelegate.hasOpenedDocument else {
        throw NSError(domain: "FinderLaunchTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "hasOpenedDocument was not set to true after openFile"])
    }
}

func testLaunchWithTargetFileSuppressesOpenPicker() throws {
    let appDelegate = AppDelegate()
    appDelegate.hasLaunchedWithTargetFile = true

    // Post launch notification
    let note = Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApplication.shared)
    appDelegate.applicationDidFinishLaunching(note)

    // Drain main runloop to process any deferred blocks
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

    guard appDelegate.openDocumentInvokedCount == 0 else {
        throw NSError(domain: "FinderLaunchTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "openDocument(nil) should NOT be presented when hasLaunchedWithTargetFile is true"])
    }
}

func testLaunchWithoutTargetFilePresentsOpenPickerWhenEmpty() throws {
    let appDelegate = AppDelegate()
    appDelegate.hasLaunchedWithTargetFile = false

    let note = Notification(name: NSApplication.didFinishLaunchingNotification, object: NSApplication.shared)
    appDelegate.applicationDidFinishLaunching(note)

    // Drain main runloop
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

    guard appDelegate.openDocumentInvokedCount == 1 else {
        throw NSError(domain: "FinderLaunchTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "openDocument(nil) should be presented when no files targeted and documents empty, count: \(appDelegate.openDocumentInvokedCount)"])
    }
}

let tests = [
    ("testOpenFileSetsLaunchFlagAndSuppressesPicker", testOpenFileSetsLaunchFlagAndSuppressesPicker),
    ("testLaunchWithTargetFileSuppressesOpenPicker", testLaunchWithTargetFileSuppressesOpenPicker),
    ("testLaunchWithoutTargetFilePresentsOpenPickerWhenEmpty", testLaunchWithoutTargetFilePresentsOpenPickerWhenEmpty),
]

var passedCount = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passedCount += 1
    } else {
        exit(1)
    }
}
print("Result: \(passedCount)/\(tests.count) tests passed.")
