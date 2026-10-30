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

final class TestContext {
    let window: NSWindow
    let tv: VimMDTextView
    let session: VimSession

    init(text: String, isTSV: Bool = false, isTabular: Bool = true) {
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        if isTabular {
            self.tv.documentSyntaxType = isTSV ? .tsv : .csv
            self.tv.isTabularDocument = true
            self.tv.isTSV = isTSV
        } else {
            self.tv.documentSyntaxType = .plainText
            self.tv.isTabularDocument = false
            self.tv.isTSV = false
        }

        self.session = VimSession(initialText: text)
        self.tv.session = self.session
        self.tv.updateSyntaxStyling(force: true)

        self.window.contentView = self.tv
        self.window.makeFirstResponder(self.tv)
    }
}

// 1. Moving down (`j`) from a long field in row 0 to row 1 where corresponding field is short stays locked to the same cell column
func testMovingDownFromLongFieldToShortFieldStaysInSameColumn() throws {
    let csv = "ShortHeaderA,VeryLongColumnHeaderTitleThatSpansManyCharactersB,ColC\n1,2,3\n100,200,300\n"
    let ctx = TestContext(text: csv)

    // Position caret at Row 0, Column 1
    ctx.tv.positionCaret(atRow: 0, column: 1)
    guard let cell0 = ctx.tv.currentTabularCell() else {
        throw NSError(domain: "TabularVerticalNav", code: 1, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil"])
    }
    guard cell0.row == 0 && cell0.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 1), got (\(cell0.row), \(cell0.column))"])
    }

    // Press 'j' to go down to Row 1
    sendKey(ctx.tv, char: "j")

    guard let cell1 = ctx.tv.currentTabularCell() else {
        throw NSError(domain: "TabularVerticalNav", code: 3, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after j"])
    }
    guard cell1.row == 1 && cell1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 1), got (\(cell1.row), \(cell1.column)) after j"])
    }

    // Press 'j' again to go down to Row 2
    sendKey(ctx.tv, char: "j")

    guard let cell2 = ctx.tv.currentTabularCell() else {
        throw NSError(domain: "TabularVerticalNav", code: 5, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell returned nil after second j"])
    }
    guard cell2.row == 2 && cell2.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected cell (2, 1), got (\(cell2.row), \(cell2.column)) after second j"])
    }
}

// 2. Moving up (`k`) from row 2 to row 1 to row 0 stays locked to the same cell column
func testMovingUpFromShortFieldToLongFieldStaysInSameColumn() throws {
    let csv = "ShortHeaderA,VeryLongColumnHeaderTitleThatSpansManyCharactersB,ColC\n1,2,3\n100,200,300\n"
    let ctx = TestContext(text: csv)

    // Position caret at Row 2, Column 1
    ctx.tv.positionCaret(atRow: 2, column: 1)
    guard let cell2 = ctx.tv.currentTabularCell(), cell2.row == 2 && cell2.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to position at (2, 1)"])
    }

    // Press 'k' to go up to Row 1
    sendKey(ctx.tv, char: "k")
    guard let cell1 = ctx.tv.currentTabularCell(), cell1.row == 1 && cell1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 1), got \(String(describing: ctx.tv.currentTabularCell())) after k"])
    }

    // Press 'k' again to go up to Row 0
    sendKey(ctx.tv, char: "k")
    guard let cell0 = ctx.tv.currentTabularCell(), cell0.row == 0 && cell0.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 1), got \(String(describing: ctx.tv.currentTabularCell())) after second k"])
    }
}

