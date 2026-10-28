import Foundation
import AppKit
import CBridge
import Engine

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

func testStreamingDeleteInnerQuotes() throws {
    let session = VimSession(initialText: "let key = 'secret_api_token';")
    var lastYanked: String?
    var lastLinewise: Bool?
    session.onYank = { (text: String, linewise: Bool) in
        lastYanked = text
        lastLinewise = linewise
    }

    session.setCursor(line: 1, byteCol: 15) // inside 'secret_api_token'
    session.feedKeys("di'")

    guard session.serializeBuffer() == "let key = '';" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected empty quotes, got: \(session.serializeBuffer())"])
    }
    guard session.isDirty else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Session should be dirty"])
    }
    guard lastYanked == "secret_api_token" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected yanked secret_api_token, got: \(String(describing: lastYanked))"])
    }
    guard lastLinewise == false else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Yank should be characterwise"])
    }
    guard session.yankBuffer?.text == "secret_api_token" else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "yankBuffer should match clipboard"])
    }
    guard session.yankBuffer?.linewise == false else {
        throw NSError(domain: "EngineTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "yankBuffer should not be linewise"])
    }
    guard NSPasteboard.general.string(forType: .string) == "secret_api_token" else {
        throw NSError(domain: "EngineTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "NSPasteboard should contain deleted inner text"])
    }

    // Undo should restore original string
    session.undo()
    guard session.serializeBuffer() == "let key = 'secret_api_token';" else {
        throw NSError(domain: "EngineTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Undo failed to restore initial content"])
    }
}

func testStreamingChangeInnerDoubleQuotes() throws {
    let session = VimSession(initialText: "config(\"database_url_old\");")
    session.setCursor(line: 1, byteCol: 12)
    session.feedKeys("ci\"postgres://prod\u{1b}")

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mode should be normal after escape"])
    }
    guard session.serializeBuffer() == "config(\"postgres://prod\");" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected updated config, got: \(session.serializeBuffer())"])
    }
    guard session.yankBuffer?.text == "database_url_old" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected old string in yankBuffer"])
    }

    // Undo change + insert in single step
    session.undo()
    guard session.serializeBuffer() == "config(\"database_url_old\");" else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Single undo should restore initial content"])
    }
}

func testStreamingYankInnerParentheses() throws {
    let session = VimSession(initialText: "dispatch(event, payload, nil);")
    session.setCursor(line: 1, byteCol: 14)
    session.feedKeys("yi(")

    guard session.serializeBuffer() == "dispatch(event, payload, nil);" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Yank should not mutate buffer"])
    }
    guard !session.isDirty else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Yank should not mark session dirty"])
    }
    guard session.yankBuffer?.text == "event, payload, nil" else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected inner params in yankBuffer, got: \(String(describing: session.yankBuffer?.text))"])
    }
    guard session.yankBuffer?.linewise == false else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Yank should not be linewise"])
    }
    guard NSPasteboard.general.string(forType: .string) == "event, payload, nil" else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "NSPasteboard should contain yanked text"])
    }
}

func testStreamingMultilineTextObject() throws {
    let initial = "function run() {\n    first();\n    second();\n}"
    let session = VimSession(initialText: initial)
    session.setCursor(line: 2, byteCol: 6)

    var deltaCount = 0
    session.onLineDelta = { (startLine: Int32, deletedCount: Int32, newLines: [String]) in
        deltaCount += 1
    }

    session.feedKeys("di{")

    guard session.serializeBuffer() == "function run() {}" else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected function run() {}, got: \(session.serializeBuffer())"])
    }
    guard session.yankBuffer?.text == "\n    first();\n    second();\n" else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected multiline yankBuffer: \(String(describing: session.yankBuffer?.text))"])
    }
    guard deltaCount >= 1 else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected at least one line delta dispatch"])
    }

    session.undo()
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Multiline undo failed"])
    }
}

func testStreamingEscCancellation() throws {
    let initial = "var x = [1, 2, 3];"
    let session = VimSession(initialText: initial)
    session.setCursor(line: 1, byteCol: 12)

    // d<Esc>
    session.feedKeys("d\u{1b}")
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "d<Esc> modified buffer"])
    }

    // di<Esc>
    session.feedKeys("di\u{1b}")
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "di<Esc> modified buffer"])
    }

    // c<Esc>
    session.feedKeys("c\u{1b}")
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "c<Esc> modified buffer"])
    }

    // ci<Esc>
    session.feedKeys("ci\u{1b}")
    guard session.serializeBuffer() == initial else {
        throw NSError(domain: "EngineTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "ci<Esc> modified buffer"])
    }

    // y<Esc>
    session.feedKeys("y\u{1b}")
    // yi<Esc>
    session.feedKeys("yi\u{1b}")

    // Now execute actual di[
    session.feedKeys("di[")
    guard session.serializeBuffer() == "var x = [];" else {
        throw NSError(domain: "EngineTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "di[ after cancelled commands failed: \(session.serializeBuffer())"])
    }
}

print("=== OperatorTextObjectTests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testStreamingDeleteInnerQuotes", testStreamingDeleteInnerQuotes),
    ("testStreamingChangeInnerDoubleQuotes", testStreamingChangeInnerDoubleQuotes),
    ("testStreamingYankInnerParentheses", testStreamingYankInnerParentheses),
    ("testStreamingMultilineTextObject", testStreamingMultilineTextObject),
    ("testStreamingEscCancellation", testStreamingEscCancellation)
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
