import Foundation
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

func testVimSessionInitialization() throws {
    let initial = "# VimMD Heading\nLine two content."
    let session = VimSession(initialText: initial)
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected VimSession to be valid upon initialization"])
    }
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected default mode to be VIM_MODE_NORMAL"])
    }
    guard session.cursor.line == 1 && session.cursor.byteCol == 1 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected cursor at (1, 1)"])
    }
    guard !session.isDirty else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected session not to be dirty initially"])
    }
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Serialized buffer does not match initial text"])
    }
}

func testVimSessionEmptyInitialization() throws {
    let session = VimSession(initialText: "")
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected empty VimSession to be valid"])
    }
    guard session.serializeBuffer() == "" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected empty buffer string"])
    }
}

func testVimSessionClearDirty() throws {
    let session = VimSession(initialText: "Testing dirty flag")
    session.clearDirty()
    guard !session.isDirty else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected clean session after clearDirty"])
    }
}

func testVimSessionFeedKeysAndExecuteEx() throws {
    let session = VimSession(initialText: "Buffer before keys")
    // feedKeys and executeEx must be robust, non-crashing methods
    session.feedKeys("gg")
    session.feedKeys("i")
    session.executeEx(":set number")
    session.executeEx(":w")
    guard session.isValid else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session should remain valid after feedKeys and executeEx"])
    }
}

func testVimSessionMultibyteUnicode() throws {
    let multibyte = "Hello 🚀 世界! Testing emojis 🌍 and accents é, ü, ñ."
    let session = VimSession(initialText: multibyte)
    guard session.serializeBuffer() == multibyte else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unicode round-trip serialization failed"])
    }
}

func testVimSessionMultiSessionIsolation() throws {
    let text1 = "Document 1: Swift Engine"
    let text2 = "Document 2: Rust / C Engine with 🚀"
    let session1 = VimSession(initialText: text1)
    let session2 = VimSession(initialText: text2)

    guard session1.serializeBuffer() == text1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session 1 buffer mismatch"])
    }
    guard session2.serializeBuffer() == text2 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session 2 buffer mismatch"])
    }

    session1.clearDirty()
    guard !session1.isDirty && !session2.isDirty else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Isolation failure on dirty flag"])
    }
}

func testVimSessionLineDeltaCallback() throws {
    let session = VimSession(initialText: "Original line 1\nOriginal line 2")
    var receivedStartLine: Int32 = -1
    var receivedDeletedCount: Int32 = -1
    var receivedLines: [String] = []

    session.onLineDelta = { startLine, deletedCount, newLines in
        receivedStartLine = startLine
        receivedDeletedCount = deletedCount
        receivedLines = newLines
    }

    session.triggerLineDelta(startLine: 1, deletedCount: 1, newLines: ["Replaced line 1", "Appended line 1.5"])

    guard receivedStartLine == 1 else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected startLine 1, got \(receivedStartLine)"])
    }
    guard receivedDeletedCount == 1 else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected deletedCount 1, got \(receivedDeletedCount)"])
    }
    guard receivedLines == ["Replaced line 1", "Appended line 1.5"] else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected replacement lines, got \(receivedLines)"])
    }
}

func testVimSessionLoopStability() throws {
    for i in 0..<500 {
        let text = "Iteration \(i) buffer content"
        let session = VimSession(initialText: text)
        guard session.isValid else {
            throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed creating session at iteration \(i)"])
        }
    }
}

print("=== Engine Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testVimSessionInitialization", testVimSessionInitialization),
    ("testVimSessionEmptyInitialization", testVimSessionEmptyInitialization),
    ("testVimSessionClearDirty", testVimSessionClearDirty),
    ("testVimSessionFeedKeysAndExecuteEx", testVimSessionFeedKeysAndExecuteEx),
    ("testVimSessionMultibyteUnicode", testVimSessionMultibyteUnicode),
    ("testVimSessionMultiSessionIsolation", testVimSessionMultiSessionIsolation),
    ("testVimSessionLineDeltaCallback", testVimSessionLineDeltaCallback),
    ("testVimSessionLoopStability", testVimSessionLoopStability)
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