// 3. Moving vertically across empty cells (,,) stays in the expected column
func testMovingVerticallyAcrossEmptyCells() throws {
    let csv = "HeaderA,HeaderB,HeaderC\nValA,,ValC\nOtherA,OtherB,OtherC\n"
    let ctx = TestContext(text: csv)

    // Position at Row 0, Column 1 (HeaderB)
    ctx.tv.positionCaret(atRow: 0, column: 1)
    guard let startCell = ctx.tv.currentTabularCell(), startCell.row == 0 && startCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 20, userInfo: [NSLocalizedDescriptionKey: "Initial cell must be (0, 1)"])
    }

    // Down to Row 1 (empty cell ,,)
    sendKey(ctx.tv, char: "j")
    guard let emptyCell = ctx.tv.currentTabularCell(), emptyCell.row == 1 && emptyCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected empty cell (1, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Down to Row 2 (OtherB)
    sendKey(ctx.tv, char: "j")
    guard let row2Cell = ctx.tv.currentTabularCell(), row2Cell.row == 2 && row2Cell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 22, userInfo: [NSLocalizedDescriptionKey: "Expected cell (2, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Back up to Row 1 (empty cell)
    sendKey(ctx.tv, char: "k")
    guard let returnEmpty = ctx.tv.currentTabularCell(), returnEmpty.row == 1 && returnEmpty.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected return to empty cell (1, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 4. Moving vertically with Up/Down arrow keys in Normal and Insert mode stays in the same cell column
func testMovingVerticallyWithUpDownArrowKeysNormalAndInsertMode() throws {
    let csv = "ColA,ColB,SuperColC\n10,20,30\n100,200,300\n"
    let ctx = TestContext(text: csv)

    // Normal mode: Start at Row 0, Column 2 (SuperColC)
    ctx.tv.positionCaret(atRow: 0, column: 2)
    guard let cell0 = ctx.tv.currentTabularCell(), cell0.row == 0 && cell0.column == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed to position at (0, 2)"])
    }

    // Down arrow (keyCode 125, \u{F701})
    sendKey(ctx.tv, char: "\u{F701}", keyCode: 125)
    guard let cell1 = ctx.tv.currentTabularCell(), cell1.row == 1 && cell1.column == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 2) after Down Arrow, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Up arrow (keyCode 126, \u{F700})
    sendKey(ctx.tv, char: "\u{F700}", keyCode: 126)
    guard let cell0Back = ctx.tv.currentTabularCell(), cell0Back.row == 0 && cell0Back.column == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 32, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 2) after Up Arrow, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Insert Mode arrow navigation
    sendKey(ctx.tv, char: "i")
    guard ctx.session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "TabularVerticalNav", code: 33, userInfo: [NSLocalizedDescriptionKey: "Failed to enter Insert mode"])
    }

    // Down arrow in insert mode
    sendKey(ctx.tv, char: "\u{F701}", keyCode: 125)
    guard let cell1Ins = ctx.tv.currentTabularCell(), cell1Ins.row == 1 && cell1Ins.column == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 2) after Down Arrow in Insert mode, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Up arrow in insert mode
    sendKey(ctx.tv, char: "\u{F700}", keyCode: 126)
    guard let cell0Ins = ctx.tv.currentTabularCell(), cell0Ins.row == 0 && cell0Ins.column == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 35, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 2) after Up Arrow in Insert mode, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Exit insert mode
    sendKey(ctx.tv, char: "\u{1b}", keyCode: 53)
}

// 5. Count multipliers (e.g. 2j, 2k) advance by the count while preserving cell column
func testCountMultipliersAdvanceByCountWhilePreservingCellColumn() throws {
    let csv = "R0C0,R0C1,R0C2\nR1C0,R1C1,R1C2\nR2C0,R2C1,R2C2\nR3C0,R3C1,R3C2\nR4C0,R4C1,R4C2\n"
    let ctx = TestContext(text: csv)

    ctx.tv.positionCaret(atRow: 0, column: 1)
    guard let startCell = ctx.tv.currentTabularCell(), startCell.row == 0 && startCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 40, userInfo: [NSLocalizedDescriptionKey: "Initial cell must be (0, 1)"])
    }

    // 2j in sequential keystrokes ('2' then 'j')
    sendKey(ctx.tv, char: "2")
    sendKey(ctx.tv, char: "j")

    guard let cell2 = ctx.tv.currentTabularCell(), cell2.row == 2 && cell2.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected cell (2, 1) after 2j, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // 2k in sequential keystrokes ('2' then 'k')
    sendKey(ctx.tv, char: "2")
    sendKey(ctx.tv, char: "k")

    guard let cell0 = ctx.tv.currentTabularCell(), cell0.row == 0 && cell0.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 1) after 2k, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Combined "3j" in single input
    sendKey(ctx.tv, char: "3j")
    guard let cell3 = ctx.tv.currentTabularCell(), cell3.row == 3 && cell3.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected cell (3, 1) after '3j', got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 6. Boundary clamping: pressing k on Row 0 stays on Row 0; pressing j on the last row stays on the last row
