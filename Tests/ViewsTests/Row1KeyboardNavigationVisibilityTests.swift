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

final class SpreadsheetVisibilityTestContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let tv: VimMDTextView
    let session: VimSession
    let colRuler: ColumnLetterRulerView
    let lineRuler: LineNumberRulerView

    static let tallCSV: String = (["HeaderA,HeaderB,HeaderC,HeaderD"] + (1...60).map { "R\($0)A,R\($0)B,R\($0)C,R\($0)D" }).joined(separator: "\n") + "\n"

    init(csv: String = SpreadsheetVisibilityTestContext.tallCSV) {
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.tv.documentSyntaxType = .csv
        self.tv.isTabularDocument = true
        self.session = VimSession(initialText: csv)
        self.tv.session = session
        self.scrollView.documentView = tv

        self.lineRuler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
        self.lineRuler.clientView = tv
        self.scrollView.hasVerticalRuler = true
        self.scrollView.verticalRulerView = lineRuler
        self.scrollView.rulersVisible = true
        self.lineRuler.updateThickness(for: tv)

        self.colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
        self.colRuler.clientView = tv
        self.scrollView.hasHorizontalRuler = true
        self.scrollView.horizontalRulerView = colRuler

        self.window.contentView = scrollView
        self.window.makeFirstResponder(tv)

        tv.updateSyntaxStyling(force: true)
        tv.updateFrameHeightToFitText()
        tv.resetScrollToTopLeft()
    }
}

// 1. k navigation to Row 1 Column 0 (Col A) maintains y == 0.0
func testKNavigationToRow1Col0MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    ctx.tv.positionCaret(atRow: 1, column: 0) // Row 2 in display, line 2 col 1
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "VisibilityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed setup cursor at row 2 col 0"])
    }

    sendKey(ctx.tv, char: "k")

    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "VisibilityTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after k, got \(ctx.session.cursorPosition.line)"])
    }
    let clipY = ctx.scrollView.contentView.bounds.origin.y
    guard abs(clipY) < 0.001 else {
        throw NSError(domain: "VisibilityTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Clip view origin y is \(clipY), expected 0.0 (Row 1 obscured behind ruler!)"])
    }
}

// 2. k navigation to Row 1 Column 1 (Col B) maintains y == 0.0
func testKNavigationToRow1Col1MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    ctx.tv.positionCaret(atRow: 1, column: 1) // Row 2 in display, Col B
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "VisibilityTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed setup cursor at row 2 col 1"])
    }

    sendKey(ctx.tv, char: "k")

    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "VisibilityTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after k, got \(ctx.session.cursorPosition.line)"])
    }
    guard ctx.session.cursorPosition.byteCol > 1 else {
        throw NSError(domain: "VisibilityTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected byteCol > 1 for Col B, got \(ctx.session.cursorPosition.byteCol)"])
    }
    let clipY = ctx.scrollView.contentView.bounds.origin.y
    guard abs(clipY) < 0.001 else {
        throw NSError(domain: "VisibilityTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Clip view origin y is \(clipY), expected 0.0 (Row 1 pushed into negative Y!)"])
    }
}

// 3. k navigation to Row 1 Column 2 (Col C) maintains y == 0.0
func testKNavigationToRow1Col2MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    ctx.tv.positionCaret(atRow: 1, column: 2)
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "VisibilityTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed setup cursor at row 2 col 2"])
    }

    sendKey(ctx.tv, char: "k")

    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "VisibilityTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after k, got \(ctx.session.cursorPosition.line)"])
    }
    let clipY = ctx.scrollView.contentView.bounds.origin.y
    guard abs(clipY) < 0.001 else {
        throw NSError(domain: "VisibilityTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Clip view origin y is \(clipY), expected 0.0"])
    }
}

// 4. k navigation to Row 1 Column 3 (Col D) maintains y == 0.0
func testKNavigationToRow1Col3MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    ctx.tv.positionCaret(atRow: 1, column: 3)
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "VisibilityTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed setup cursor at row 2 col 3"])
    }

    sendKey(ctx.tv, char: "k")

    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "VisibilityTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after k, got \(ctx.session.cursorPosition.line)"])
    }
    let clipY = ctx.scrollView.contentView.bounds.origin.y
    guard abs(clipY) < 0.001 else {
        throw NSError(domain: "VisibilityTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Clip view origin y is \(clipY), expected 0.0"])
    }
}

// 5. Up Arrow navigation maintains y == 0.0 across all columns
func testUpArrowNavigationToRow1MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    for col in 0...3 {
        ctx.tv.positionCaret(atRow: 1, column: col)
        // Up arrow key code: 126, unicode \u{F700}
        sendKey(ctx.tv, char: "\u{F700}", keyCode: 126)
        guard ctx.session.cursorPosition.line == 1 else {
            throw NSError(domain: "VisibilityTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Up arrow failed to reach line 1 from col \(col)"])
        }
        let clipY = ctx.scrollView.contentView.bounds.origin.y
        guard abs(clipY) < 0.001 else {
            throw NSError(domain: "VisibilityTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Up arrow to col \(col) resulted in clipY = \(clipY), expected 0.0"])
        }
    }
}

