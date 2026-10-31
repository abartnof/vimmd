import Foundation
import AppKit
import App
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

func testModeThemePaletteColors() throws {
    // Normal: Grey / Slate
    let normalColor = VimModeTheme.color(for: VIM_MODE_NORMAL)
    guard let rgbNormal = normalColor.usingColorSpace(.deviceRGB) else {
        throw NSError(domain: "ThemeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Normal color cannot convert to deviceRGB"])
    }
    // Slate grey: balanced, gentle cool grey (R, G, B relatively close, not overly saturated)
    guard abs(rgbNormal.redComponent - rgbNormal.greenComponent) < 0.25 &&
          abs(rgbNormal.greenComponent - rgbNormal.blueComponent) < 0.25 else {
        throw NSError(domain: "ThemeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Normal mode color must be a gentle grey/slate, got \(rgbNormal)"])
    }

    // Insert: Gentle, cohesive Blue
    let insertColor = VimModeTheme.color(for: VIM_MODE_INSERT)
    guard let rgbInsert = insertColor.usingColorSpace(.deviceRGB) else {
        throw NSError(domain: "ThemeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Insert color cannot convert to deviceRGB"])
    }
    guard rgbInsert.blueComponent > rgbInsert.redComponent && rgbInsert.blueComponent > 0.4 else {
        throw NSError(domain: "ThemeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Insert mode color must be a cohesive blue, got \(rgbInsert)"])
    }

    // Visual: Harmonious Royal Purple / Soft Magenta
    let visualColor = VimModeTheme.color(for: VIM_MODE_VISUAL)
    guard let rgbVisual = visualColor.usingColorSpace(.deviceRGB) else {
        throw NSError(domain: "ThemeTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Visual color cannot convert to deviceRGB"])
    }
    guard rgbVisual.redComponent > 0.35 && rgbVisual.blueComponent > 0.45 && rgbVisual.blueComponent > rgbVisual.greenComponent else {
        throw NSError(domain: "ThemeTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Visual mode color must be purple/magenta, got \(rgbVisual)"])
    }

    // Command: Warm safety amber / soft orange-red
    let commandColor = VimModeTheme.color(for: VIM_MODE_COMMAND)
    guard let rgbCommand = commandColor.usingColorSpace(.deviceRGB) else {
        throw NSError(domain: "ThemeTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Command color cannot convert to deviceRGB"])
    }
    guard rgbCommand.redComponent > 0.6 && rgbCommand.greenComponent > 0.25 && rgbCommand.redComponent > rgbCommand.blueComponent else {
        throw NSError(domain: "ThemeTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Command mode color must be warm safety amber/orange-red, got \(rgbCommand)"])
    }

    // Replace: Distinct accent (soft teal / cyan)
    let replaceColor = VimModeTheme.color(for: VIM_MODE_REPLACE)
    guard let rgbReplace = replaceColor.usingColorSpace(.deviceRGB) else {
        throw NSError(domain: "ThemeTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Replace color cannot convert to deviceRGB"])
    }
    guard rgbReplace.greenComponent > 0.4 && rgbReplace.blueComponent > 0.4 && rgbReplace.greenComponent > rgbReplace.redComponent else {
        throw NSError(domain: "ThemeTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Replace mode color must be distinct soft teal/accent, got \(rgbReplace)"])
    }
}

func testCursorMorphologyMapping() throws {
    guard VimModeTheme.cursorMorphology(for: VIM_MODE_NORMAL) == .block else {
        throw NSError(domain: "ThemeTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Normal mode must have .block morphology"])
    }

    guard case .verticalBar = VimModeTheme.cursorMorphology(for: VIM_MODE_INSERT) else {
        throw NSError(domain: "ThemeTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Insert mode must have .verticalBar morphology"])
    }

    guard VimModeTheme.cursorMorphology(for: VIM_MODE_VISUAL) == .block else {
        throw NSError(domain: "ThemeTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Visual mode must have .block morphology"])
    }

    let replaceMorph = VimModeTheme.cursorMorphology(for: VIM_MODE_REPLACE)
    guard replaceMorph == .underline || replaceMorph == .halfBlock else {
        throw NSError(domain: "ThemeTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Replace mode must have .underline or .halfBlock morphology, got \(replaceMorph)"])
    }
}

