import Foundation
import AppKit
import App
import Views
import Engine
import CBridge

print("================================================================================")
print(" VimMD Critical User Journey (CUJ) Verification Suite")
print("================================================================================")

// Ensure AppKit NSApplication environment is initialized
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
appDelegate.setupMainMenu()

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cuj_\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
defer {
    try? FileManager.default.removeItem(at: tempDir)
}

// ============================================================================
// SCENARIO A: The User's Exact File from Screenshot (pcc_incremental_tables_roadmap_v2.md)
// ============================================================================
print("\n>>> [SCENARIO A] Testing user's exact file: pcc_incremental_tables_roadmap_v2.md")

let scenarioAFilename = "pcc_incremental_tables_roadmap_v2.md"
let scenarioAURL = tempDir.appendingPathComponent(scenarioAFilename)

let initialMarkdownContent = """
# Incremental Tables Roadmap 📊 🚀

**Status: In Progress**

| Phase | Milestone | Priority |
| :--- | :--- | :--- |
| Phase 1 | Schema Ingestion | P0 |
| Phase 2 | Delta Compaction | P1 |

## Action Items
- [ ] Ingestion engine performance audit
- [ ] Benchmark multi-node write throughput
"""

try initialMarkdownContent.write(to: scenarioAURL, atomically: true, encoding: .utf8)
print("[SCENARIO A] Step 1: Created rich markdown file at \(scenarioAURL.path)")
print("  - Content contains headers, tables, bold text, checklists, and emojis (📊 🚀)")

// Confirm opening with "Markdown Document" format succeeds without any errors
print("[SCENARIO A] Step 2: Instantiating VimMDDocument with ofType: 'Markdown Document'")
let docA: VimMDDocument
do {
    docA = try VimMDDocument(contentsOf: scenarioAURL, ofType: "Markdown Document")
    print("  - Successfully opened document with ofType: 'Markdown Document'")
    print("  - Confirmed: NO 'VimMD cannot open files in Markdown Document format' error occurred!")
} catch {
    fatalError("[SCENARIO A FAILURE] Failed to instantiate VimMDDocument: \(error.localizedDescription)")
}

assert(docA.fileURL == scenarioAURL, "Document fileURL should match disk URL")
assert(docA.fileType == "Markdown Document", "Document fileType should be 'Markdown Document'")

// Window Controller & TextView creation
print("[SCENARIO A] Step 3: Initializing Window Controller and VimMDTextView")
docA.makeWindowControllers()
guard let windowControllerA = docA.windowControllers.first else {
    fatalError("[SCENARIO A FAILURE] Window controller not created")
}
guard let sessionA = docA.session else {
    fatalError("[SCENARIO A FAILURE] VimSession is nil")
}
guard let textViewA = docA.textView else {
    fatalError("[SCENARIO A FAILURE] VimMDTextView is nil")
}

print("  - Window controller title: '\(windowControllerA.window?.title ?? "")'")
print("  - Session valid: \(sessionA.isValid)")
print("  - Document dirty state: \(docA.isDocumentEdited)")
assert(!docA.isDocumentEdited, "Newly opened document must not be edited/dirty")

// Verify TextView content matches file content exactly
print("[SCENARIO A] Step 4: Verifying TextView string matches file content")
print("  - File content length: \(initialMarkdownContent.count) chars")
print("  - TextView string length: \(textViewA.string.count) chars")
assert(textViewA.string == initialMarkdownContent, "TextView content must match initial file content")
assert(sessionA.serializeBuffer() == initialMarkdownContent, "Session buffer must match initial file content")

// Normal mode navigation: j, k, 0, $
print("[SCENARIO A] Step 5: Testing Normal mode navigation (j, k, 0, $)")
print("  - Initial cursor position: Line \(sessionA.cursorPosition.line), Col \(sessionA.cursorPosition.byteCol)")
assert(sessionA.cursorPosition.line == 1 && sessionA.cursorPosition.byteCol == 1)

// Navigate to end of line 1 with '$'
sessionA.feedKeys("$")
let line1Len = initialMarkdownContent.components(separatedBy: "\n")[0].utf8.count
print("  - Cursor after '$': Line \(sessionA.cursorPosition.line), Col \(sessionA.cursorPosition.byteCol)")
assert(sessionA.cursorPosition.line == 1 && sessionA.cursorPosition.byteCol == line1Len)

// Navigate to start of line 1 with '0'
sessionA.feedKeys("0")
print("  - Cursor after '0': Line \(sessionA.cursorPosition.line), Col \(sessionA.cursorPosition.byteCol)")
assert(sessionA.cursorPosition.line == 1 && sessionA.cursorPosition.byteCol == 1)

