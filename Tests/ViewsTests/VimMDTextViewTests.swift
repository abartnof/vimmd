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

func testTextViewSessionBindingAndDeltaSync() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Original Content")
    textView.session = session

    guard textView.string == "Original Content" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "TextView text did not initialize from session: '\(textView.string)'"])
    }

    // Apply delta from Ex command or session
    session.executeEx(":%s/Original/Updated/g")
    guard textView.string == "Updated Content" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "TextView did not reflect delta update: '\(textView.string)'"])
    }
}

func testTextViewNormalModeInterception() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "First Line\nSecond Line")
    textView.session = session

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Normal mode"])
    }

    // Simulate keyDown in normal mode: 'j' moves down to line 2
    let eventJ = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "j",
        charactersIgnoringModifiers: "j",
        isARepeat: false,
        keyCode: 38 // 'j'
    )!
    textView.keyDown(with: eventJ)

    guard session.cursorPosition.line == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cursor did not advance to line 2, got \(session.cursorPosition)"])
    }
    guard textView.selectedRange().location == session.cursorUtf16Offset else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Caret location mismatch, got \(textView.selectedRange().location), expected \(session.cursorUtf16Offset)"])
    }
}

func testTextViewInsertModeTextInputClient() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Start ")
    textView.session = session

    // Switch to insert mode via 'A' (append)
    session.feedKeys("A")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Insert mode"])
    }

    // Test NSTextInputClient insertText
    textView.insertText("Added", replacementRange: NSRange(location: NSNotFound, length: 0))
    guard session.serializeBuffer() == "Start Added" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "InsertText failed to route to session, got '\(session.serializeBuffer())'"])
    }

    // Test Escape key returning to Normal mode
    let eventEsc = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53 // Esc
    )!
    textView.keyDown(with: eventEsc)

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected mode to return to NORMAL after Esc"])
    }
}

func testImeMarkedTextLifecycle() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    guard !textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Should not have marked text initially"])
    }

    textView.setMarkedText("日本語", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    guard textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected marked text to be active"])
    }
    guard textView.markedRange().length == 3 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected marked length 3, got \(textView.markedRange().length)"])
    }

    textView.unmarkText()
    guard !textView.hasMarkedText() else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected no marked text after unmarkText"])
    }
}

func testAttributedSubstring() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    textView.string = "Alpha Beta Gamma"

    var actualRange = NSRange(location: 0, length: 0)
    let substring = textView.attributedSubstring(forProposedRange: NSRange(location: 6, length: 4), actualRange: &actualRange)

    guard substring?.string == "Beta" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected substring 'Beta', got '\(String(describing: substring?.string))'"])
    }
    guard actualRange == NSRange(location: 6, length: 4) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Actual range mismatch: \(actualRange)"])
    }
}

func testVisualModeKeyInterception() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Selectable Text")
    textView.session = session

    session.feedKeys("v")
    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Visual mode"])
    }

    let eventL = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "l",
        charactersIgnoringModifiers: "l",
        isARepeat: false,
        keyCode: 37
    )!
    textView.keyDown(with: eventL)

    guard session.cursorPosition.byteCol == 2 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Visual mode cursor col expected 2, got \(session.cursorPosition.byteCol)"])
    }

    let eventEsc = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
    )!
    textView.keyDown(with: eventEsc)

    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected return to Normal mode after Esc"])
    }
}

func testNilSessionSafety() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    // session is nil
    textView.synchronizeCaretWithSession()
    textView.applyDelta(startLine: 1, deletedCount: 0, newLines: ["Safe"])
    textView.insertText("No crash", replacementRange: NSRange(location: 0, length: 0))

    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "a",
        charactersIgnoringModifiers: "a",
        isARepeat: false,
        keyCode: 0
    )!
    textView.keyDown(with: event)
    // Passes if no crash
}

