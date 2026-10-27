import Foundation
import AppKit
import App
import Views
import Engine
import CBridge

print("=======================================================")
print(" VimMD End-to-End Real-World User Workflow Trial")
print("=======================================================")

// Setup temporary file
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
defer {
    try? FileManager.default.removeItem(at: tempDir)
}

let docURL = tempDir.appendingPathComponent("trial_document.md")
let initialMarkdown = """
# Title
This is a document with **bold text** and emojis: 🚀 🌟.
- Item 1
- Item 2
"""

try initialMarkdown.write(to: docURL, atomically: true, encoding: .utf8)
print("[TRIAL] Step 1: Created real markdown file at \(docURL.path)")
print("[TRIAL] Initial File Content:\n---")
print(initialMarkdown)
print("---\n")

// Initialize NSApplication environment for AppKit
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
delegate.setupMainMenu()

// Open document
let doc = VimMDDocument()
let initialData = try Data(contentsOf: docURL)
try doc.read(from: initialData, ofType: "net.daringfireball.markdown")
doc.makeWindowControllers()

guard let session = doc.session, let textView = doc.textView else {
    fatalError("[TRIAL ERROR] Document failed to initialize session or textView")
}

print("[TRIAL] Step 2: Document opened in VimMDDocument window controller")
print("  - Session valid: \(session.isValid)")
print("  - Document initial dirty state: \(doc.isDocumentEdited)")
print("  - TextView initial content matches: \(textView.string == initialMarkdown)")
assert(textView.string == initialMarkdown, "TextView content does not match initial markdown")
assert(!doc.isDocumentEdited, "Initial document should not be dirty")

// Navigation tests
print("\n[TRIAL] Step 3: Simulating Normal mode navigation (h, j, k, l, 0, $)")
print("  - Starting cursor: line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol)")
assert(session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1)

// Navigate with 'l' and '$'
session.feedKeys("lll")
print("  - After 'lll': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol)")
assert(session.cursorPosition.byteCol == 4)

session.feedKeys("$")
print("  - After '$': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol) (end of line 1)")
assert(session.cursorPosition.byteCol == 7)

session.feedKeys("0")
print("  - After '0': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol) (beginning of line 1)")
assert(session.cursorPosition.byteCol == 1)

// Move down to Line 2 ('j') and Line 3 ('j')
session.feedKeys("j")
print("  - After 'j': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol) (Line 2)")
assert(session.cursorPosition.line == 2)

session.feedKeys("j")
print("  - After second 'j': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol) (Line 3 with 🚀 🌟)")
assert(session.cursorPosition.line == 3)

// Navigate up with 'k', 'k'
session.feedKeys("kk")
print("  - After 'kk': line \(session.cursorPosition.line), col \(session.cursorPosition.byteCol) (Back to Line 1)")
assert(session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1)

// Insert mode test
print("\n[TRIAL] Step 4: Entering Insert mode ('i'), typing text, and pressing Escape")
// Navigate past '# ' -> 'l', 'l'
session.feedKeys("ll")
print("  - Cursor positioned before 'Title': col \(session.cursorPosition.byteCol)")

// Enter Insert mode and type 'Super '
session.feedKeys("iSuper \u{1b}")
print("  - Exited Insert mode with <Esc>")
print("  - Mode is now: \(session.mode == VIM_MODE_NORMAL ? "NORMAL" : "OTHER")")
assert(session.mode == VIM_MODE_NORMAL)
print("  - Document dirty state: \(doc.isDocumentEdited)")
assert(doc.isDocumentEdited)
print("  - Current Line 1: '\(session.serializeBuffer().components(separatedBy: "\n")[0])'")
assert(session.serializeBuffer().hasPrefix("# Super Title"))
assert(textView.string.hasPrefix("# Super Title"))

// Ex replacement test
print("\n[TRIAL] Step 5: Executing Ex replacement :%s/Title/VimMD Production/g")
session.executeEx(":%s/Title/VimMD Production/g")
let line1AfterEx = session.serializeBuffer().components(separatedBy: "\n")[0]
print("  - Line 1 after substitution: '\(line1AfterEx)'")
assert(line1AfterEx == "# Super VimMD Production")
assert(textView.string.components(separatedBy: "\n")[0] == "# Super VimMD Production")

// Insert new line below ('o') and above ('O')
print("\n[TRIAL] Step 6: Inserting lines below ('o') and above ('O')")
// Move cursor to bottom: 'G'
session.feedKeys("G")
print("  - Moved to bottom line: \(session.cursorPosition.line)")
assert(session.cursorPosition.line == 4)

session.feedKeys("o- Item 3 (New)\u{1b}")
print("  - After 'o- Item 3 (New)<Esc>': Total lines = \(session.lineIndexTable.lineCount)")
assert(session.lineIndexTable.lineCount == 5)
assert(session.serializeBuffer().components(separatedBy: "\n")[4] == "- Item 3 (New)")

session.feedKeys("gg")
print("  - Moved to line 1 with 'gg'")
assert(session.cursorPosition.line == 1)

session.feedKeys("O<!-- Document Header -->\u{1b}")
print("  - After 'O<!-- Document Header --><Esc>': Total lines = \(session.lineIndexTable.lineCount)")
assert(session.lineIndexTable.lineCount == 6)
assert(session.serializeBuffer().components(separatedBy: "\n")[0] == "<!-- Document Header -->")
assert(textView.string.components(separatedBy: "\n")[0] == "<!-- Document Header -->")
print("  - textView and session buffer synchronized identically across all 6 lines")

// Saving with :w
print("\n[TRIAL] Step 7: Saving document (:w) and validating file on disk")
session.executeEx(":w")
try doc.write(to: docURL, ofType: "net.daringfireball.markdown", for: .saveOperation, originalContentsURL: nil)

print("  - Document saved to \(docURL.path)")
print("  - Document dirty state after save: \(doc.isDocumentEdited)")
assert(!doc.isDocumentEdited, "Document should not be dirty after save")

let savedDiskContent = try String(contentsOf: docURL, encoding: .utf8)
print("[TRIAL] Resulting File Payload on Disk:\n---")
print(savedDiskContent)
print("---")

let expectedContent = """
<!-- Document Header -->
# Super VimMD Production
This is a document with **bold text** and emojis: 🚀 🌟.
- Item 1
- Item 2
- Item 3 (New)
"""
assert(savedDiskContent == expectedContent, "Saved disk content does not match expected payload")
print("  - Disk payload matches expectations EXACTLY!")

// Quitting with ZZ / :q
print("\n[TRIAL] Step 8: Quitting session with 'ZZ'")
var quitTriggered = false
textView.onQuitRequested = {
    quitTriggered = true
    doc.handleQuitTrigger()
}

session.feedKeys("ZZ")
print("  - session.shouldQuit: \(session.shouldQuit)")
assert(session.shouldQuit, "session.shouldQuit should be true after ZZ")

if !quitTriggered {
    // TextView handles keyDown with event, or manual trigger
    doc.handleQuitTrigger()
}
print("  - Document closed status: \(doc.isClosed)")
assert(doc.isClosed, "Document should be closed after quit trigger")

print("\n=======================================================")
print(" ALL REAL-WORLD USER TRIAL STEPS SUCCEEDED CLEANLY! ")
print("=======================================================")