// Move down to Line 2 ('j') and Line 3 ('j')
sessionA.feedKeys("j")
print("  - Cursor after 'j': Line \(sessionA.cursorPosition.line), Col \(sessionA.cursorPosition.byteCol)")
assert(sessionA.cursorPosition.line == 2)

sessionA.feedKeys("j")
print("  - Cursor after second 'j' (Line 3: '**Status: In Progress**'): Line \(sessionA.cursorPosition.line)")
assert(sessionA.cursorPosition.line == 3)

// Move back up with 'k'
sessionA.feedKeys("k")
print("  - Cursor after 'k': Line \(sessionA.cursorPosition.line)")
assert(sessionA.cursorPosition.line == 2)

sessionA.feedKeys("k")
print("  - Cursor after second 'k': Line \(sessionA.cursorPosition.line)")
assert(sessionA.cursorPosition.line == 1)

// Insert mode edit: Navigate to checklist line and insert '[DONE] ' before task
print("\n[SCENARIO A] Step 6: Performing Insert mode edit: insert '[DONE] ' before checklist item")
// Checklist line is line 11: "- [ ] Ingestion engine performance audit"
// Move down 10 lines with 'j' x 10
sessionA.feedKeys(String(repeating: "j", count: 10))
print("  - Cursor moved to Line \(sessionA.cursorPosition.line): '\(sessionA.serializeBuffer().components(separatedBy: "\n")[sessionA.cursorPosition.line - 1])'")
assert(sessionA.cursorPosition.line == 11)

// Move cursor past '- [ ] ' (6 bytes) to position before 'I'
sessionA.feedKeys(String(repeating: "l", count: 6))
print("  - Cursor byteCol before insertion: \(sessionA.cursorPosition.byteCol)")

// Enter insert mode, type '[DONE] ' and press <Esc>
sessionA.feedKeys("i[DONE] \u{1b}")
print("  - Exited insert mode with <Esc>")
print("  - Mode is now: \(sessionA.mode == VIM_MODE_NORMAL ? "NORMAL" : "OTHER")")
assert(sessionA.mode == VIM_MODE_NORMAL)

// Verify dirty state is detected
print("  - Document edited state (dirty): \(docA.isDocumentEdited)")
assert(docA.isDocumentEdited, "Document should be dirty after insert mode mutation")

let editedLine11 = sessionA.serializeBuffer().components(separatedBy: "\n")[10]
print("  - Edited Line 11 in buffer: '\(editedLine11)'")
assert(editedLine11 == "- [ ] [DONE] Ingestion engine performance audit")
assert(textViewA.string.components(separatedBy: "\n")[10] == "- [ ] [DONE] Ingestion engine performance audit")

// Ex command: :%s/In Progress/Completed/g
print("\n[SCENARIO A] Step 7: Performing Ex substitution :%s/In Progress/Completed/g")
sessionA.executeEx(":%s/In Progress/Completed/g")

let substitutedLine3 = sessionA.serializeBuffer().components(separatedBy: "\n")[2]
print("  - Line 3 in buffer after Ex replacement: '\(substitutedLine3)'")
assert(substitutedLine3 == "**Status: Completed**")
assert(textViewA.string.components(separatedBy: "\n")[2] == "**Status: Completed**")
assert(docA.isDocumentEdited, "Document should still be dirty")

// Save with :w
print("\n[SCENARIO A] Step 8: Saving document with Ex command ':w'")
sessionA.executeEx(":w")

print("  - Document dirty state after :w: \(docA.isDocumentEdited)")
assert(!docA.isDocumentEdited, "Document dirty state must be cleared after save")

// Read and verify file on disk
let diskPayloadA = try String(contentsOf: scenarioAURL, encoding: .utf8)
print("  - Reading persisted content from disk at \(scenarioAURL.path)...")
assert(diskPayloadA.contains("**Status: Completed**"), "Disk file must contain '**Status: Completed**'")
assert(diskPayloadA.contains("- [ ] [DONE] Ingestion engine performance audit"), "Disk file must contain '[DONE]'")
print("  - Disk content verified: Successfully updated with 'Completed' and '[DONE]'!")

// Quit with ZZ
print("\n[SCENARIO A] Step 9: Quitting session with 'ZZ'")
sessionA.feedKeys("ZZ")
print("  - sessionA.shouldQuit: \(sessionA.shouldQuit)")
assert(sessionA.shouldQuit, "session.shouldQuit should be true after ZZ")
print("  - docA.isClosed: \(docA.isClosed)")
assert(docA.isClosed, "Document must be closed cleanly after ZZ")
print("[SCENARIO A] PASSED: Complete Critical User Journey for Scenario A succeeded!\n")