func testTextViewOpenLineMutations() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Line 1\nLine 2")
    textView.session = session

    // 'o' opens line below line 1
    session.feedKeys("oInserted Below\u{1b}")
    guard textView.string == "Line 1\nInserted Below\nLine 2" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed 'o' insertion sync, got: '\(textView.string)'"])
    }

    // 'O' opens line above line 1
    session.feedKeys("gg")
    session.feedKeys("OTop Header\u{1b}")
    guard textView.string == "Top Header\nLine 1\nInserted Below\nLine 2" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed 'O' insertion sync, got: '\(textView.string)'"])
    }
}

func testTextViewFirstResponderAndCaretSelection() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    guard textView.acceptsFirstResponder else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected acceptsFirstResponder to be true"])
    }
    guard textView.becomeFirstResponder() else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected becomeFirstResponder to return true"])
    }
    guard textView.resignFirstResponder() else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected resignFirstResponder to return true"])
    }

    textView.setSelectedRange(NSRange(location: 3, length: 0), affinity: .downstream, stillSelecting: false)
    guard textView.selectedRange().location == 3 else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected selectedRange location 3, got \(textView.selectedRange().location)"])
    }
}

func testTextViewDirectInsertModeKeyHandling() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Initial")
    textView.session = session

    // Enter insert mode with 'i'
    let eventI = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34)!
    textView.keyDown(with: eventI)
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected mode to be INSERT"])
    }

    // Type character 'X' in insert mode via keyDown
    let eventX = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "X", charactersIgnoringModifiers: "X", isARepeat: false, keyCode: 7)!
    textView.keyDown(with: eventX)
    guard session.serializeBuffer().contains("XInitial") else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected X to be inserted before Initial, got '\(session.serializeBuffer())'"])
    }

    // Type Backspace (keyCode 51)
    let eventBS = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
    textView.keyDown(with: eventBS)
    guard session.serializeBuffer() == "Initial" else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected X to be deleted by Backspace, got '\(session.serializeBuffer())'"])
    }

    // Escape back to NORMAL (keyCode 53)
    let eventEsc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    textView.keyDown(with: eventEsc)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected mode to return to NORMAL"])
    }
}

func testTextViewModeAndCursorMovedCallbacks() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Hello World")
    textView.session = session

    var modeChanges = 0
    var cursorMoves = 0

    textView.onModeChanged = { _ in modeChanges += 1 }
    textView.onCursorMoved = { cursorMoves += 1 }

    // 'i' triggers mode change and cursor move
    let eventI = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "i", charactersIgnoringModifiers: "i", isARepeat: false, keyCode: 34)!
    textView.keyDown(with: eventI)
    guard modeChanges >= 1 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected onModeChanged when entering INSERT"])
    }

    // 'Z' in insert mode triggers cursor move
    let eventZ = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "Z", charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6)!
    textView.keyDown(with: eventZ)
    guard cursorMoves >= 1 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected onCursorMoved when typing"])
    }

    // Esc back to normal
    let eventEsc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    textView.keyDown(with: eventEsc)
    guard modeChanges >= 2 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected onModeChanged when exiting INSERT"])
    }
}

func testTextViewCommandHotkeysPreservation() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Immutable Text")
    textView.session = session

    // 1. In NORMAL mode, Cmd+V must NOT switch mode to VISUAL!
    let eventCmdV = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "v",
        charactersIgnoringModifiers: "v",
        isARepeat: false,
        keyCode: 9 // 'v'
    )!
    textView.keyDown(with: eventCmdV)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cmd+V in NORMAL mode caused mode transition to \(session.modeString)! Expected NORMAL."])
    }

    // 2. In NORMAL mode, Cmd+X must NOT delete character ('x')
    let eventCmdX = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "x",
        charactersIgnoringModifiers: "x",
        isARepeat: false,
        keyCode: 7 // 'x'
    )!
    textView.keyDown(with: eventCmdX)
    guard session.serializeBuffer() == "Immutable Text" else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cmd+X in NORMAL mode mutated buffer: '\(session.serializeBuffer())'! Expected 'Immutable Text'."])
    }
}

