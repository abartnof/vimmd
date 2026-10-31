import Foundation
import AppKit
import Views
import Engine
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

func testColumnLetterBijectiveConversion() throws {
    guard ColumnLetterRulerView.columnLetter(for: 0) == "A" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "0 should be A"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 25) == "Z" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "25 should be Z"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 26) == "AA" else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "26 should be AA"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 27) == "AB" else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "27 should be AB"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 51) == "AZ" else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "51 should be AZ"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 52) == "BA" else {
        throw NSError(domain: "ViewsTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "52 should be BA"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 701) == "ZZ" else {
        throw NSError(domain: "ViewsTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "701 should be ZZ"])
    }
    guard ColumnLetterRulerView.columnLetter(for: 702) == "AAA" else {
        throw NSError(domain: "ViewsTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "702 should be AAA"])
    }
}

func testRulerInitializationAndOrientation() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)

    guard ruler.orientation == .horizontalRuler else {
        throw NSError(domain: "ViewsTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Ruler orientation must be horizontal"])
    }
    guard ruler.ruleThickness >= 18.0 && ruler.ruleThickness <= 30.0 else {
        throw NSError(domain: "ViewsTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Ruler thickness should be between 18 and 30 pt, got \(ruler.ruleThickness)"])
    }
}

func testRulerVisibilityForTabularDocuments() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    scrollView.documentView = textView

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    ruler.clientView = textView
    scrollView.horizontalRulerView = ruler

    textView.documentSyntaxType = .csv
    guard scrollView.hasHorizontalRuler == true else {
        throw NSError(domain: "ViewsTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalRuler should be true for CSV"])
    }

    textView.documentSyntaxType = .tsv
    guard scrollView.hasHorizontalRuler == true else {
        throw NSError(domain: "ViewsTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalRuler should be true for TSV"])
    }

    textView.documentSyntaxType = .markdown
    guard scrollView.hasHorizontalRuler == false else {
        throw NSError(domain: "ViewsTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalRuler should be false for Markdown"])
    }
}

func testColumnLetterHoverCursor() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    let session = VimSession(initialText: "A,B,C\n1,2,3\n")
    textView.session = session
    scrollView.documentView = textView

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    ruler.clientView = textView
    scrollView.horizontalRulerView = ruler
    scrollView.hasHorizontalRuler = true

    let cur = ruler.cursorForPoint(NSPoint(x: 50, y: 10))
    guard cur == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "ViewsTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Expected downwardArrowCursor over column letter ruler"])
    }

    textView.documentSyntaxType = .plainText
    let curPlain = ruler.cursorForPoint(NSPoint(x: 50, y: 10))
    guard curPlain == nil else {
        throw NSError(domain: "ViewsTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Expected nil cursor for plain text"])
    }
}

func testColumnLetterClickCopiesColumn() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    let csv = "Name,Department,Salary\nAlice,Engineering,150k\nBob,Design,120k\nCarol,Product,130k\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    ruler.clientView = textView
    scrollView.horizontalRulerView = ruler
    scrollView.hasHorizontalRuler = true
    scrollView.rulersVisible = true

    guard let col1Rect = textView.columnRect(for: 1) else {
        throw NSError(domain: "ViewsTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Failed to get col 1 rect"])
    }
    let rulerPt = ruler.convert(NSPoint(x: col1Rect.midX, y: 0), from: textView)

    var feedbackReceived: String?
    textView.onFlashFeedback = { msg in
        feedbackReceived = msg
    }

    NSPasteboard.general.clearContents()
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: ruler.convert(rulerPt, to: nil as NSView?),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!
    ruler.mouseDown(with: event)

    let copied = NSPasteboard.general.string(forType: .string)
    guard copied == "Department\nEngineering\nDesign\nProduct" else {
        throw NSError(domain: "ViewsTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Expected copied 'Department\\nEngineering\\nDesign\\nProduct', got '\(String(describing: copied))'"])
    }
    guard let feedback = feedbackReceived, feedback.contains("Department") else {
        throw NSError(domain: "ViewsTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected feedback mentioning Department, got \(String(describing: feedbackReceived))"])
    }
    guard textView.transientFlashRect != nil else {
        throw NSError(domain: "ViewsTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected transientFlashRect to be set"])
    }
}