func testBoundaryClamping() throws {
    let csv = "R0C0,R0C1\nR1C0,R1C1\nR2C0,R2C1\n"
    let ctx = TestContext(text: csv)

    ctx.tv.positionCaret(atRow: 0, column: 1)
    guard let startCell = ctx.tv.currentTabularCell(), startCell.row == 0 && startCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 50, userInfo: [NSLocalizedDescriptionKey: "Initial cell must be (0, 1)"])
    }

    // Press 'k' on Row 0
    sendKey(ctx.tv, char: "k")
    guard let clampTop = ctx.tv.currentTabularCell(), clampTop.row == 0 && clampTop.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 51, userInfo: [NSLocalizedDescriptionKey: "k on row 0 must stay on (0, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Press '99k' on Row 0
    sendKey(ctx.tv, char: "9")
    sendKey(ctx.tv, char: "9")
    sendKey(ctx.tv, char: "k")
    guard let clampTopMulti = ctx.tv.currentTabularCell(), clampTopMulti.row == 0 && clampTopMulti.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 52, userInfo: [NSLocalizedDescriptionKey: "99k on row 0 must stay on (0, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Go to last row (Row 2)
    ctx.tv.positionCaret(atRow: 2, column: 1)
    guard let lastRowCell = ctx.tv.currentTabularCell(), lastRowCell.row == 2 && lastRowCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 53, userInfo: [NSLocalizedDescriptionKey: "Failed to position at (2, 1)"])
    }

    // Press 'j' on last row
    sendKey(ctx.tv, char: "j")
    guard let clampBottom = ctx.tv.currentTabularCell(), clampBottom.row == 2 && clampBottom.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 54, userInfo: [NSLocalizedDescriptionKey: "j on last row must stay on (2, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Press '99j' on last row
    sendKey(ctx.tv, char: "9")
    sendKey(ctx.tv, char: "9")
    sendKey(ctx.tv, char: "j")
    guard let clampBottomMulti = ctx.tv.currentTabularCell(), clampBottomMulti.row == 2 && clampBottomMulti.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 55, userInfo: [NSLocalizedDescriptionKey: "99j on last row must stay on (2, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 7. Non-tabular files (Markdown, Plain Text) continue to use standard character offset navigation
func testNonTabularFilesPreserveStandardCharacterOffsetNavigation() throws {
    let plainText = "A very long first line with many characters\nShort\nAnother long line here\n"
    let ctx = TestContext(text: plainText, isTabular: false)

    guard ctx.tv.currentTabularCell() == nil else {
        throw NSError(domain: "TabularVerticalNav", code: 60, userInfo: [NSLocalizedDescriptionKey: "currentTabularCell must be nil for non-tabular documents"])
    }

    // Set cursor to byteCol 15 on line 1
    ctx.session.setCursor(line: 1, byteCol: 15)
    ctx.tv.synchronizeCaretWithSession()

    // Send 'j'
    sendKey(ctx.tv, char: "j")

    // In plain text, line should be 2, and byteCol should clamp to the length of line 2 ("Short" len 5)
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "TabularVerticalNav", code: 61, userInfo: [NSLocalizedDescriptionKey: "Expected line 2 after j in plain text, got \(ctx.session.cursorPosition.line)"])
    }
    // "Short" has length 5, so byteCol clamps to 5
    guard ctx.session.cursorPosition.byteCol == 5 else {
        throw NSError(domain: "TabularVerticalNav", code: 62, userInfo: [NSLocalizedDescriptionKey: "Expected byteCol 5 after j clamped on line 2, got \(ctx.session.cursorPosition.byteCol)"])
    }
}