func testTextViewMarkdownRenderingInNormalMode() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "# Header\nThis is **bold** text.")
    textView.session = session

    guard let storage = textView.textStorage else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected textStorage"])
    }

    // Line 1 is H1 -> 22pt bold
    let h1Font = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
    guard let f = h1Font, f.pointSize == 22 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header font in Normal mode, got \(String(describing: h1Font))"])
    }

    // Line 2 has bold text
    let boldLoc = (storage.string as NSString).range(of: "bold").location
    let boldFont = storage.attribute(.font, at: boldLoc, effectiveRange: nil) as? NSFont
    guard let bf = boldFont, NSFontManager.shared.traits(of: bf).contains(.boldFontMask) else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected bold trait in Normal mode"])
    }
}

func testTextViewMarkdownFormattingPermanentInInsertMode() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "# Header Line\n**Bold Line Two**")
    textView.session = session

    // Enter insert mode on Line 1
    session.feedKeys("i")
    textView.updateSyntaxStyling(force: true)

    guard let storage = textView.textStorage else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected textStorage"])
    }

    // Line 1 is active in insert mode -> MUST retain 22pt bold header font (permanent formatting)
    let line1Font = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
    guard let l1f = line1Font, l1f.pointSize == 22, NSFontManager.shared.traits(of: l1f).contains(.boldFontMask) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected active line in insert mode to permanently retain 22pt bold header font, got \(String(describing: line1Font))"])
    }

    // Line 2 is inactive in insert mode -> rendered markdown bold
    let line2Loc = (storage.string as NSString).range(of: "Bold Line Two").location
    let line2Font = storage.attribute(.font, at: line2Loc, effectiveRange: nil) as? NSFont
    guard let l2f = line2Font, NSFontManager.shared.traits(of: l2f).contains(.boldFontMask) else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected inactive line to maintain bold styling"])
    }
}

func testTextViewModeTransitionPreservesMarkdownFormatting() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "# Header")
    textView.session = session

    guard let storage = textView.textStorage else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected textStorage"])
    }

    // Normal mode -> 22pt header
    var font = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
    guard font?.pointSize == 22 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header font in Normal mode"])
    }

    // Transition to Insert mode -> STILL 22pt header!
    session.feedKeys("i")
    textView.updateSyntaxStyling(force: true)
    font = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
    guard font?.pointSize == 22, let f = font, NSFontManager.shared.traits(of: f).contains(.boldFontMask) else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header font preserved in Insert mode"])
    }

    // Escape back to Normal mode -> 22pt header
    session.feedKeys("\u{1b}")
    textView.updateSyntaxStyling(force: true)
    font = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
    guard font?.pointSize == 22 else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected 22pt header font after returning to Normal mode"])
    }
}

func testTextViewInsertModeCursorMoveMaintainsStyling() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "# Line One\n## Line Two")
    textView.session = session

    // Enter insert mode on Line 1
    session.feedKeys("i")
    textView.updateSyntaxStyling(force: true)

    guard let storage = textView.textStorage else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected textStorage"])
    }

    // Line 1 (22pt bold), Line 2 (18pt bold)
    var fontL1 = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
    let l2Offset = (storage.string as NSString).range(of: "Line Two").location
    var fontL2 = storage.attribute(.font, at: l2Offset, effectiveRange: nil) as? NSFont
    guard fontL1?.pointSize == 22, fontL2?.pointSize == 18 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial insert mode styling mismatch"])
    }

    // Move cursor to Line 2 while remaining in Insert mode
    session.setCursor(line: 2, byteCol: 1)
    textView.updateSyntaxStyling(force: true)

    // Both lines must maintain their header formatting
    fontL1 = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
    fontL2 = storage.attribute(.font, at: l2Offset, effectiveRange: nil) as? NSFont
    guard fontL1?.pointSize == 22, fontL2?.pointSize == 18 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Header styling should persist across cursor moves in Insert mode"])
    }
}

