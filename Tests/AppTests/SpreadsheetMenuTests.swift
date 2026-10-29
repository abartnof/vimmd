import Foundation
import AppKit
import Engine
import Views
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

// 1. Spreadsheet Menu Items exist in View Menu
func testSpreadsheetMenuItemsExistInViewMenu() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    guard let viewMenuItem = appDelegate.viewMenuItem, let viewMenu = viewMenuItem.submenu else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "View menu missing"])
    }

    let itemTitles = viewMenu.items.map { $0.title }
    guard itemTitles.contains("Freeze First Row") else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Freeze First Row menu item missing"])
    }
    guard itemTitles.contains("Freeze First Column") else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Freeze First Column menu item missing"])
    }
    guard itemTitles.contains("Wrap Table Cells") else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Wrap Table Cells menu item missing"])
    }

    guard let freezeRowItem = appDelegate.freezeFirstRowMenuItem,
          let freezeColItem = appDelegate.freezeFirstColumnMenuItem,
          let wrapCellsItem = appDelegate.wrapTableCellsMenuItem else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "AppDelegate menuItem references missing"])
    }

    guard freezeRowItem.action == #selector(AppDelegate.toggleFreezeFirstRow(_:)) else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "freezeRowItem has wrong action"])
    }
    guard freezeColItem.action == #selector(AppDelegate.toggleFreezeFirstColumn(_:)) else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "freezeColItem has wrong action"])
    }
    guard wrapCellsItem.action == #selector(AppDelegate.toggleWrapTableCells(_:)) else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "wrapCellsItem has wrong action"])
    }
}

// 2. Format-Aware Validation: Enabled on CSV / TSV, Disabled on Markdown & Plain Text
func testFormatAwareMenuValidation() throws {
    let appDelegate = AppDelegate()
    appDelegate.setupMainMenu()

    let freezeRowItem = NSMenuItem(title: "Freeze First Row", action: #selector(VimMDDocument.toggleFreezeFirstRow(_:)), keyEquivalent: "")
    let freezeColItem = NSMenuItem(title: "Freeze First Column", action: #selector(VimMDDocument.toggleFreezeFirstColumn(_:)), keyEquivalent: "")
    let wrapCellsItem = NSMenuItem(title: "Wrap Table Cells", action: #selector(VimMDDocument.toggleWrapTableCells(_:)), keyEquivalent: "")

    // Case A: CSV Document -> must validate as true
    let csvDoc = VimMDDocument()
    let csvData = "a,b,c\n1,2,3\n".data(using: .utf8)!
    try csvDoc.read(from: csvData, ofType: "public.comma-separated-values-text")

    guard csvDoc.validateMenuItem(freezeRowItem) == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Expected freezeRowItem to be enabled for CSV"])
    }
    guard csvDoc.validateMenuItem(freezeColItem) == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected freezeColItem to be enabled for CSV"])
    }
    guard csvDoc.validateMenuItem(wrapCellsItem) == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Expected wrapCellsItem to be enabled for CSV"])
    }

    // Case B: TSV Document -> must validate as true
    let tsvDoc = VimMDDocument()
    let tsvData = "a\tb\tc\n1\t2\t3\n".data(using: .utf8)!
    try tsvDoc.read(from: tsvData, ofType: "public.tab-separated-values-text")

    guard tsvDoc.validateMenuItem(freezeRowItem) == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected freezeRowItem to be enabled for TSV"])
    }

    // Case C: Markdown Document -> must validate as false (greyed out)
    let mdDoc = VimMDDocument()
    let mdData = "# Hello World\nSome markdown text\n".data(using: .utf8)!
    try mdDoc.read(from: mdData, ofType: "net.daringfireball.markdown")

    guard mdDoc.validateMenuItem(freezeRowItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Expected freezeRowItem to be disabled for Markdown"])
    }
    guard mdDoc.validateMenuItem(freezeColItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected freezeColItem to be disabled for Markdown"])
    }
    guard mdDoc.validateMenuItem(wrapCellsItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected wrapCellsItem to be disabled for Markdown"])
    }

    // Case D: Plain Text Document -> must validate as false (greyed out)
    let txtDoc = VimMDDocument()
    let txtData = "plain text line 1\nline 2\n".data(using: .utf8)!
    try txtDoc.read(from: txtData, ofType: "public.plain-text")

    guard txtDoc.validateMenuItem(freezeRowItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Expected freezeRowItem to be disabled for Plain Text"])
    }
    guard txtDoc.validateMenuItem(freezeColItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "Expected freezeColItem to be disabled for Plain Text"])
    }
    guard txtDoc.validateMenuItem(wrapCellsItem) == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 29, userInfo: [NSLocalizedDescriptionKey: "Expected wrapCellsItem to be disabled for Plain Text"])
    }
}

