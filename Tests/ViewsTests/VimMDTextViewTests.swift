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
    ("testTextViewCaretAlignmentMatchesRawOffsets", testTextViewCaretAlignmentMatchesRawOffsets)
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
