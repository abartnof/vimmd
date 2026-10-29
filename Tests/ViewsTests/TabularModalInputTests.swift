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

func sendKey(_ tv: VimMDTextView, char: String, keyCode: UInt16 = 0, modifierFlags: NSEvent.ModifierFlags = []) {
    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifierFlags,
        timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0,
        context: nil,
        characters: char,
        charactersIgnoringModifiers: char,
        isARepeat: false,
        keyCode: keyCode
    )!
    tv.keyDown(with: event)
}

func sendMouseClick(_ tv: VimMDTextView, at point: NSPoint) {
    let windowPoint = tv.convert(point, to: nil)
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowPoint,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: tv.window?.windowNumber ?? 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    tv.mouseDown(with: event)
}

// 1. Tabular Mouse Down Acquires First Responder & Positions Caret
func testTabularMouseDownAcquiresFirstResponder() throws {
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    let dummyView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csvContent = "ColA,ColB,ColC\n10,20,30\n100,200,300\n"
    let session = VimSession(initialText: csvContent)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    container.addSubview(dummyView)
    container.addSubview(tv)
    window.contentView = container

    // Start with dummyView having firstResponder
    window.makeFirstResponder(dummyView)
    guard window.firstResponder === dummyView else {
        throw NSError(domain: "TabularModalInputTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial first responder must be dummyView"])
    }

    // 1a. Click in Header Row 0 (Col B)
    guard let row0 = tv.rowRect(for: 0), let col1 = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularModalInputTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing rects for row 0 / col 1"])
    }
    let ptRow0 = NSPoint(x: col1.midX, y: row0.midY)
    sendMouseClick(tv, at: ptRow0)

    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Clicking in header Row 0 must make tv first responder, got \(String(describing: window.firstResponder))"])
    }
    // Caret should be positioned at Col B in header row (line 1)
    guard session.cursorPosition.line == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected cursor line 1, got \(session.cursorPosition.line)"])
    }

    // 1b. Reset to dummyView and click in Column A (Row 1)
    window.makeFirstResponder(dummyView)
    guard window.firstResponder === dummyView else {
        throw NSError(domain: "TabularModalInputTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to reset first responder to dummyView"])
    }

    guard let row1 = tv.rowRect(for: 1), let col0 = tv.columnRect(for: 0) else {
        throw NSError(domain: "TabularModalInputTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing rects for row 1 / col 0"])
    }
    let ptColA = NSPoint(x: col0.midX, y: row1.midY)
    sendMouseClick(tv, at: ptColA)

    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Clicking in Column A must make tv first responder, got \(String(describing: window.firstResponder))"])
    }
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at Line 2, Col 1, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }

    // 1c. Direct call to handleTabularMouseDown must also acquire first responder
    window.makeFirstResponder(dummyView)
    _ = tv.handleTabularMouseDown(at: ptColA)
    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Direct handleTabularMouseDown must make tv first responder, got \(String(describing: window.firstResponder))"])
    }

    // 1d. Click in body cell (Row 1, Col 1 / Col B) must make tv first responder and place caret directly
    window.makeFirstResponder(dummyView)
    guard let col1Body = tv.columnRect(for: 1) else {
        throw NSError(domain: "TabularModalInputTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Missing col 1"])
    }
    let ptBody = NSPoint(x: col1Body.midX, y: row1.midY)
    sendMouseClick(tv, at: ptBody)
    guard window.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "Clicking in body cell must make tv first responder, got \(String(describing: window.firstResponder))"])
    }
    // "10,20,30\n" -> "20" starts at 0-based offset 3, so Vim byteCol is 4 on Line 2
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 4 else {
        throw NSError(domain: "TabularModalInputTests", code: 93, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at Line 2, Col 4, got Line \(session.cursorPosition.line), Col \(session.cursorPosition.byteCol)"])
    }
}