func testCursorRectCalculations() throws {
    let baseRect = NSRect(x: 20.0, y: 15.0, width: 8.0, height: 16.0)

    // 1. Block: solid full-cell covering current glyph
    let blockRect = VimModeTheme.calculateCursorRect(for: .block, proposedRect: baseRect, cellWidth: 8.0)
    guard blockRect == NSRect(x: 20.0, y: 15.0, width: 8.0, height: 16.0) else {
        throw NSError(domain: "ThemeTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected full-cell block rect \(baseRect), got \(blockRect)"])
    }

    // 2. Vertical Bar: 1.5–2pt bar between characters
    let barRect = VimModeTheme.calculateCursorRect(for: .verticalBar(width: 2.0), proposedRect: baseRect, cellWidth: 8.0)
    guard barRect.origin.x == 20.0 && barRect.origin.y == 15.0 && barRect.height == 16.0 else {
        throw NSError(domain: "ThemeTests", code: 16, userInfo: [NSLocalizedDescriptionKey: "Bar origin and height must match baseRect, got \(barRect)"])
    }
    guard barRect.width >= 1.5 && barRect.width <= 2.0 else {
        throw NSError(domain: "ThemeTests", code: 17, userInfo: [NSLocalizedDescriptionKey: "Bar width must be 1.5–2.0pt, got \(barRect.width)"])
    }

    // 3. Underline: horizontal line at the base of the character
    let underlineRect = VimModeTheme.calculateCursorRect(for: .underline(height: 2.5), proposedRect: baseRect, cellWidth: 8.0)
    guard underlineRect.origin.x == 20.0 && underlineRect.width == 8.0 else {
        throw NSError(domain: "ThemeTests", code: 18, userInfo: [NSLocalizedDescriptionKey: "Underline origin x and width must match glyph cell, got \(underlineRect)"])
    }
    guard underlineRect.maxY == baseRect.maxY else {
        throw NSError(domain: "ThemeTests", code: 19, userInfo: [NSLocalizedDescriptionKey: "Underline must be placed at the base (bottom) of the character cell, expected maxY \(baseRect.maxY), got \(underlineRect.maxY)"])
    }
    guard underlineRect.height >= 1.5 && underlineRect.height <= 3.0 else {
        throw NSError(domain: "ThemeTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Underline height must be 1.5–3.0pt, got \(underlineRect.height)"])
    }

    // 4. Half Block: half-height block at the base of the character
    let halfBlockRect = VimModeTheme.calculateCursorRect(for: .halfBlock, proposedRect: baseRect, cellWidth: 8.0)
    guard halfBlockRect.origin.x == 20.0 && halfBlockRect.width == 8.0 else {
        throw NSError(domain: "ThemeTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Half block origin x and width must match glyph cell, got \(halfBlockRect)"])
    }
    guard halfBlockRect.maxY == baseRect.maxY && halfBlockRect.height == 8.0 else {
        throw NSError(domain: "ThemeTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Half block must cover bottom half of cell, got \(halfBlockRect)"])
    }
}

func testTextViewCaretMorphologyAndImmediateRedrawOnModeChange() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "Hello Vim World")
    textView.session = session
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    // Initial state: Normal mode
    guard textView.caretMorphology == .block else {
        throw NSError(domain: "ThemeTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "TextView initial caret morphology must be .block, got \(textView.caretMorphology)"])
    }
    let normalColor = VimModeTheme.color(for: VIM_MODE_NORMAL)
    guard textView.insertionPointColor == normalColor else {
        throw NSError(domain: "ThemeTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "TextView initial insertionPointColor must match Normal theme color"])
    }

    let initialCaretRect = textView.currentCaretRect
    guard initialCaretRect.width > 2.0 else {
        throw NSError(domain: "ThemeTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Normal mode caret rect must cover glyph width, got \(initialCaretRect)"])
    }

    // Transition to Insert mode: 'i'
    let eventI = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "i",
        charactersIgnoringModifiers: "i",
        isARepeat: false,
        keyCode: 34
    )!
    textView.keyDown(with: eventI)

    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ThemeTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected Insert mode"])
    }
    guard case .verticalBar = textView.caretMorphology else {
        throw NSError(domain: "ThemeTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "TextView caret morphology in Insert mode must be .verticalBar, got \(textView.caretMorphology)"])
    }
    let insertColor = VimModeTheme.color(for: VIM_MODE_INSERT)
    guard textView.insertionPointColor == insertColor else {
        throw NSError(domain: "ThemeTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "TextView insertionPointColor in Insert mode must match Insert theme color"])
    }
    let insertCaretRect = textView.currentCaretRect
    guard insertCaretRect.width >= 1.5 && insertCaretRect.width <= 2.5 else {
        throw NSError(domain: "ThemeTests", code: 29, userInfo: [NSLocalizedDescriptionKey: "Insert mode caret rect must be 1.5–2pt bar, got \(insertCaretRect)"])
    }

    // Transition to Replace mode: Esc then 'R'
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

    let eventR = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.shift],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "R",
        charactersIgnoringModifiers: "R",
        isARepeat: false,
        keyCode: 15
    )!
    textView.keyDown(with: eventR)

    guard session.mode == VIM_MODE_REPLACE else {
        throw NSError(domain: "ThemeTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Expected Replace mode, got \(session.mode)"])
    }
    let replaceMorph = textView.caretMorphology
    guard replaceMorph == .underline || replaceMorph == .halfBlock else {
        throw NSError(domain: "ThemeTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "TextView caret morphology in Replace mode must be .underline or .halfBlock, got \(replaceMorph)"])
    }
    let replaceColor = VimModeTheme.color(for: VIM_MODE_REPLACE)
    guard textView.insertionPointColor == replaceColor else {
        throw NSError(domain: "ThemeTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "TextView insertionPointColor in Replace mode must match Replace theme color"])
    }
    let replaceCaretRect = textView.currentCaretRect
    guard replaceCaretRect.width > 2.0 && replaceCaretRect.height < initialCaretRect.height else {
        throw NSError(domain: "ThemeTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Replace mode caret rect must be underline/half-height at base, got \(replaceCaretRect)"])
    }

    // Transition back to Normal mode
    textView.keyDown(with: eventEsc)
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ThemeTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected Normal mode after Esc"])
    }
    guard textView.caretMorphology == .block else {
        throw NSError(domain: "ThemeTests", code: 35, userInfo: [NSLocalizedDescriptionKey: "TextView caret morphology must restore to .block, got \(textView.caretMorphology)"])
    }
    guard textView.insertionPointColor == normalColor else {
        throw NSError(domain: "ThemeTests", code: 36, userInfo: [NSLocalizedDescriptionKey: "TextView insertionPointColor must restore to Normal color"])
    }
}

