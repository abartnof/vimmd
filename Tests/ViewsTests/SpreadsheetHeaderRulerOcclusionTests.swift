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

final class SpreadsheetOcclusionTestContext {
    let window: NSWindow
    let scrollView: NSScrollView
    let tv: VimMDTextView
    let session: VimSession
    let colRuler: ColumnLetterRulerView
    let lineRuler: LineNumberRulerView

    static let testCSV: String = (["ColA,ColB,ColC,ColD"] + (1...60).map { "R\($0)A,R\($0)B,R\($0)C,R\($0)D" }).joined(separator: "\n") + "\n"

    init(csv: String = SpreadsheetOcclusionTestContext.testCSV) {
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

// 1. ColumnLetterRulerView thickness normalization
func testColumnLetterRulerMarkerReservationAndThickness() throws {
    let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let ruler = ColumnLetterRulerView(scrollView: sv, orientation: .horizontalRuler)

    guard ruler.reservedThicknessForMarkers == 0.0 else {
        throw NSError(
            domain: "OcclusionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "ColumnLetterRulerView.reservedThicknessForMarkers is \(ruler.reservedThicknessForMarkers), expected 0.0"]
        )
    }

    guard abs(ruler.requiredThickness - ruler.ruleThickness) < 0.001 else {
        throw NSError(
            domain: "OcclusionTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "requiredThickness (\(ruler.requiredThickness)) does not equal ruleThickness (\(ruler.ruleThickness))"]
        )
    }

    guard abs(ruler.ruleThickness - 20.0) < 0.001 else {
        throw NSError(
            domain: "OcclusionTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "ruleThickness is \(ruler.ruleThickness), expected 20.0 at default scale"]
        )
    }
}

// 2. Row 1 not occluded after document opening and resetScrollToTopLeft
func testRow1NotOccludedAfterOpenAndResetScroll() throws {
    let ctx = SpreadsheetOcclusionTestContext()
    ctx.tv.resetScrollToTopLeft()

    guard let row0Rect = ctx.tv.rowRect(for: 0) else {
        throw NSError(domain: "OcclusionTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to get row 0 rect"])
    }

    let row0InSV = ctx.tv.convert(row0Rect, to: ctx.scrollView)
    let rulerFrame = ctx.colRuler.frame

    if row0InSV.intersects(rulerFrame) {
        throw NSError(
            domain: "OcclusionTests",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Row 1 rect in scroll view \(row0InSV) intersects horizontal ruler frame \(rulerFrame)"]
        )
    }

    if row0InSV.minY < rulerFrame.maxY - 0.001 {
        throw NSError(
            domain: "OcclusionTests",
            code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Row 1 minY (\(row0InSV.minY)) is above ruler maxY (\(rulerFrame.maxY))"]
        )
    }
}

// 3. Row 2 not occluded after document opening and resetScrollToTopLeft
func testRow2NotOccludedAfterOpenAndResetScroll() throws {
    let ctx = SpreadsheetOcclusionTestContext()
    ctx.tv.resetScrollToTopLeft()

    guard let row1Rect = ctx.tv.rowRect(for: 1) else {
        throw NSError(domain: "OcclusionTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Failed to get row 1 rect"])
    }

    let row1InSV = ctx.tv.convert(row1Rect, to: ctx.scrollView)
    let rulerFrame = ctx.colRuler.frame

    if row1InSV.intersects(rulerFrame) {
        throw NSError(
            domain: "OcclusionTests",
            code: 21,
            userInfo: [NSLocalizedDescriptionKey: "Row 2 rect in scroll view \(row1InSV) intersects horizontal ruler frame \(rulerFrame)"]
        )
    }

    if row1InSV.minY < rulerFrame.maxY - 0.001 {
        throw NSError(
            domain: "OcclusionTests",
            code: 22,
            userInfo: [NSLocalizedDescriptionKey: "Row 2 minY (\(row1InSV.minY)) is above ruler maxY (\(rulerFrame.maxY))"]
        )
    }
}