// 2. Tabular Caret Placement and Selection Mapping Accuracy
func testTabularCaretPlacementAccuracy() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csvContent = "First,Second,Third\nAlpha,Beta,Gamma\nOne,Two,Three\n"
    let session = VimSession(initialText: csvContent)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Position at Row 2, Column 1 ("Two")
    tv.positionCaret(atRow: 2, column: 1)
    guard session.cursorPosition.line == 3 else {
        throw NSError(domain: "TabularModalInputTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected cursor line 3, got \(session.cursorPosition.line)"])
    }
    // "Two" begins after "One," in line 3
    guard session.cursorPosition.byteCol == 5 else {
        throw NSError(domain: "TabularModalInputTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected cursor col 5 ('Two'), got \(session.cursorPosition.byteCol)"])
    }

    // Position at Row 1, Column 0 ("Alpha")
    tv.positionCaret(atRow: 1, column: 0)
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected cursor line 2 col 1 ('Alpha'), got Line \(session.cursorPosition.line) Col \(session.cursorPosition.byteCol)"])
    }

    // Position at Row 0, Column 2 ("Third")
    tv.positionCaret(atRow: 0, column: 2)
    guard session.cursorPosition.line == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected cursor line 1, got \(session.cursorPosition.line)"])
    }
    // "First,Second,Third" -> 0-based index of 'Third' is 13, 1-based col is 14
    guard session.cursorPosition.byteCol == 14 else {
        throw NSError(domain: "TabularModalInputTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected cursor col 14 ('Third'), got \(session.cursorPosition.byteCol)"])
    }
}

// 3. Tabular Vim Motions Parity (h, j, k, l, w, b, e, ge, 0, ^, $, gg, G, f, t)
func testTabularMotionsParity() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csv = "ID,Name,Role\n1,Alice,Engineer\n2,Bob,Designer\n3,Charlie,Product"
    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Start at top (1,1)
    sendKey(tv, char: "g")
    sendKey(tv, char: "g")
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "gg motion failed"])
    }

    // j moves down to line 2
    sendKey(tv, char: "j")
    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "TabularModalInputTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "j motion failed"])
    }

    // 2j moves down to line 4
    sendKey(tv, char: "2")
    sendKey(tv, char: "j")
    guard session.cursorPosition.line == 4 else {
        throw NSError(domain: "TabularModalInputTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "2j motion failed"])
    }

    // k moves up to line 3
    sendKey(tv, char: "k")
    guard session.cursorPosition.line == 3 else {
        throw NSError(domain: "TabularModalInputTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "k motion failed"])
    }

    // $ moves to end of line
    sendKey(tv, char: "$")
    guard session.cursorPosition.byteCol > 10 else {
        throw NSError(domain: "TabularModalInputTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "$ motion failed"])
    }

    // 0 moves to start of line
    sendKey(tv, char: "0")
    guard session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "0 motion failed"])
    }

    // w moves forward words
    sendKey(tv, char: "w")
    guard session.cursorPosition.byteCol > 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "w motion failed"])
    }

    // G moves to bottom line
    sendKey(tv, char: "G")
    guard session.cursorPosition.line == 4 else {
        throw NSError(domain: "TabularModalInputTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "G motion failed"])
    }
}