func testColumnLetterAlignmentAndDrawing() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    textView.wrapTableCells = true
    let csv = "ColA,ColB,ColC\n1,2,3\n"
    let session = VimSession(initialText: csv)
    textView.session = session
    scrollView.documentView = textView
    textView.updateSyntaxStyling(force: true)

    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    ruler.clientView = textView
    scrollView.horizontalRulerView = ruler

    // Default wrapped width should be 240.0 pt for each column
    let widths = textView.columnWidths()
    guard widths.count == 3 else {
        throw NSError(domain: "ViewsTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Expected 3 columns, got \(widths.count)"])
    }
    for (i, w) in widths.enumerated() {
        guard abs(w - 240.0) < 0.1 else {
            throw NSError(domain: "ViewsTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Col \(i) width should default to 240.0 pt, got \(w)"])
        }
    }

    // Check drawing without crashing
    let image = NSImage(size: NSSize(width: max(1, ruler.bounds.width), height: max(1, ruler.bounds.height)))
    image.lockFocus()
    ruler.draw(ruler.bounds)
    image.unlockFocus()
}

func testRulerAccessoriesAndMarkersDisabled() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    guard tv.usesRuler == false else {
        throw NSError(domain: "ViewsTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "tv.usesRuler should default to false"])
    }

    scrollView.documentView = tv
    let colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    colRuler.clientView = tv
    scrollView.horizontalRulerView = colRuler

    tv.documentSyntaxType = .csv
    guard tv.usesRuler == false else {
        throw NSError(domain: "ViewsTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "tv.usesRuler should remain false after setting csv syntax"])
    }

    // Verify accessoryView is nil and setter is a no-op
    guard colRuler.accessoryView == nil else {
        throw NSError(domain: "ViewsTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "colRuler.accessoryView should be nil"])
    }
    colRuler.accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
    guard colRuler.accessoryView == nil else {
        throw NSError(domain: "ViewsTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "colRuler.accessoryView setter should be a no-op"])
    }

    // Verify markers is nil or empty, and addMarker is a no-op
    guard colRuler.markers == nil || colRuler.markers?.isEmpty == true else {
        throw NSError(domain: "ViewsTests", code: 64, userInfo: [NSLocalizedDescriptionKey: "colRuler.markers should be nil or empty"])
    }
    let marker = NSRulerMarker(rulerView: colRuler, markerLocation: 50.0, image: NSImage(), imageOrigin: .zero)
    colRuler.addMarker(marker)
    guard colRuler.markers == nil || colRuler.markers?.isEmpty == true else {
        throw NSError(domain: "ViewsTests", code: 65, userInfo: [NSLocalizedDescriptionKey: "colRuler.addMarker should be ignored"])
    }

    // Verify subviews cannot be added and remain empty
    let dummyView = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
    colRuler.addSubview(dummyView)
    guard colRuler.subviews.isEmpty else {
        throw NSError(domain: "ViewsTests", code: 66, userInfo: [NSLocalizedDescriptionKey: "colRuler.subviews should remain empty"])
    }
}

print("=== ColumnLetterRulerView Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testColumnLetterBijectiveConversion", testColumnLetterBijectiveConversion),
    ("testRulerInitializationAndOrientation", testRulerInitializationAndOrientation),
    ("testRulerVisibilityForTabularDocuments", testRulerVisibilityForTabularDocuments),
    ("testColumnLetterHoverCursor", testColumnLetterHoverCursor),
    ("testColumnLetterClickCopiesColumn", testColumnLetterClickCopiesColumn),
    ("testColumnLetterAlignmentAndDrawing", testColumnLetterAlignmentAndDrawing),
    ("testRulerAccessoriesAndMarkersDisabled", testRulerAccessoriesAndMarkersDisabled)
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
