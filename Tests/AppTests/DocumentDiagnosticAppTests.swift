import Foundation
import AppKit
import Engine
import Views
import App
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

// 1. VimMDDocument detects malformed CSV and displays warning in messageLabel
func testDocumentDisplaysDiagnosticInStatusBar() throws {
    let doc = VimMDDocument()
    let badCSV = "HeaderA,HeaderB\nValA,\"ValB\nValC,ValD"
    try doc.read(from: badCSV.data(using: .utf8)!, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    guard let label = doc.messageLabel else {
        throw NSError(domain: "DocDiagAppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "messageLabel was nil"])
    }

    guard label.stringValue.contains("[Warning] Unclosed quote at line 2") else {
        throw NSError(domain: "DocDiagAppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected unclosed quote warning in messageLabel, got: '\(label.stringValue)'"])
    }

    guard label.textColor == NSColor.systemOrange else {
        throw NSError(domain: "DocDiagAppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected systemOrange textColor, got: \(String(describing: label.textColor))"])
    }

    doc.close()
}

// 2. ValidateMenuItem retains normal operations
func testValidateMenuItemRetainsOperations() throws {
    let doc = VimMDDocument()
    let text = "HeaderA,HeaderB\n1,2"
    try doc.read(from: text.data(using: .utf8)!, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    let itemWrap = NSMenuItem(title: "Wrap Lines", action: #selector(doc.toggleWrapLines(_:)), keyEquivalent: "")
    let itemFreezeRow = NSMenuItem(title: "Freeze Row", action: #selector(doc.toggleFreezeFirstRow(_:)), keyEquivalent: "")
    let itemFreezeCol = NSMenuItem(title: "Freeze Col", action: #selector(doc.toggleFreezeFirstColumn(_:)), keyEquivalent: "")
    let itemWrapCells = NSMenuItem(title: "Wrap Cells", action: #selector(doc.toggleWrapTableCells(_:)), keyEquivalent: "")

    guard doc.validateMenuItem(itemWrap) else {
        throw NSError(domain: "DocDiagAppTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "toggleWrapLines validation failed"])
    }
    guard doc.validateMenuItem(itemFreezeRow) else {
        throw NSError(domain: "DocDiagAppTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "toggleFreezeFirstRow validation failed"])
    }
    guard doc.validateMenuItem(itemFreezeCol) else {
        throw NSError(domain: "DocDiagAppTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "toggleFreezeFirstColumn validation failed"])
    }
    guard doc.validateMenuItem(itemWrapCells) else {
        throw NSError(domain: "DocDiagAppTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "toggleWrapTableCells validation failed"])
    }

    doc.close()
}

// 3. Clean CSV shows no diagnostic message
func testCleanDocumentShowsNoDiagnostic() throws {
    let doc = VimMDDocument()
    try doc.read(from: "A,B\n1,2\n3,4\n".data(using: .utf8)!, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()
    guard doc.pendingLoadDiagnostics.isEmpty else {
        throw NSError(domain: "DocDiagAppTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Unexpected diagnostics: \(doc.pendingLoadDiagnostics)"])
    }
    guard !doc.isCurrentStatusMessageWarning, (doc.messageLabel?.stringValue ?? "").isEmpty else {
        throw NSError(domain: "DocDiagAppTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected empty status, got '\(doc.messageLabel?.stringValue ?? "nil")'"])
    }
    doc.close()
}

// 4. Clean re-read clears a stale load-diagnostic message
func testCleanRereadClearsStaleDiagnostic() throws {
    let doc = VimMDDocument()
    let type = "public.comma-separated-values-text"
    try doc.read(from: "A,B\n1,\"x\n2,3".data(using: .utf8)!, ofType: type)
    doc.makeWindowControllers()
    guard doc.messageLabel?.stringValue.contains("Unclosed quote") == true else {
        throw NSError(domain: "DocDiagAppTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "setup: expected warning"])
    }
    try doc.read(from: "A,B\n1,2\n".data(using: .utf8)!, ofType: type)
    guard (doc.messageLabel?.stringValue ?? "x").isEmpty, !doc.isCurrentStatusMessageWarning, doc.currentStatusMessage == "" else {
        throw NSError(domain: "DocDiagAppTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "stale message not cleared: '\(doc.messageLabel?.stringValue ?? "nil")'"])
    }
    doc.close()
}

// 5. Clean re-read must NOT clobber an unrelated message (e.g. save feedback)
func testCleanRereadKeepsUnrelatedMessage() throws {
    let doc = VimMDDocument()
    let type = "public.comma-separated-values-text"
    try doc.read(from: "A,B\n1,\"x\n2,3".data(using: .utf8)!, ofType: type)
    doc.makeWindowControllers()
    doc.showStatusMessage("\"f.csv\" 2L, 10B written", isWarning: false)
    try doc.read(from: "A,B\n1,2\n".data(using: .utf8)!, ofType: type)
    guard doc.messageLabel?.stringValue == "\"f.csv\" 2L, 10B written" else {
        throw NSError(domain: "DocDiagAppTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "unrelated message clobbered: '\(doc.messageLabel?.stringValue ?? "nil")'"])
    }
    doc.close()
}

let tests: [(String, () throws -> Void)] = [
    ("testDocumentDisplaysDiagnosticInStatusBar", testDocumentDisplaysDiagnosticInStatusBar),
    ("testValidateMenuItemRetainsOperations", testValidateMenuItemRetainsOperations),
    ("testCleanDocumentShowsNoDiagnostic", testCleanDocumentShowsNoDiagnostic),
    ("testCleanRereadClearsStaleDiagnostic", testCleanRereadClearsStaleDiagnostic),
    ("testCleanRereadKeepsUnrelatedMessage", testCleanRereadKeepsUnrelatedMessage)
]

print("=== DocumentDiagnosticAppTests ===")
var passed = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passed += 1
    }
}
print("Result: \(passed)/\(tests.count) tests passed.")
if passed != tests.count {
    exit(1)
}