// 4. Navigation (k, Up arrow, j, Down arrow, gg, G, mouse clicks) keeps Row 1 visible without occlusion
func testNavigationKeepsRow1VisibleWithoutOcclusion() throws {
    let ctx = SpreadsheetOcclusionTestContext()

    func assertRow1Visible(action: String) throws {
        guard let row0Rect = ctx.tv.rowRect(for: 0) else {
            throw NSError(domain: "OcclusionTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Failed row 0 rect during \(action)"])
        }
        let row0InSV = ctx.tv.convert(row0Rect, to: ctx.scrollView)
        let rulerFrame = ctx.colRuler.frame
        if row0InSV.intersects(rulerFrame) {
            throw NSError(
                domain: "OcclusionTests",
                code: 31,
                userInfo: [NSLocalizedDescriptionKey: "After \(action), Row 1 rect \(row0InSV) intersects ruler \(rulerFrame)"]
            )
        }
        if row0InSV.minY < rulerFrame.maxY - 0.001 {
            throw NSError(
                domain: "OcclusionTests",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "After \(action), Row 1 minY \(row0InSV.minY) is above ruler maxY \(rulerFrame.maxY)"]
            )
        }
    }

    // A. Initial open
    try assertRow1Visible(action: "initial open")

    // B. Navigate down with 'j' to line 2, then 'k' back to line 1
    sendKey(ctx.tv, char: "j")
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "OcclusionTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected line 2 after j"])
    }
    sendKey(ctx.tv, char: "k")
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "OcclusionTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after k"])
    }
    try assertRow1Visible(action: "k back to line 1")

    // C. Navigate down with Down Arrow, then Up Arrow back to line 1
    // Down arrow key code: 125, unicode \u{F701}
    sendKey(ctx.tv, char: "\u{F701}", keyCode: 125)
    guard ctx.session.cursorPosition.line == 2 else {
        throw NSError(domain: "OcclusionTests", code: 35, userInfo: [NSLocalizedDescriptionKey: "Expected line 2 after Down arrow"])
    }
    // Up arrow key code: 126, unicode \u{F700}
    sendKey(ctx.tv, char: "\u{F700}", keyCode: 126)
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "OcclusionTests", code: 36, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after Up arrow"])
    }
    try assertRow1Visible(action: "Up arrow back to line 1")

    // D. Jump far down with 'G' (bottom of document) then 'gg' (top of document)
    sendKey(ctx.tv, char: "G")
    guard ctx.session.cursorPosition.line > 50 else {
        throw NSError(domain: "OcclusionTests", code: 37, userInfo: [NSLocalizedDescriptionKey: "Expected bottom line after G"])
    }
    sendKey(ctx.tv, char: "g")
    sendKey(ctx.tv, char: "g")
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "OcclusionTests", code: 38, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after gg"])
    }
    try assertRow1Visible(action: "gg back to line 1")

    // E. Mouse click on Row 1 (header row)
    guard let row0Rect = ctx.tv.rowRect(for: 0) else {
        throw NSError(domain: "OcclusionTests", code: 39, userInfo: [NSLocalizedDescriptionKey: "Failed row 0 rect"])
    }
    let clickPt = NSPoint(x: row0Rect.midX, y: row0Rect.midY)
    ctx.tv.positionCaret(at: clickPt)
    guard ctx.session.cursorPosition.line == 1 else {
        throw NSError(domain: "OcclusionTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Expected line 1 after mouse click"])
    }
    try assertRow1Visible(action: "mouse click on Row 1")
}

print("=== SpreadsheetHeaderRulerOcclusionTests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testColumnLetterRulerMarkerReservationAndThickness", testColumnLetterRulerMarkerReservationAndThickness),
    ("testRow1NotOccludedAfterOpenAndResetScroll", testRow1NotOccludedAfterOpenAndResetScroll),
    ("testRow2NotOccludedAfterOpenAndResetScroll", testRow2NotOccludedAfterOpenAndResetScroll),
    ("testNavigationKeepsRow1VisibleWithoutOcclusion", testNavigationKeepsRow1VisibleWithoutOcclusion)
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