func testTextViewDynamicFrameHeightExpansion() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
    let multiline = (1...60).map { "Line \($0): A long document line with some text." }.joined(separator: "\n")
    let session = VimSession(initialText: multiline)
    textView.session = session

    // Ensure frame height expanded to accommodate multiline text
    guard textView.frame.size.height >= 500 else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected text view frame height to expand for multiline text, got \(textView.frame.size.height)"])
    }
}

class TrackingScrollTextView: VimMDTextView {
    var lastScrolledRange: NSRange?
    override func scrollRangeToVisible(_ range: NSRange) {
        lastScrolledRange = range
        super.scrollRangeToVisible(range)
    }
}

func testCaretAutoScrollInvocation() throws {
    let textView = TrackingScrollTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let multiline = (1...30).map { "Line \($0)" }.joined(separator: "\n")
    let session = VimSession(initialText: multiline)
    textView.session = session

    // Move cursor down with 'j'
    let eventJ = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "j",
        charactersIgnoringModifiers: "j",
        isARepeat: false,
        keyCode: 38
    )!
    textView.keyDown(with: eventJ)

    guard let scrolled = textView.lastScrolledRange else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "scrollRangeToVisible was never called after cursor navigation"])
    }
    guard scrolled.location == session.cursorUtf16Offset else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "scrollRangeToVisible called with range \(scrolled), expected \(session.cursorUtf16Offset)"])
    }
}

func testResponsiveTypingInInsertModeMarkdownStyling() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "")
    textView.session = session

    // Enter insert mode
    session.feedKeys("i")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Insert mode"])
    }

    // Type '**live bold**' live in insert mode
    for ch in "**live bold**" {
        session.feedKeys(String(ch))
    }

    guard let storage = textView.textStorage else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected textStorage"])
    }

    let boldLoc = (storage.string as NSString).range(of: "live bold").location
    guard boldLoc != NSNotFound else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "String missing 'live bold': '\(storage.string)'"])
    }

    let boldFont = storage.attribute(.font, at: boldLoc, effectiveRange: nil) as? NSFont
    guard let bf = boldFont, NSFontManager.shared.traits(of: bf).contains(.boldFontMask) else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Typing in Insert mode did not responsively apply bold styling: \(String(describing: boldFont))"])
    }

    // Now type CommonMark edge case: '\n*this is not italic, but *this* is'
    session.feedKeys("\r")
    for ch in "*this is not italic, but *this* is" {
        session.feedKeys(String(ch))
    }

    let notItalicLoc = (storage.string as NSString).range(of: "this is not italic").location
    let notItalicFont = storage.attribute(.font, at: notItalicLoc, effectiveRange: nil) as? NSFont
    guard let nif = notItalicFont, !NSFontManager.shared.traits(of: nif).contains(.italicFontMask) else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "'this is not italic' must not be italic"])
    }

    let isItalicLoc = (storage.string as NSString).range(of: "this* is").location
    let isItalicFont = storage.attribute(.font, at: isItalicLoc, effectiveRange: nil) as? NSFont
    guard let iif = isItalicFont, NSFontManager.shared.traits(of: iif).contains(.italicFontMask) else {
        throw NSError(domain: "ViewsTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "'*this*' must be italic"])
    }
}

class TrackingScrollView: NSScrollView {
    var receivedScrollWheel = false
    override func scrollWheel(with event: NSEvent) {
        receivedScrollWheel = true
    }
}

func testScrollWheelForwarding() throws {
    let scrollView = TrackingScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
    scrollView.documentView = textView

    let dummyEvent = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: 0
    )!
    textView.scrollWheel(with: dummyEvent)

    guard scrollView.receivedScrollWheel else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "scrollWheel was not forwarded to enclosing scroll view"])
    }
}