// 4. Tabular Mutations Parity (x, s, r, cw, cc, c$, dd, dw, d$, yy, p, P, J)
func testTabularMutationsParity() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csv = "ColA,ColB\n11,22\n33,44"
    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Delete character with x at (1,1)
    sendKey(tv, char: "g")
    sendKey(tv, char: "g")
    sendKey(tv, char: "x")
    guard tv.string.hasPrefix("olA,ColB") else {
        throw NSError(domain: "TabularModalInputTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "x mutation failed, got '\(tv.string)'"])
    }

    // Delete line with dd
    sendKey(tv, char: "d")
    sendKey(tv, char: "d")
    guard !tv.string.contains("olA") && tv.string.hasPrefix("11,22") else {
        throw NSError(domain: "TabularModalInputTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "dd mutation failed, got '\(tv.string)'"])
    }

    // Yank line and paste with yy and p
    sendKey(tv, char: "y")
    sendKey(tv, char: "y")
    sendKey(tv, char: "p")
    guard tv.string.components(separatedBy: "\n").filter({ $0 == "11,22" }).count == 2 else {
        throw NSError(domain: "TabularModalInputTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "yy/p failed, got '\(tv.string)'"])
    }

    // Join lines with J
    sendKey(tv, char: "g")
    sendKey(tv, char: "g")
    sendKey(tv, char: "J")
    guard tv.string.hasPrefix("11,22 11,22") else {
        throw NSError(domain: "TabularModalInputTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "J mutation failed, got '\(tv.string)'"])
    }
}

// 5. Tabular Modal Transitions & Undo/Redo (i, a, o, u, Ctrl-R)
func testTabularModalTransitionsAndUndoRedo() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .tsv
    tv.isTabularDocument = true
    tv.isTSV = true

    let tsv = "Col1\tCol2\nRow1Val1\tRow1Val2\n"
    let session = VimSession(initialText: tsv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Insert mode at top
    sendKey(tv, char: "g")
    sendKey(tv, char: "g")
    sendKey(tv, char: "i")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "TabularModalInputTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "i key failed to enter INSERT mode"])
    }

    // Type text and Esc back to normal
    sendKey(tv, char: "PREFIX_")
    sendKey(tv, char: "\u{1b}", keyCode: 53)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "TabularModalInputTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Esc failed to return to NORMAL mode"])
    }
    guard tv.string.contains("PREFIX_Col1") else {
        throw NSError(domain: "TabularModalInputTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Insert failed, got '\(tv.string)'"])
    }

    // Undo with u
    sendKey(tv, char: "u")
    guard !tv.string.contains("PREFIX_") && tv.string.contains("Col1\tCol2") else {
        throw NSError(domain: "TabularModalInputTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Undo failed, got '\(tv.string)'"])
    }

    // Redo with Ctrl-R
    sendKey(tv, char: "\u{12}", keyCode: 15, modifierFlags: [.control])
    guard tv.string.contains("PREFIX_Col1") else {
        throw NSError(domain: "TabularModalInputTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Redo failed, got '\(tv.string)'"])
    }
}

// 6. Tabular Ex Commands (:%s/old/new/g, :sort, /search)
func testTabularExCommands() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csv = "Name,Score\nZebra,85\nApple,92\nMango,77\n"
    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Substitute Apple with Apricot via :%s/Apple/Apricot/g
    sendKey(tv, char: ":")
    sendKey(tv, char: "%")
    sendKey(tv, char: "s")
    sendKey(tv, char: "/")
    sendKey(tv, char: "Apple")
    sendKey(tv, char: "/")
    sendKey(tv, char: "Apricot")
    sendKey(tv, char: "/")
    sendKey(tv, char: "g")
    sendKey(tv, char: "\r", keyCode: 36)

    guard tv.string.contains("Apricot,92") && !tv.string.contains("Apple") else {
        throw NSError(domain: "TabularModalInputTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Ex substitute failed, got '\(tv.string)'"])
    }

    // Sort lines 2 to 4 via :2,4sort
    sendKey(tv, char: ":")
    sendKey(tv, char: "2")
    sendKey(tv, char: ",")
    sendKey(tv, char: "4")
    sendKey(tv, char: "sort")
    sendKey(tv, char: "\r", keyCode: 36)

    let lines = tv.string.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard lines.count == 4 && lines[0] == "Name,Score" && lines[1] == "Apricot,92" && lines[2] == "Mango,77" && lines[3] == "Zebra,85" else {
        throw NSError(domain: "TabularModalInputTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Ex sort failed, got lines: \(lines)"])
    }
}

