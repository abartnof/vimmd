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

func testViewMenuContainsZoomItems() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let mainMenu = NSApplication.shared.mainMenu,
          let viewItem = mainMenu.items.first(where: { $0.submenu?.title == "View" }),
          let viewMenu = viewItem.submenu else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "View menu not found in main menu"])
    }

    // Check zoomInMenuItem
    guard let zoomIn = viewMenu.items.first(where: { $0.title == "Zoom In" }) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Zoom In menu item missing"])
    }
    guard zoomIn.action == Selector(("zoomIn:")) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Zoom In action mismatch: \(String(describing: zoomIn.action))"])
    }
    guard zoomIn.keyEquivalent == "+" || zoomIn.keyEquivalent == "=" else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Zoom In keyEquivalent mismatch: \(zoomIn.keyEquivalent)"])
    }
    guard zoomIn.keyEquivalentModifierMask == [.command] else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Zoom In modifiers mismatch"])
    }

    // Check zoomOutMenuItem
    guard let zoomOut = viewMenu.items.first(where: { $0.title == "Zoom Out" }) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Zoom Out menu item missing"])
    }
    guard zoomOut.action == Selector(("zoomOut:")) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Zoom Out action mismatch: \(String(describing: zoomOut.action))"])
    }
    guard zoomOut.keyEquivalent == "-" else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Zoom Out keyEquivalent mismatch: \(zoomOut.keyEquivalent)"])
    }
    guard zoomOut.keyEquivalentModifierMask == [.command] else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Zoom Out modifiers mismatch"])
    }

    // Check actualSizeMenuItem
    guard let actualSize = viewMenu.items.first(where: { $0.title == "Actual Size" }) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Actual Size menu item missing"])
    }
    guard actualSize.action == Selector(("actualSize:")) else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Actual Size action mismatch: \(String(describing: actualSize.action))"])
    }
    guard actualSize.keyEquivalent == "0" else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Actual Size keyEquivalent mismatch: \(actualSize.keyEquivalent)"])
    }
    guard actualSize.keyEquivalentModifierMask == [.command] else {
        throw NSError(domain: "ViewportZoomMenuTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Actual Size modifiers mismatch"])
    }
}

let tests = [
    ("testViewMenuContainsZoomItems", testViewMenuContainsZoomItems)
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