// 8. Quoted cells containing embedded commas
func testQuotedCellsWithEmbeddedCommas() throws {
    let csv = "\"Value, with, commas\",ColB\n1,2\n"
    let ctx = TestContext(text: csv)

    // Position at Row 0, Column 0 (the quoted cell)
    ctx.tv.positionCaret(atRow: 0, column: 0)
    guard let c0 = ctx.tv.currentTabularCell(), c0.row == 0 && c0.column == 0 else {
        throw NSError(domain: "TabularVerticalNav", code: 70, userInfo: [NSLocalizedDescriptionKey: "Failed to position in quoted cell"])
    }

    // Move down into Row 1, Column 0 ("1")
    sendKey(ctx.tv, char: "j")
    guard let c1 = ctx.tv.currentTabularCell(), c1.row == 1 && c1.column == 0 else {
        throw NSError(domain: "TabularVerticalNav", code: 71, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 0) below quoted cell, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Now test Column 1 (after the quoted cell)
    ctx.tv.positionCaret(atRow: 0, column: 1) // ColB
    guard let cCol1 = ctx.tv.currentTabularCell(), cCol1.row == 0 && cCol1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 72, userInfo: [NSLocalizedDescriptionKey: "Failed to position in ColB"])
    }

    sendKey(ctx.tv, char: "j")
    guard let c1Col1 = ctx.tv.currentTabularCell(), c1Col1.row == 1 && c1Col1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 73, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 9. Multibyte UTF-8 and emoji cells
func testMultibyteUtf8AndEmojiCells() throws {
    let csv = "🚀SpaceX,Col2\n🌟NASA,ColB\n"
    let ctx = TestContext(text: csv)

    ctx.tv.positionCaret(atRow: 0, column: 0)
    guard let c0 = ctx.tv.currentTabularCell(), c0.row == 0 && c0.column == 0 else {
        throw NSError(domain: "TabularVerticalNav", code: 80, userInfo: [NSLocalizedDescriptionKey: "Failed to position in emoji cell 0"])
    }

    sendKey(ctx.tv, char: "j")
    guard let c1 = ctx.tv.currentTabularCell(), c1.row == 1 && c1.column == 0 else {
        throw NSError(domain: "TabularVerticalNav", code: 81, userInfo: [NSLocalizedDescriptionKey: "Expected cell (1, 0) on emoji row 1, got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Move to Column 1 in row 1
    ctx.tv.positionCaret(atRow: 1, column: 1)
    sendKey(ctx.tv, char: "k")
    guard let c0Col1 = ctx.tv.currentTabularCell(), c0Col1.row == 0 && c0Col1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 82, userInfo: [NSLocalizedDescriptionKey: "Expected cell (0, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 10. Ragged rows with mismatched column counts
func testRaggedRowsWithMismatchedColumnCounts() throws {
    // Row 0 has 4 columns; Row 1 has 2 columns; Row 2 has 4 columns
    let csv = "A,B,C,D\n1,2\n10,20,30,40\n"
    let ctx = TestContext(text: csv)

    // Position in Row 0, Column 3 (column D)
    ctx.tv.positionCaret(atRow: 0, column: 3)
    guard let c0 = ctx.tv.currentTabularCell(), c0.row == 0 && c0.column == 3 else {
        throw NSError(domain: "TabularVerticalNav", code: 90, userInfo: [NSLocalizedDescriptionKey: "Failed to position at (0, 3)"])
    }

    // Move down to Row 1 (only 2 columns: 0 and 1) -> should clamp to Column 1
    sendKey(ctx.tv, char: "j")
    guard let c1 = ctx.tv.currentTabularCell(), c1.row == 1 && c1.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 91, userInfo: [NSLocalizedDescriptionKey: "Expected cell clamped to (1, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }

    // Move down to Row 2 -> from Column 1 it goes to Row 2, Column 1
    sendKey(ctx.tv, char: "j")
    guard let c2 = ctx.tv.currentTabularCell(), c2.row == 2 && c2.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 92, userInfo: [NSLocalizedDescriptionKey: "Expected cell (2, 1), got \(String(describing: ctx.tv.currentTabularCell()))"])
    }
}

// 11. Pending command non-interference (fj, rj)
func testPendingCommandNonInterference() throws {
    let csv = "apple,banana_j_fruit,cherry\n1,2,3\n"
    let ctx = TestContext(text: csv)

    ctx.tv.positionCaret(atRow: 0, column: 1)
    guard let startCell = ctx.tv.currentTabularCell(), startCell.row == 0 && startCell.column == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 100, userInfo: [NSLocalizedDescriptionKey: "Failed to position at (0, 1)"])
    }

    // 1. Test 'fj': Find char 'j' on the same line
    sendKey(ctx.tv, char: "f")
    guard ctx.session.hasPendingCommand else {
        throw NSError(domain: "TabularVerticalNav", code: 101, userInfo: [NSLocalizedDescriptionKey: "hasPendingCommand must be true after 'f'"])
    }
    sendKey(ctx.tv, char: "j")

    // Cursor must still be on Row 0 (line 1), NOT navigated to Row 1!
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 102, userInfo: [NSLocalizedDescriptionKey: "fj must NOT navigate vertically, line is \(ctx.session.cursorPosition.line)"])
    }
    guard !ctx.session.hasPendingCommand else {
        throw NSError(domain: "TabularVerticalNav", code: 103, userInfo: [NSLocalizedDescriptionKey: "hasPendingCommand must be false after completing 'fj'"])
    }

    // 2. Test 'rj': Replace char under cursor with 'j'
    sendKey(ctx.tv, char: "r")
    guard ctx.session.hasPendingCommand else {
        throw NSError(domain: "TabularVerticalNav", code: 104, userInfo: [NSLocalizedDescriptionKey: "hasPendingCommand must be true after 'r'"])
    }
    sendKey(ctx.tv, char: "j")

    // Cursor must still be on Row 0, line 1
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "TabularVerticalNav", code: 105, userInfo: [NSLocalizedDescriptionKey: "rj must NOT navigate vertically, line is \(ctx.session.cursorPosition.line)"])
    }
    guard !ctx.session.hasPendingCommand else {
        throw NSError(domain: "TabularVerticalNav", code: 106, userInfo: [NSLocalizedDescriptionKey: "hasPendingCommand must be false after completing 'rj'"])
    }
}