func testDocumentStatusBarModeLabelStyling() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()

    guard let modeLabel = doc.modeLabel else {
        throw NSError(domain: "ThemeTests", code: 37, userInfo: [NSLocalizedDescriptionKey: "doc.modeLabel is nil"])
    }
    guard doc.messageLabel != nil else {
        throw NSError(domain: "ThemeTests", code: 38, userInfo: [NSLocalizedDescriptionKey: "doc.messageLabel is nil"])
    }
    guard let session = doc.session else {
        throw NSError(domain: "ThemeTests", code: 39, userInfo: [NSLocalizedDescriptionKey: "doc.session is nil"])
    }

    // 1. Normal mode styling
    doc.updateStatusDisplay()
    guard !modeLabel.isHidden && (modeLabel.stringValue == "NORMAL" || modeLabel.stringValue == "-- NORMAL --") else {
        throw NSError(domain: "ThemeTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Expected visible 'NORMAL', got '\(modeLabel.stringValue)'"])
    }
    let normalColor = VimModeTheme.color(for: VIM_MODE_NORMAL)
    guard modeLabel.badgeColor == normalColor || modeLabel.textColor == normalColor else {
        throw NSError(domain: "ThemeTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "modeLabel badgeColor must match Normal theme color, got \(String(describing: modeLabel.badgeColor))"])
    }

    // 2. Insert mode styling
    session.feedKeys("i")
    doc.updateStatusDisplay()
    guard !modeLabel.isHidden && (modeLabel.stringValue == "INSERT" || modeLabel.stringValue == "-- INSERT --") else {
        throw NSError(domain: "ThemeTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected visible 'INSERT', got '\(modeLabel.stringValue)'"])
    }
    let insertColor = VimModeTheme.color(for: VIM_MODE_INSERT)
    guard modeLabel.badgeColor == insertColor || modeLabel.textColor == insertColor else {
        throw NSError(domain: "ThemeTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "modeLabel badgeColor must match Insert theme color, got \(String(describing: modeLabel.badgeColor))"])
    }

    // 3. Replace mode styling
    session.feedKeys("\u{1b}R")
    doc.updateStatusDisplay()
    guard !modeLabel.isHidden && (modeLabel.stringValue == "REPLACE" || modeLabel.stringValue == "-- REPLACE --") else {
        throw NSError(domain: "ThemeTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Expected visible 'REPLACE', got '\(modeLabel.stringValue)'"])
    }
    let replaceColor = VimModeTheme.color(for: VIM_MODE_REPLACE)
    guard modeLabel.badgeColor == replaceColor || modeLabel.textColor == replaceColor else {
        throw NSError(domain: "ThemeTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "modeLabel badgeColor must match Replace theme color, got \(String(describing: modeLabel.badgeColor))"])
    }

    // 4. Visual mode styling
    session.feedKeys("\u{1b}v")
    doc.updateStatusDisplay()
    guard !modeLabel.isHidden && (modeLabel.stringValue == "VISUAL" || modeLabel.stringValue == "-- VISUAL --") else {
        throw NSError(domain: "ThemeTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "Expected visible 'VISUAL', got '\(modeLabel.stringValue)'"])
    }
    let visualColor = VimModeTheme.color(for: VIM_MODE_VISUAL)
    guard modeLabel.badgeColor == visualColor || modeLabel.textColor == visualColor else {
        throw NSError(domain: "ThemeTests", code: 47, userInfo: [NSLocalizedDescriptionKey: "modeLabel badgeColor must match Visual theme color, got \(String(describing: modeLabel.badgeColor))"])
    }

    // 5. Command mode styling
    session.feedKeys("\u{1b}:")
    doc.updateStatusDisplay()
    guard modeLabel.isHidden else {
        throw NSError(domain: "ThemeTests", code: 48, userInfo: [NSLocalizedDescriptionKey: "modeLabel must be hidden in Command mode"])
    }
}

func testInsertionBaseRectAtEOF() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let str = "Hello World"
    textView.string = str
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let eofIndex = str.count
    let rect = textView.insertionBaseRect(at: eofIndex)
    guard rect.origin.x > 50.0 else {
        throw NSError(domain: "ThemeTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "EOF rect for '\(str)' must be at the end of text (x > 50), got \(rect)"])
    }
}

func testInsertionBaseRectAtEOFTrailingNewline() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let str = "Line 1\n"
    textView.string = str
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let line1Rect = textView.insertionBaseRect(at: 0)
    let eofIndex = (str as NSString).length
    let eofRect = textView.insertionBaseRect(at: eofIndex)
    guard eofRect.origin.y > line1Rect.origin.y else {
        throw NSError(domain: "ThemeTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "EOF rect with trailing newline must be on line 2 (y > \(line1Rect.origin.y)), got \(eofRect.origin.y)"])
    }
    guard eofRect.origin.x == textView.textContainerInset.width else {
        throw NSError(domain: "ThemeTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "EOF rect on empty new line must start at margin x=\(textView.textContainerInset.width), got \(eofRect.origin.x)"])
    }
}

func testMultibyteAndSurrogatePairCursor() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "🎉 Rocket")
    textView.session = session
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let width = textView.glyphCellWidth(at: 0)
    guard width > 8.0 else {
        throw NSError(domain: "ThemeTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Emoji glyph cell width must be non-zero and cover emoji, got \(width)"])
    }

    let caretRect = textView.currentCaretRect
    guard caretRect.width >= width else {
        throw NSError(domain: "ThemeTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "Caret rect for emoji must cover emoji cell width, got \(caretRect)"])
    }
}