// 6. positionCaret(atRow: 0, column: ...) maintains y == 0.0
func testPositionCaretRow0MaintainsYZero() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    for col in 0...3 {
        // First move down so positionCaret has to adjust
        ctx.tv.positionCaret(atRow: 2, column: col)
        ctx.tv.positionCaret(atRow: 0, column: col)
        let clipY = ctx.scrollView.contentView.bounds.origin.y
        guard abs(clipY) < 0.001 else {
            throw NSError(domain: "VisibilityTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "positionCaret row 0 col \(col) clipY = \(clipY), expected 0.0"])
        }
    }
}

func fail(_ code: Int, _ msg: String) -> NSError {
    return NSError(domain: "VisibilityTests", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
}

// 7. Navigate down ~30 rows then back up with k: Row 1 must be fully visible in every column
func testDownThirtyThenUpToRow1AllColumns() throws {
    for col in 0...3 {
        let ctx = SpreadsheetVisibilityTestContext()
        ctx.tv.positionCaret(atRow: 0, column: col)
        for _ in 0..<50 { sendKey(ctx.tv, char: "j") }
        guard ctx.session.cursorPosition.line == 51 else { throw fail(20, "col \(col): expected line 51, got \(ctx.session.cursorPosition.line)") }
        let midY = ctx.scrollView.contentView.bounds.origin.y
        guard midY > 0 else { throw fail(21, "col \(col): expected mid-document scroll (y > 0), got \(midY)") }
        for _ in 0..<50 { sendKey(ctx.tv, char: "k") }
        guard ctx.session.cursorPosition.line == 1 else { throw fail(22, "col \(col): expected line 1, got \(ctx.session.cursorPosition.line)") }
        let clipY = ctx.scrollView.contentView.bounds.origin.y
        guard abs(clipY) < 0.001 else { throw fail(23, "col \(col): clip y = \(clipY), expected 0") }
        let loc = ctx.tv.selectedRange().location
        guard let lm = ctx.tv.layoutManager, let tc = ctx.tv.textContainer else { throw fail(24, "no layout manager") }
        let glyph = lm.glyphIndexForCharacter(at: 0)
        let rowRect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            .offsetBy(dx: ctx.tv.textContainerOrigin.x, dy: ctx.tv.textContainerOrigin.y)
        guard ctx.tv.visibleRect.intersects(rowRect), ctx.tv.visibleRect.minY <= rowRect.minY + 0.001 else {
            throw fail(25, "col \(col): Row 1 rect \(rowRect) not within visibleRect \(ctx.tv.visibleRect) (caret loc \(loc))")
        }
    }
}

// 8. Normal mid-document scrolling is unaffected: clip y never negative, caret stays visible
func testMidDocumentScrollingUnaffected() throws {
    let ctx = SpreadsheetVisibilityTestContext()
    ctx.tv.positionCaret(atRow: 0, column: 2)
    for _ in 0..<40 { sendKey(ctx.tv, char: "j") }
    let y = ctx.scrollView.contentView.bounds.origin.y
    guard y > 0 else { throw fail(30, "expected scrolled down, y = \(y)") }
    for _ in 0..<5 { sendKey(ctx.tv, char: "k") }
    let y2 = ctx.scrollView.contentView.bounds.origin.y
    guard y2 > 0 else { throw fail(31, "mid-document y collapsed to \(y2)") }
    guard ctx.session.cursorPosition.line == 36 else { throw fail(32, "expected line 36, got \(ctx.session.cursorPosition.line)") }
}

let tests: [(String, () throws -> Void)] = [
    ("testKNavigationToRow1Col0MaintainsYZero", testKNavigationToRow1Col0MaintainsYZero),
    ("testKNavigationToRow1Col1MaintainsYZero", testKNavigationToRow1Col1MaintainsYZero),
    ("testKNavigationToRow1Col2MaintainsYZero", testKNavigationToRow1Col2MaintainsYZero),
    ("testKNavigationToRow1Col3MaintainsYZero", testKNavigationToRow1Col3MaintainsYZero),
    ("testUpArrowNavigationToRow1MaintainsYZero", testUpArrowNavigationToRow1MaintainsYZero),
    ("testPositionCaretRow0MaintainsYZero", testPositionCaretRow0MaintainsYZero),
    ("testDownThirtyThenUpToRow1AllColumns", testDownThirtyThenUpToRow1AllColumns),
    ("testMidDocumentScrollingUnaffected", testMidDocumentScrollingUnaffected)
]

print("=== Row1KeyboardNavigationVisibilityTests ===")
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