// MARK: - Test Runner Main
var testsPassed = 0
var testsFailed = 0

print("=== TabularVerticalNavigation Unit Tests ===")

let allTests: [(String, () throws -> Void)] = [
    ("testMovingDownFromLongFieldToShortFieldStaysInSameColumn", testMovingDownFromLongFieldToShortFieldStaysInSameColumn),
    ("testMovingUpFromShortFieldToLongFieldStaysInSameColumn", testMovingUpFromShortFieldToLongFieldStaysInSameColumn),
    ("testMovingVerticallyAcrossEmptyCells", testMovingVerticallyAcrossEmptyCells),
    ("testMovingVerticallyWithUpDownArrowKeysNormalAndInsertMode", testMovingVerticallyWithUpDownArrowKeysNormalAndInsertMode),
    ("testCountMultipliersAdvanceByCountWhilePreservingCellColumn", testCountMultipliersAdvanceByCountWhilePreservingCellColumn),
    ("testBoundaryClamping", testBoundaryClamping),
    ("testNonTabularFilesPreserveStandardCharacterOffsetNavigation", testNonTabularFilesPreserveStandardCharacterOffsetNavigation),
    ("testQuotedCellsWithEmbeddedCommas", testQuotedCellsWithEmbeddedCommas),
    ("testMultibyteUtf8AndEmojiCells", testMultibyteUtf8AndEmojiCells),
    ("testRaggedRowsWithMismatchedColumnCounts", testRaggedRowsWithMismatchedColumnCounts),
    ("testPendingCommandNonInterference", testPendingCommandNonInterference)
]

for (name, test) in allTests {
    if runTest(name: name, test: test) {
        testsPassed += 1
    } else {
        testsFailed += 1
    }
}

print("Result: \(testsPassed)/\(allTests.count) tests passed.")

if testsFailed > 0 {
    exit(1)
}
