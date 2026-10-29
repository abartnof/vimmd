import Foundation
import AppKit
import Engine
import Views
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

func testSortCommandAlphabetical() throws {
    let initial = "delta\nalpha\ncharlie\nbravo"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    var deltaDispatched = false
    var deltaStart = 0
    var deltaDeleted = 0
    var deltaAdded = 0
    session.onLineDelta = { start, del, newLines in
        deltaDispatched = true
        deltaStart = Int(start)
        deltaDeleted = Int(del)
        deltaAdded = newLines.count
    }

    session.executeEx("sort")

    guard session.isDirty else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected session to be dirty after sort"])
    }
    guard session.lastError == nil else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected lastError to be nil, got: \(session.lastError!)"])
    }
    let expected = "alpha\nbravo\ncharlie\ndelta"
    guard session.serializeBuffer() == expected else {
        throw NSError(domain: "SortCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Buffer does not match expected alphabetical sort: '\(session.serializeBuffer())'"])
    }
    guard deltaDispatched && deltaStart == 1 && deltaDeleted == 4 && deltaAdded == 4 else {
        throw NSError(domain: "SortCommandTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Delta callback mismatch: start=\(deltaStart), del=\(deltaDeleted), add=\(deltaAdded)"])
    }
    guard textView.string == expected else {
        throw NSError(domain: "SortCommandTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "VimMDTextView string mismatch: '\(textView.string)'"])
    }
    guard session.lineIndexTable.lineCount == 4 else {
        throw NSError(domain: "SortCommandTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "LineIndexTable line count mismatch"])
    }
}

func testSortCommandReverse() throws {
    let initial = "alpha\nbravo\ncharlie\ndelta"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    session.executeEx("sort!")

    let expected = "delta\ncharlie\nbravo\nalpha"
    guard session.serializeBuffer() == expected else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Buffer does not match reverse sort: '\(session.serializeBuffer())'"])
    }
    guard textView.string == expected else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView text did not synchronize after sort!: '\(textView.string)'"])
    }
}

func testSortCommandUnique() throws {
    let initial = "pear\napple\norange\napple\npear\nbanana"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    var recordedDeleted = 0
    var recordedAdded = 0
    session.onLineDelta = { _, del, newLines in
        recordedDeleted = Int(del)
        recordedAdded = newLines.count
    }

    session.executeEx("sort u")

    let expected = "apple\nbanana\norange\npear"
    guard session.serializeBuffer() == expected else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Buffer does not match sort u: '\(session.serializeBuffer())'"])
    }
    guard textView.string == expected else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView text mismatch after sort u: '\(textView.string)'"])
    }
    guard session.lineIndexTable.lineCount == 4 else {
        throw NSError(domain: "SortCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "LineIndexTable count expected 4, got \(session.lineIndexTable.lineCount)"])
    }
    guard recordedDeleted == 6 && recordedAdded == 4 else {
        throw NSError(domain: "SortCommandTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Delta mismatch: deleted=\(recordedDeleted), added=\(recordedAdded)"])
    }
}

func testSortCommandNumeric() throws {
    let initial = "task 100\ntask 2\ntask 10\ntask 1"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    session.executeEx("sort n")

    let expected = "task 1\ntask 2\ntask 10\ntask 100"
    guard session.serializeBuffer() == expected else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Numeric sort mismatch: '\(session.serializeBuffer())'"])
    }
    guard textView.string == expected else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView numeric sort mismatch: '\(textView.string)'"])
    }

    // Reverse numeric
    session.executeEx("sort! n")
    let revExpected = "task 100\ntask 10\ntask 2\ntask 1"
    guard session.serializeBuffer() == revExpected else {
        throw NSError(domain: "SortCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Reverse numeric sort mismatch: '\(session.serializeBuffer())'"])
    }
    guard textView.string == revExpected else {
        throw NSError(domain: "SortCommandTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "TextView reverse numeric mismatch: '\(textView.string)'"])
    }
}

func testSortCommandRangeAndVisualRange() throws {
    let initial = "header\nzebra\napple\nmango\nfooter"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    // Sort subrange lines 2 to 4
    session.executeEx("2,4sort")

    let expected = "header\napple\nmango\nzebra\nfooter"
    guard session.serializeBuffer() == expected else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Range sort mismatch: '\(session.serializeBuffer())'"])
    }
    guard textView.string == expected else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView range sort mismatch: '\(textView.string)'"])
    }

    // Visual selection range: :'<,'>sort
    let visualInitial = "START\nkilo\nfoxtrot\nhotel\nEND"
    let visualSession = VimSession(initialText: visualInitial)
    visualSession.feedKeys("2G")
    visualSession.feedKeys("V")
    visualSession.feedKeys("2j") // Select lines 2 to 4
    visualSession.executeEx("'<,'>sort")

    let visualExpected = "START\nfoxtrot\nhotel\nkilo\nEND"
    guard visualSession.serializeBuffer() == visualExpected else {
        throw NSError(domain: "SortCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Visual range sort mismatch: '\(visualSession.serializeBuffer())'"])
    }
}

func testSortCommandUndoRedoPipeline() throws {
    let initial = "300\n10\n20\n10\n300"
    let session = VimSession(initialText: initial)
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.session = session

    session.executeEx("sort u n")
    let sortedText = "10\n20\n300"
    guard session.serializeBuffer() == sortedText else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sort u n failed"])
    }
    guard textView.string == sortedText else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView sort u n mismatch"])
    }

    // Undo
    session.undo()
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "SortCommandTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Undo failed to restore initial text"])
    }
    guard textView.string == initial else {
        throw NSError(domain: "SortCommandTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "TextView undo mismatch"])
    }

    // Redo
    session.redo()
    guard session.serializeBuffer() == sortedText else {
        throw NSError(domain: "SortCommandTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Redo failed to restore sorted text"])
    }
    guard textView.string == sortedText else {
        throw NSError(domain: "SortCommandTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "TextView redo mismatch"])
    }
}

func testSortCommandErrorHandling() throws {
    let session = VimSession(initialText: "line 1\nline 2\nline 3")

    // Invalid range start > end
    session.executeEx("3,1sort")
    guard let err1 = session.lastError, err1.contains("E16") else {
        throw NSError(domain: "SortCommandTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected E16 for invalid range, got: \(session.lastError ?? "nil")"])
    }

    // Malformed sort options
    session.executeEx("sort invalid")
    guard let err2 = session.lastError, err2.contains("E492") else {
        throw NSError(domain: "SortCommandTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected E492 for malformed sort command, got: \(session.lastError ?? "nil")"])
    }
}

let tests: [(String, () throws -> Void)] = [
    ("testSortCommandAlphabetical", testSortCommandAlphabetical),
    ("testSortCommandReverse", testSortCommandReverse),
    ("testSortCommandUnique", testSortCommandUnique),
    ("testSortCommandNumeric", testSortCommandNumeric),
    ("testSortCommandRangeAndVisualRange", testSortCommandRangeAndVisualRange),
    ("testSortCommandUndoRedoPipeline", testSortCommandUndoRedoPipeline),
    ("testSortCommandErrorHandling", testSortCommandErrorHandling),
]

print("=== SortCommandTests ===")
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