// ============================================================================
// SCENARIO B: Common File Formats (TSV, CSV, TXT, SH)
// ============================================================================
print(">>> [SCENARIO B] Testing Common File Formats (TSV, CSV, TXT, SH)")

struct FormatTestCase {
    let name: String
    let ext: String
    let ofType: String
    let initialContent: String
    let editKeys: String
    let expectedDiskSubstring: String
}

let testCases: [FormatTestCase] = [
    FormatTestCase(
        name: "Tab-Separated Values (TSV)",
        ext: "tsv",
        ofType: "public.tab-separated-values-text",
        initialContent: "id\tname\tstatus\n1\tingestion\tpending\n2\tcompaction\trunning",
        editKeys: "j$\u{1b}:%s/pending/active/g\n",
        expectedDiskSubstring: "1\tingestion\tactive"
    ),
    FormatTestCase(
        name: "Comma-Separated Values (CSV)",
        ext: "csv",
        ofType: "public.comma-separated-values-text",
        initialContent: "host,port,environment\nprod-db-1,5432,staging\nprod-db-2,5432,staging",
        editKeys: "gg:%s/staging/production/g\n",
        expectedDiskSubstring: "prod-db-1,5432,production"
    ),
    FormatTestCase(
        name: "Shell Script (SH)",
        ext: "sh",
        ofType: "public.shell-script",
        initialContent: "#!/usr/bin/env bash\necho 'Deploying v1.0.0'\nexit 0",
        editKeys: "gg:%s/v1.0.0/v2.1.0/g\n",
        expectedDiskSubstring: "echo 'Deploying v2.1.0'"
    ),
    FormatTestCase(
        name: "Plain Text (TXT)",
        ext: "txt",
        ofType: "public.plain-text",
        initialContent: "System Log Entry 2026-10-27\nCluster status: Degraded",
        editKeys: "gg:%s/Degraded/Healthy/g\n",
        expectedDiskSubstring: "Cluster status: Healthy"
    )
]

for tc in testCases {
    print("\n--- Testing Format: \(tc.name) (.\(tc.ext)) ---")
    let fileURL = tempDir.appendingPathComponent("test_data.\(tc.ext)")
    try tc.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
    print("  - Step 1: Created .\(tc.ext) file on disk")

    let doc = try VimMDDocument(contentsOf: fileURL, ofType: tc.ofType)
    doc.makeWindowControllers()
    print("  - Step 2: Instantiated VimMDDocument with ofType: '\(tc.ofType)'")

    guard let session = doc.session, let textView = doc.textView else {
        fatalError("[SCENARIO B FAILURE] Document failed to initialize session or textView for \(tc.ext)")
    }

    assert(textView.string == tc.initialContent, "TextView content mismatch for \(tc.ext)")
    assert(session.serializeBuffer() == tc.initialContent, "Session buffer mismatch for \(tc.ext)")
    assert(!doc.isDocumentEdited, "Initial document should not be dirty for \(tc.ext)")
    print("  - Step 3: Verified content loaded into session and text view without errors")

    // Apply mutation
    session.feedKeys(tc.editKeys)
    print("  - Step 4: Applied edit keys, dirty state: \(doc.isDocumentEdited)")
    assert(doc.isDocumentEdited, "Document should be dirty after edit for \(tc.ext)")

    // Save with :w
    session.executeEx(":w")
    print("  - Step 5: Executed :w, dirty state after save: \(doc.isDocumentEdited)")
    assert(!doc.isDocumentEdited, "Document should be clean after save for \(tc.ext)")

    // Verify on disk
    let diskContent = try String(contentsOf: fileURL, encoding: .utf8)
    assert(diskContent.contains(tc.expectedDiskSubstring), "Persisted content missing expected substring '\(tc.expectedDiskSubstring)' in \(fileURL.path)")
    print("  - Step 6: Verified updated content persisted to disk: contains '\(tc.expectedDiskSubstring)'")

    // Clean close
    session.feedKeys("ZZ")
    assert(doc.isClosed, "Document should close cleanly on ZZ for \(tc.ext)")
    print("  - Step 7: Document closed cleanly for \(tc.ext)")
}

print("\n================================================================================")
print(" ALL CRITICAL USER JOURNEY TESTS COMPLETED SUCCESSFULLY! ")
print("================================================================================")