func testInsertModeBlinkOffDoesNotDrawCharacter() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "ABC")
    textView.session = session
    session.feedKeys("i")
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    textView.drawInsertionPoint(in: NSRect(x: 10, y: 10, width: 2, height: 16), color: .systemBlue, turnedOn: true)
    textView.drawInsertionPoint(in: NSRect(x: 10, y: 10, width: 2, height: 16), color: .systemBlue, turnedOn: false)

    NSGraphicsContext.restoreGraphicsState()
}

func testHeadingFontSizeCaretScaling() throws {
    let textView = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "# Large Heading\nBody text")
    textView.session = session
    textView.documentSyntaxType = .markdown
    textView.updateSyntaxStyling(force: true)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let headingRect = textView.insertionBaseRect(at: 2)
    let bodyIndex = (("# Large Heading\n" as NSString).length)
    let bodyRect = textView.insertionBaseRect(at: bodyIndex)

    guard headingRect.height > bodyRect.height + 4.0 else {
        throw NSError(domain: "ThemeTests", code: 55, userInfo: [NSLocalizedDescriptionKey: "Heading caret height (\(headingRect.height)) must be substantially larger than body caret height (\(bodyRect.height))"])
    }
}

print("=== Cursor Morphology & Mode Theme Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testModeThemePaletteColors", testModeThemePaletteColors),
    ("testCursorMorphologyMapping", testCursorMorphologyMapping),
    ("testCursorRectCalculations", testCursorRectCalculations),
    ("testTextViewCaretMorphologyAndImmediateRedrawOnModeChange", testTextViewCaretMorphologyAndImmediateRedrawOnModeChange),
    ("testDocumentStatusBarModeLabelStyling", testDocumentStatusBarModeLabelStyling),
    ("testInsertionBaseRectAtEOF", testInsertionBaseRectAtEOF),
    ("testInsertionBaseRectAtEOFTrailingNewline", testInsertionBaseRectAtEOFTrailingNewline),
    ("testMultibyteAndSurrogatePairCursor", testMultibyteAndSurrogatePairCursor),
    ("testInsertModeBlinkOffDoesNotDrawCharacter", testInsertModeBlinkOffDoesNotDrawCharacter),
    ("testHeadingFontSizeCaretScaling", testHeadingFontSizeCaretScaling)
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