// 7. Window Controller Document Initialization Sets First Responder
func testDocumentMakeWindowControllersSetsFirstResponder() throws {
    let doc = VimMDDocument()
    let csvData = "A,B\n1,2\n".data(using: .utf8)!
    try doc.read(from: csvData, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    guard let winCtrl = doc.windowControllers.first, let win = winCtrl.window else {
        throw NSError(domain: "TabularModalInputTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Missing window controller or window"])
    }
    guard let tv = doc.textView else {
        throw NSError(domain: "TabularModalInputTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Missing textView in doc"])
    }

    guard win.initialFirstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "initialFirstResponder must be tv, got \(String(describing: win.initialFirstResponder))"])
    }
    guard win.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Window firstResponder must be tv, got \(String(describing: win.firstResponder))"])
    }
}

// 8. Linewise Paste at EOF on Documents with Trailing Newline
func testLinewisePasteAtEOFWithTrailingNewline() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    let csv = "ColA,ColB\n11,22\n33,44\n"
    let session = VimSession(initialText: csv)
    tv.session = session
    tv.updateSyntaxStyling(force: true)

    // Move to last data row (line 3) with 3G
    sendKey(tv, char: "3")
    sendKey(tv, char: "G")
    guard session.cursorPosition.line == 3 else {
        throw NSError(domain: "TabularModalInputTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Expected 3G to be at line 3, got \(session.cursorPosition.line)"])
    }

    // Yank line 3 with yy
    sendKey(tv, char: "y")
    sendKey(tv, char: "y")

    // Paste below with p at EOF of data lines
    sendKey(tv, char: "p")

    let expected = session.serializeBuffer()
    guard tv.string == expected else {
        throw NSError(domain: "TabularModalInputTests", code: 71, userInfo: [NSLocalizedDescriptionKey: "tv.string must match session.serializeBuffer() at EOF paste. Expected:\n'\(expected)'\nGot:\n'\(tv.string)'"])
    }

    // Assert zero phantom blank lines
    let lines = tv.string.components(separatedBy: "\n")
    guard lines.count == 5 && lines[2] == "33,44" && lines[3] == "33,44" && lines[4] == "" else {
        throw NSError(domain: "TabularModalInputTests", code: 72, userInfo: [NSLocalizedDescriptionKey: "Unexpected line structure after EOF linewise paste: \(lines)"])
    }
}

// 9. Boundary Cases for positionCaret(atRow:column:)
func testPositionCaretBoundaryCases() throws {
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    tv.documentSyntaxType = .csv
    tv.isTabularDocument = true
    tv.isTSV = false

    // 1. Empty buffer
    let emptySession = VimSession(initialText: "")
    tv.session = emptySession
    tv.updateSyntaxStyling(force: true)
    tv.positionCaret(atRow: 0, column: 0)
    guard tv.selectedRange().location == 0 && emptySession.cursorPosition.line == 1 && emptySession.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 80, userInfo: [NSLocalizedDescriptionKey: "Empty buffer caret positioning failed"])
    }

    // 2. Multibyte characters and emojis: "ID,Name\n1,🚀Rocket\n"
    let emojiCsv = "ID,Name\n1,🚀Rocket\n"
    let emojiSession = VimSession(initialText: emojiCsv)
    tv.session = emojiSession
    tv.updateSyntaxStyling(force: true)
    tv.positionCaret(atRow: 1, column: 1)
    guard emojiSession.cursorPosition.line == 2 && emojiSession.cursorPosition.byteCol == 3 else {
        throw NSError(domain: "TabularModalInputTests", code: 81, userInfo: [NSLocalizedDescriptionKey: "Emoji cell caret positioning failed, got Line \(emojiSession.cursorPosition.line), Col \(emojiSession.cursorPosition.byteCol)"])
    }

    // 3. Sparse empty cells: "A,,C\n1,,3\n"
    let sparseCsv = "A,,C\n1,,3\n"
    let sparseSession = VimSession(initialText: sparseCsv)
    tv.session = sparseSession
    tv.updateSyntaxStyling(force: true)
    tv.positionCaret(atRow: 0, column: 1) // empty middle cell in header
    guard sparseSession.cursorPosition.line == 1 && sparseSession.cursorPosition.byteCol == 3 else {
        throw NSError(domain: "TabularModalInputTests", code: 82, userInfo: [NSLocalizedDescriptionKey: "Sparse empty cell positioning failed, got Line \(sparseSession.cursorPosition.line), Col \(sparseSession.cursorPosition.byteCol)"])
    }

    // 4. Negative row / col clamping
    tv.positionCaret(atRow: -5, column: -2)
    guard sparseSession.cursorPosition.line == 1 && sparseSession.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "TabularModalInputTests", code: 83, userInfo: [NSLocalizedDescriptionKey: "Negative row/col clamping failed, got Line \(sparseSession.cursorPosition.line), Col \(sparseSession.cursorPosition.byteCol)"])
    }

    // 5. Out-of-bounds row / col clamping
    tv.positionCaret(atRow: 99, column: 99)
    guard sparseSession.cursorPosition.line == 2 else {
        throw NSError(domain: "TabularModalInputTests", code: 84, userInfo: [NSLocalizedDescriptionKey: "Out-of-bounds row clamping failed, got Line \(sparseSession.cursorPosition.line)"])
    }
}