func testTextViewCaretAlignmentMatchesRawOffsets() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "# Line One\n**Bold Text**\n`Code`")
    textView.session = session

    // Normal mode: cursor at line 2 col 3
    session.setCursor(line: 2, byteCol: 3)
    textView.synchronizeCaretWithSession()
    guard textView.selectedRange().location == session.cursorUtf16Offset else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Caret offset mismatch in Normal mode"])
    }

    // Insert mode: cursor at line 3 col 2
    session.feedKeys("i")
    session.setCursor(line: 3, byteCol: 2)
    textView.synchronizeCaretWithSession()
    guard textView.selectedRange().location == session.cursorUtf16Offset else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Caret offset mismatch in Insert mode"])
    }
}

func testTextViewVisualTextObjectSelection() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "let value = 'highlighted text';")
    textView.session = session

    // Position cursor inside single quotes
    session.setCursor(line: 1, byteCol: 18)
    textView.synchronizeCaretWithSession()

    // Feed 'v', 'i', '\''
    session.feedKeys("v")
    session.feedKeys("i")
    session.feedKeys("'")
    textView.synchronizeCaretWithSession()

    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Visual mode"])
    }
    let selected = textView.selectedRange()
    guard selected.location != NSNotFound && selected.length == 16 else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected selection length 16 for 'highlighted text', got \(selected)"])
    }
    let sub = (textView.string as NSString).substring(with: selected)
    guard sub == "highlighted text" else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Selected text mismatch: '\(sub)'"])
    }
}

func testTextViewSearchKeyNavigation() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "first target\nsecond target\nthird target")
    textView.session = session

    // Send '/' via keyDown
    let eventSlash = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "/", charactersIgnoringModifiers: "/", isARepeat: false, keyCode: 44)!
    textView.keyDown(with: eventSlash)
    guard session.mode == VIM_MODE_COMMAND else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected Command mode after '/'"])
    }

    // Type 't', 'a', 'r', 'g', 'e', 't', '\r'
    let eventWord = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "target\r", charactersIgnoringModifiers: "target\r", isARepeat: false, keyCode: 36)!
    textView.keyDown(with: eventWord)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected Normal mode after Return"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 7 else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cursor mismatch after search: \(session.cursorPosition)"])
    }

    // Press 'n' via keyDown
    let eventN = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "n", charactersIgnoringModifiers: "n", isARepeat: false, keyCode: 45)!
    textView.keyDown(with: eventN)
    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 8 else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cursor mismatch after 'n': \(session.cursorPosition)"])
    }
}

func testTextViewCopyAndPasteSynchronizedWithSystemPasteboard() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let session = VimSession(initialText: "Hello VimMD World\nSecond line")
    textView.session = session

    // 1. In Normal mode without selection: copy() yanks current line ('yy')
    textView.copy(nil as Any?)
    let pbText = NSPasteboard.general.string(forType: .string) ?? ""
    guard pbText.contains("Hello VimMD World") else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "copy() in normal mode did not copy current line to pasteboard: '\(pbText)'"])
    }

    // 2. In Visual mode: 'v3l' selects 'Hell', copy() yanks selection and returns to normal
    session.feedKeys("v3l")
    guard session.mode == VIM_MODE_VISUAL else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected Visual mode"])
    }
    textView.copy(nil as Any?)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected Normal mode after visual copy()"])
    }
    let pbVisual = NSPasteboard.general.string(forType: .string) ?? ""
    guard pbVisual == "Hell" else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Visual copy() did not yank 'Hell': '\(pbVisual)'"])
    }

    // 3. Pasteboard paste() in normal mode pastes clipboard text
    let newClip = " [COPIED] "
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(newClip, forType: .string)

    textView.paste(nil as Any?)
    let contentAfterPaste = textView.string
    guard contentAfterPaste.contains(newClip) else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "paste() did not insert clipboard text: '\(contentAfterPaste)'"])
    }
}