// 3. Toggling freezeFirstRow, freezeFirstColumn, wrapTableCells
func testTogglingSpreadsheetProperties() throws {
    let doc = VimMDDocument()
    let csvData = "col1,col2\nval1,val2\n".data(using: .utf8)!
    try doc.read(from: csvData, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    let freezeRowItem = NSMenuItem(title: "Freeze First Row", action: #selector(VimMDDocument.toggleFreezeFirstRow(_:)), keyEquivalent: "")
    let freezeColItem = NSMenuItem(title: "Freeze First Column", action: #selector(VimMDDocument.toggleFreezeFirstColumn(_:)), keyEquivalent: "")
    let wrapCellsItem = NSMenuItem(title: "Wrap Table Cells", action: #selector(VimMDDocument.toggleWrapTableCells(_:)), keyEquivalent: "")

    // Initial states: false (off)
    guard doc.freezeFirstRow == false && doc.freezeFirstColumn == false && doc.wrapTableCells == false else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Initial properties should be false"])
    }
    _ = doc.validateMenuItem(freezeRowItem)
    guard freezeRowItem.state == .off else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Initial freezeRowItem state should be off"])
    }

    // Toggle Freeze First Row
    doc.toggleFreezeFirstRow(nil)
    guard doc.freezeFirstRow == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "freezeFirstRow should be true after toggle"])
    }
    _ = doc.validateMenuItem(freezeRowItem)
    guard freezeRowItem.state == .on else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "freezeRowItem state should be on after toggle"])
    }
    guard doc.textView?.freezeFirstRow == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "textView.freezeFirstRow should match doc"])
    }

    // Toggle Freeze First Column
    doc.toggleFreezeFirstColumn(nil)
    guard doc.freezeFirstColumn == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 35, userInfo: [NSLocalizedDescriptionKey: "freezeFirstColumn should be true after toggle"])
    }
    _ = doc.validateMenuItem(freezeColItem)
    guard freezeColItem.state == .on else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 36, userInfo: [NSLocalizedDescriptionKey: "freezeColItem state should be on after toggle"])
    }
    guard doc.textView?.freezeFirstColumn == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 37, userInfo: [NSLocalizedDescriptionKey: "textView.freezeFirstColumn should match doc"])
    }

    // Toggle Wrap Table Cells
    doc.toggleWrapTableCells(nil)
    guard doc.wrapTableCells == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 38, userInfo: [NSLocalizedDescriptionKey: "wrapTableCells should be true after toggle"])
    }
    _ = doc.validateMenuItem(wrapCellsItem)
    guard wrapCellsItem.state == .on else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 39, userInfo: [NSLocalizedDescriptionKey: "wrapCellsItem state should be on after toggle"])
    }
    guard doc.textView?.wrapTableCells == true else {
        throw NSError(domain: "SpreadsheetMenuTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "textView.wrapTableCells should match doc"])
    }
}

print("=== SpreadsheetMenu Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testSpreadsheetMenuItemsExistInViewMenu", testSpreadsheetMenuItemsExistInViewMenu),
    ("testFormatAwareMenuValidation", testFormatAwareMenuValidation),
    ("testTogglingSpreadsheetProperties", testTogglingSpreadsheetProperties)
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