// 10. VimMDDocument.read(from:ofType:) First Responder Continuity
func testDocumentReadFromDataSetsFirstResponder() throws {
    let doc = VimMDDocument()
    let csvData1 = "A,B\n1,2\n".data(using: .utf8)!
    try doc.read(from: csvData1, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    guard let winCtrl = doc.windowControllers.first, let win = winCtrl.window, let tv = doc.textView else {
        throw NSError(domain: "TabularModalInputTests", code: 90, userInfo: [NSLocalizedDescriptionKey: "Missing window or textView"])
    }

    // Lose focus to another view
    let dummy = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    win.contentView?.addSubview(dummy)
    win.makeFirstResponder(dummy)
    guard win.firstResponder === dummy else {
        throw NSError(domain: "TabularModalInputTests", code: 91, userInfo: [NSLocalizedDescriptionKey: "Failed to set dummy first responder"])
    }

    // Reload document via read(from:ofType:)
    let csvData2 = "Col1,Col2\nX,Y\n".data(using: .utf8)!
    try doc.read(from: csvData2, ofType: "public.comma-separated-values-text")

    guard win.firstResponder === tv else {
        throw NSError(domain: "TabularModalInputTests", code: 92, userInfo: [NSLocalizedDescriptionKey: "read(from:ofType:) must restore first responder to tv, got \(String(describing: win.firstResponder))"])
    }
}

// Main test runner
let tests: [(String, () throws -> Void)] = [
    ("testTabularMouseDownAcquiresFirstResponder", testTabularMouseDownAcquiresFirstResponder),
    ("testTabularCaretPlacementAccuracy", testTabularCaretPlacementAccuracy),
    ("testTabularMotionsParity", testTabularMotionsParity),
    ("testTabularMutationsParity", testTabularMutationsParity),
    ("testTabularModalTransitionsAndUndoRedo", testTabularModalTransitionsAndUndoRedo),
    ("testTabularExCommands", testTabularExCommands),
    ("testDocumentMakeWindowControllersSetsFirstResponder", testDocumentMakeWindowControllersSetsFirstResponder),
    ("testLinewisePasteAtEOFWithTrailingNewline", testLinewisePasteAtEOFWithTrailingNewline),
    ("testPositionCaretBoundaryCases", testPositionCaretBoundaryCases),
    ("testDocumentReadFromDataSetsFirstResponder", testDocumentReadFromDataSetsFirstResponder)
]

print("=== TabularModalInputTests ===")
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