class MockMenuItem: NSObject, NSValidatedUserInterfaceItem {
    let action: Selector?
    let tag: Int
    init(action: Selector?, tag: Int = 0) {
        self.action = action
        self.tag = tag
        super.init()
    }
}

func testTextViewUndoRedoCommandKeys() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let initial = "Sample text for undo test"
    let session = VimSession(initialText: initial)
    textView.session = session

    // Normal mode delete character 'S' with 'x'
    let eventX = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
    textView.keyDown(with: eventX)

    guard textView.string == "ample text for undo test" else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 'ample text for undo test', got '\(textView.string)'"])
    }

    // Cmd+Z: Undo
    let eventCmdZ = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "z",
        charactersIgnoringModifiers: "z",
        isARepeat: false,
        keyCode: 6 // 'z'
    )!
    textView.keyDown(with: eventCmdZ)

    guard textView.string == initial else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected Cmd+Z to restore initial string, got '\(textView.string)'"])
    }

    // Cmd+Shift+Z: Redo
    let eventCmdShiftZ = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command, .shift],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "Z",
        charactersIgnoringModifiers: "z",
        isARepeat: false,
        keyCode: 6 // 'z'
    )!
    textView.keyDown(with: eventCmdShiftZ)

    guard textView.string == "ample text for undo test" else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected Cmd+Shift+Z to redo deletion, got '\(textView.string)'"])
    }
}

func testTextViewUndoRedoActionMethods() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let initial = "Alpha Beta Gamma"
    let session = VimSession(initialText: initial)
    textView.session = session

    let undoItem = MockMenuItem(action: #selector(VimMDTextView.undo(_:)))
    let redoItem = MockMenuItem(action: #selector(VimMDTextView.redo(_:)))

    // Initially cannot undo or redo
    guard !textView.validateUserInterfaceItem(undoItem) else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected undo to be disabled initially"])
    }
    guard !textView.validateUserInterfaceItem(redoItem) else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected redo to be disabled initially"])
    }

    // Make an edit: delete word 'Alpha ' with 'dw'
    session.feedKeys("dw")
    guard textView.string == "Beta Gamma" else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 'Beta Gamma', got '\(textView.string)'"])
    }

    guard textView.validateUserInterfaceItem(undoItem) else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected undo to be enabled after edit"])
    }
    guard !textView.validateUserInterfaceItem(redoItem) else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected redo to be disabled after edit"])
    }

    // Call undo(_:)
    textView.undo(nil as Any?)
    guard textView.string == initial else {
        throw NSError(domain: "ViewsTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected undo(_:) to restore initial, got '\(textView.string)'"])
    }

    guard !textView.validateUserInterfaceItem(undoItem) else {
        throw NSError(domain: "ViewsTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected undo to be disabled after full undo"])
    }
    guard textView.validateUserInterfaceItem(redoItem) else {
        throw NSError(domain: "ViewsTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected redo to be enabled after undo"])
    }

    // Call redo(_:)
    textView.redo(nil as Any?)
    guard textView.string == "Beta Gamma" else {
        throw NSError(domain: "ViewsTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected redo(_:) to reapply edit, got '\(textView.string)'"])
    }
}

func testTextViewUndoManagerIntegration() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let initial = "First Line\nSecond Line"
    let session = VimSession(initialText: initial)
    textView.session = session

    guard let mgr = textView.undoManager else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil undoManager"])
    }

    guard !mgr.canUndo && !mgr.canRedo else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "undoManager should report cannot undo/redo initially"])
    }

    // Mutate
    session.feedKeys("dd")
    guard mgr.canUndo && !mgr.canRedo else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "undoManager should allow undo after dd"])
    }

    mgr.undo()
    guard textView.string == initial else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "mgr.undo() failed: '\(textView.string)'"])
    }

    guard !mgr.canUndo && mgr.canRedo else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "undoManager state after undo incorrect"])
    }

    mgr.redo()
    guard textView.string == "Second Line" else {
        throw NSError(domain: "ViewsTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "mgr.redo() failed: '\(textView.string)'"])
    }
}

func testTextViewWrapLinesPropertyAndConfiguration() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    scrollView.documentView = textView

    // 1. Initial default state: wrapLines == true
    guard textView.wrapLines == true else {
        throw NSError(domain: "ViewsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default wrapLines must be true"])
    }
    guard textView.textContainer?.widthTracksTextView == true else {
        throw NSError(domain: "ViewsTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "widthTracksTextView must be true when wrapLines == true"])
    }
    guard textView.isHorizontallyResizable == false else {
        throw NSError(domain: "ViewsTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "isHorizontallyResizable must be false when wrapLines == true"])
    }
    guard scrollView.hasHorizontalScroller == false else {
        throw NSError(domain: "ViewsTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalScroller must be false when wrapLines == true"])
    }

    // 2. Set wrapLines = false (unwrapped / horizontal scroll)
    textView.wrapLines = false
    guard textView.wrapLines == false else {
        throw NSError(domain: "ViewsTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "wrapLines must be false"])
    }
    guard textView.textContainer?.widthTracksTextView == false else {
        throw NSError(domain: "ViewsTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "widthTracksTextView must be false when wrapLines == false"])
    }
    guard textView.textContainer?.containerSize.width == CGFloat.greatestFiniteMagnitude else {
        throw NSError(domain: "ViewsTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "containerSize.width must be greatestFiniteMagnitude when wrapLines == false"])
    }
    guard textView.isHorizontallyResizable == true else {
        throw NSError(domain: "ViewsTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "isHorizontallyResizable must be true when wrapLines == false"])
    }
    guard textView.maxSize.width == CGFloat.greatestFiniteMagnitude else {
        throw NSError(domain: "ViewsTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "maxSize.width must be greatestFiniteMagnitude when wrapLines == false"])
    }
    guard scrollView.hasHorizontalScroller == true else {
        throw NSError(domain: "ViewsTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalScroller must be true when wrapLines == false"])
    }

    // 3. Test horizontal frame expansion with a wide line
    let wideLine = String(repeating: "tabular_data_col_value\t", count: 20)
    let session = VimSession(initialText: wideLine)
    textView.session = session
    textView.updateFrameHeightToFitText()

    guard textView.frame.size.width > 400 else {
        throw NSError(domain: "ViewsTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected textView frame width to expand beyond 400 for wide text when wrapLines == false, got \(textView.frame.size.width)"])
    }

    // 4. Toggle back to wrapLines == true
    textView.wrapLines = true
    guard textView.wrapLines == true else {
        throw NSError(domain: "ViewsTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "wrapLines must be true"])
    }
    guard textView.textContainer?.widthTracksTextView == true else {
        throw NSError(domain: "ViewsTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "widthTracksTextView must restore to true"])
    }
    guard let containerWidth = textView.textContainer?.containerSize.width, abs(containerWidth - 400) < 1.0 else {
        throw NSError(domain: "ViewsTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "containerSize.width must restore to contentWidth, got \(String(describing: textView.textContainer?.containerSize.width))"])
    }
    guard textView.isHorizontallyResizable == false else {
        throw NSError(domain: "ViewsTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "isHorizontallyResizable must restore to false"])
    }
    guard scrollView.hasHorizontalScroller == false else {
        throw NSError(domain: "ViewsTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "hasHorizontalScroller must restore to false"])
    }

    // 5. User interface validation checkmark tests (validateUserInterfaceItem)
    let menuItem = NSMenuItem(title: "Wrap Lines", action: #selector(VimMDTextView.toggleWrapLines(_:)), keyEquivalent: "")
    let isValidOn = textView.validateUserInterfaceItem(menuItem)
    guard isValidOn else {
        throw NSError(domain: "ViewsTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "validateUserInterfaceItem returned false for toggleWrapLines"])
    }
    guard menuItem.state == .on else {
        throw NSError(domain: "ViewsTests", code: 18, userInfo: [NSLocalizedDescriptionKey: "menuItem.state should be .on when wrapLines == true"])
    }

    textView.wrapLines = false
    let isValidOff = textView.validateUserInterfaceItem(menuItem)
    guard isValidOff else {
        throw NSError(domain: "ViewsTests", code: 19, userInfo: [NSLocalizedDescriptionKey: "validateUserInterfaceItem returned false for toggleWrapLines"])
    }
    guard menuItem.state == .off else {
        throw NSError(domain: "ViewsTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "menuItem.state should be .off when wrapLines == false"])
    }

    // 6. toggleWrapLines action method
    textView.toggleWrapLines(nil)
    guard textView.wrapLines == true else {
        throw NSError(domain: "ViewsTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "toggleWrapLines should flip wrapLines to true"])
    }
    textView.toggleWrapLines(nil)
    guard textView.wrapLines == false else {
        throw NSError(domain: "ViewsTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "toggleWrapLines should flip wrapLines back to false"])
    }
}

print("=== VimMDTextView Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testTextViewSessionBindingAndDeltaSync", testTextViewSessionBindingAndDeltaSync),
    ("testTextViewNormalModeInterception", testTextViewNormalModeInterception),
    ("testTextViewInsertModeTextInputClient", testTextViewInsertModeTextInputClient),
    ("testImeMarkedTextLifecycle", testImeMarkedTextLifecycle),
    ("testAttributedSubstring", testAttributedSubstring),
    ("testVisualModeKeyInterception", testVisualModeKeyInterception),
    ("testNilSessionSafety", testNilSessionSafety),
    ("testTextViewOpenLineMutations", testTextViewOpenLineMutations),
    ("testTextViewFirstResponderAndCaretSelection", testTextViewFirstResponderAndCaretSelection),
    ("testTextViewDirectInsertModeKeyHandling", testTextViewDirectInsertModeKeyHandling),
    ("testTextViewModeAndCursorMovedCallbacks", testTextViewModeAndCursorMovedCallbacks),
    ("testTextViewCommandHotkeysPreservation", testTextViewCommandHotkeysPreservation),
    ("testTextViewMarkdownRenderingInNormalMode", testTextViewMarkdownRenderingInNormalMode),
    ("testTextViewMarkdownFormattingPermanentInInsertMode", testTextViewMarkdownFormattingPermanentInInsertMode),
    ("testTextViewModeTransitionPreservesMarkdownFormatting", testTextViewModeTransitionPreservesMarkdownFormatting),
    ("testTextViewInsertModeCursorMoveMaintainsStyling", testTextViewInsertModeCursorMoveMaintainsStyling),
    ("testTextViewDynamicFrameHeightExpansion", testTextViewDynamicFrameHeightExpansion),
    ("testCaretAutoScrollInvocation", testCaretAutoScrollInvocation),
    ("testResponsiveTypingInInsertModeMarkdownStyling", testResponsiveTypingInInsertModeMarkdownStyling),
    ("testScrollWheelForwarding", testScrollWheelForwarding),
    ("testTextViewCaretAlignmentMatchesRawOffsets", testTextViewCaretAlignmentMatchesRawOffsets),
    ("testTextViewVisualTextObjectSelection", testTextViewVisualTextObjectSelection),
    ("testTextViewSearchKeyNavigation", testTextViewSearchKeyNavigation),
    ("testTextViewCopyAndPasteSynchronizedWithSystemPasteboard", testTextViewCopyAndPasteSynchronizedWithSystemPasteboard),
    ("testTextViewUndoRedoCommandKeys", testTextViewUndoRedoCommandKeys),
    ("testTextViewUndoRedoActionMethods", testTextViewUndoRedoActionMethods),
    ("testTextViewUndoManagerIntegration", testTextViewUndoManagerIntegration),
    ("testTextViewWrapLinesPropertyAndConfiguration", testTextViewWrapLinesPropertyAndConfiguration)
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
