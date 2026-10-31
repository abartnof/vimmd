import Foundation
import AppKit
import Views
import Engine
import CBridge
import App

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

// 1. Verify ModeBadgeView & VimModeTheme text & colors across all modes
func testStatusBarModeBadgeStylingAndColors() throws {
    // Verify VimModeTheme.modeBadgeText strings: clean uppercase, no enclosing dashes
    guard VimModeTheme.modeBadgeText(for: VIM_MODE_NORMAL) == "NORMAL" else {
        throw NSError(domain: "ModeBadgesTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 'NORMAL', got '\(VimModeTheme.modeBadgeText(for: VIM_MODE_NORMAL))'"])
    }
    guard VimModeTheme.modeBadgeText(for: VIM_MODE_INSERT) == "INSERT" else {
        throw NSError(domain: "ModeBadgesTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 'INSERT', got '\(VimModeTheme.modeBadgeText(for: VIM_MODE_INSERT))'"])
    }
    guard VimModeTheme.modeBadgeText(for: VIM_MODE_VISUAL) == "VISUAL" else {
        throw NSError(domain: "ModeBadgesTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 'VISUAL', got '\(VimModeTheme.modeBadgeText(for: VIM_MODE_VISUAL))'"])
    }
    guard VimModeTheme.modeBadgeText(for: VIM_MODE_REPLACE) == "REPLACE" else {
        throw NSError(domain: "ModeBadgesTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected 'REPLACE', got '\(VimModeTheme.modeBadgeText(for: VIM_MODE_REPLACE))'"])
    }

    // Verify ModeBadgeView
    let badge = ModeBadgeView(frame: NSRect(x: 8, y: 3, width: 68, height: 16))
    badge.mode = VIM_MODE_NORMAL
    guard badge.stringValue == "NORMAL" else {
        throw NSError(domain: "ModeBadgesTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "ModeBadgeView stringValue mismatch: \(badge.stringValue)"])
    }
    guard badge.badgeColor == VimModeTheme.normalColor else {
        throw NSError(domain: "ModeBadgesTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Normal badgeColor mismatch"])
    }
    guard badge.textColor == NSColor.white else {
        throw NSError(domain: "ModeBadgesTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Badge textColor must be white"])
    }

    badge.mode = VIM_MODE_INSERT
    guard badge.stringValue == "INSERT" && badge.badgeColor == VimModeTheme.insertColor else {
        throw NSError(domain: "ModeBadgesTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Insert mode badge styling mismatch"])
    }

    badge.mode = VIM_MODE_VISUAL
    guard badge.stringValue == "VISUAL" && badge.badgeColor == VimModeTheme.visualColor else {
        throw NSError(domain: "ModeBadgesTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Visual mode badge styling mismatch"])
    }

    badge.mode = VIM_MODE_REPLACE
    guard badge.stringValue == "REPLACE" && badge.badgeColor == VimModeTheme.replaceColor else {
        throw NSError(domain: "ModeBadgesTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Replace mode badge styling mismatch"])
    }
}

// 2. Verify Document Mode Pill integration and Command mode prompt behavior
func testDocumentModeBadgeIntegrationAndCommandModeHiding() throws {
    let doc = try VimMDDocument(type: "public.plain-text")
    doc.makeWindowControllers()

    guard let badge = doc.modeBadgeView else {
        throw NSError(domain: "ModeBadgesTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "doc.modeBadgeView is nil"])
    }
    guard let msgLabel = doc.messageLabel else {
        throw NSError(domain: "ModeBadgesTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "doc.messageLabel is nil"])
    }
    guard let session = doc.session else {
        throw NSError(domain: "ModeBadgesTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "doc.session is nil"])
    }

    // Initial NORMAL state
    doc.updateStatusDisplay()
    guard !badge.isHidden && badge.stringValue == "NORMAL" else {
        throw NSError(domain: "ModeBadgesTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected visible NORMAL pill, got '\(badge.stringValue)', isHidden=\(badge.isHidden)"])
    }
    guard badge.badgeColor == VimModeTheme.normalColor else {
        throw NSError(domain: "ModeBadgesTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Expected normalColor"])
    }
    // Verify text aligns with document text body left margin (default 41.0pt) and origin is past gutter (x > 8)
    let textLeftMargin = doc.textBodyLeftMargin()
    guard textLeftMargin >= 36.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected textBodyLeftMargin >= 36.0, got \(textLeftMargin)"])
    }
    guard badge.frame.origin.x > 8.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Badge origin x should be moved past gutter (x > 8), got \(badge.frame.origin.x)"])
    }
    guard abs(badge.textOriginXInSuperview - textLeftMargin) < 1.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Badge text origin (\(badge.textOriginXInSuperview)) must align with textBodyLeftMargin (\(textLeftMargin))"])
    }

    // Switch to INSERT
    session.feedKeys("i")
    doc.updateStatusDisplay()
    guard !badge.isHidden && badge.stringValue == "INSERT" && badge.badgeColor == VimModeTheme.insertColor else {
        throw NSError(domain: "ModeBadgesTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected visible INSERT pill with insertColor"])
    }

    // Switch to REPLACE
    session.feedKeys("\u{1b}R")
    doc.updateStatusDisplay()
    guard !badge.isHidden && badge.stringValue == "REPLACE" && badge.badgeColor == VimModeTheme.replaceColor else {
        throw NSError(domain: "ModeBadgesTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Expected visible REPLACE pill with replaceColor"])
    }

    // Switch to VISUAL
    session.feedKeys("\u{1b}v")
    doc.updateStatusDisplay()
    guard !badge.isHidden && badge.stringValue == "VISUAL" && badge.badgeColor == VimModeTheme.visualColor else {
        throw NSError(domain: "ModeBadgesTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "Expected visible VISUAL pill with visualColor"])
    }

    // Switch to COMMAND (':')
    session.feedKeys("\u{1b}:")
    doc.updateStatusDisplay()
    guard badge.isHidden else {
        throw NSError(domain: "ModeBadgesTests", code: 29, userInfo: [NSLocalizedDescriptionKey: "Mode badge pill must be hidden in COMMAND mode"])
    }
    guard msgLabel.frame.origin.x == 8 else {
        throw NSError(domain: "ModeBadgesTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Message label must start at x = 8 during COMMAND mode, got \(msgLabel.frame.origin.x)"])
    }

    // Cancel COMMAND mode back to NORMAL
    session.feedKeys("\u{1b}")
    doc.updateStatusDisplay()
    guard !badge.isHidden && badge.stringValue == "NORMAL" else {
        throw NSError(domain: "ModeBadgesTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Mode badge pill must be restored to NORMAL after escaping COMMAND mode"])
    }
}

// 3. Verify LineNumberRulerView active row badge geometry and pill dimensions
func testLineNumberRulerBadgeGeometry() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    ruler.clientView = tv
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true
    ruler.ruleThickness = 40.0

    // 1-digit line number: sleek pill by default (height: 16.0, width > height)
    let rect1 = ruler.activeRowBadgeRect(for: 1, y: 0.0, rowHeight: 18.0)
    guard rect1.height == 16.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Expected height 16.0, got \(rect1.height)"])
    }
    guard rect1.width > rect1.height else {
        throw NSError(domain: "ModeBadgesTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "1-digit line number must be a sleek pill (width > height): width=\(rect1.width), height=\(rect1.height)"])
    }
    // Vertical buffer: 1.0pt top and bottom within 18pt frame
    guard rect1.origin.y == 1.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected badge y == 1.0 within 18pt row, got \(rect1.origin.y)"])
    }

    // 2-digit line number: expands leftward
    let rect99 = ruler.activeRowBadgeRect(for: 99, y: 0.0, rowHeight: 18.0)
    guard rect99.height == 16.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected height 16.0, got \(rect99.height)"])
    }
    guard rect99.width > rect1.width else {
        throw NSError(domain: "ModeBadgesTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "2-digit pill width (\(rect99.width)) should exceed 1-digit pill width (\(rect1.width))"])
    }

    // 3-digit line number: expands further leftward without clipping
    let rect100 = ruler.activeRowBadgeRect(for: 100, y: 0.0, rowHeight: 18.0)
    guard rect100.height == 16.0 else {
        throw NSError(domain: "ModeBadgesTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Expected height 16.0, got \(rect100.height)"])
    }
    guard rect100.width > rect99.width else {
        throw NSError(domain: "ModeBadgesTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "3-digit pill width (\(rect100.width)) must exceed 2-digit pill width (\(rect99.width))"])
    }

    // 4-digit line number: expands further proportionally
    let rect1000 = ruler.activeRowBadgeRect(for: 1000, y: 0.0, rowHeight: 18.0)
    guard rect1000.width > rect100.width else {
        throw NSError(domain: "ModeBadgesTests", code: 47, userInfo: [NSLocalizedDescriptionKey: "4-digit line number capsule (\(rect1000.width)) must be wider than 3-digit capsule (\(rect100.width))"])
    }

    // Exact mathematical symmetry (top == bottom, left == right, and baseline parity with inactive text)
    for num in [1, 9, 42, 99, 100, 999, 1000] {
        let badgeRect = ruler.activeRowBadgeRect(for: num, y: 0.0, rowHeight: 18.0)
        let textRect = ruler.lineNumberTextRect(for: num, y: 0.0, rowHeight: 18.0, isActive: true)
        let topMargin = textRect.minY - badgeRect.minY
        let bottomMargin = badgeRect.maxY - textRect.maxY
        let leftMargin = textRect.minX - badgeRect.minX
        let rightMargin = badgeRect.maxX - textRect.maxX

        guard abs(topMargin - bottomMargin) < 0.1 else {
            throw NSError(domain: "ModeBadgesTests", code: 48, userInfo: [NSLocalizedDescriptionKey: "Vertical margin asymmetry for line \(num): top=\(topMargin), bottom=\(bottomMargin)"])
        }
        guard abs(leftMargin - rightMargin) < 0.1 else {
            throw NSError(domain: "ModeBadgesTests", code: 49, userInfo: [NSLocalizedDescriptionKey: "Horizontal margin asymmetry for line \(num): left=\(leftMargin), right=\(rightMargin)"])
        }

        let inactiveTextRect = ruler.lineNumberTextRect(for: num, y: 0.0, rowHeight: 18.0, isActive: false)
        guard abs(textRect.origin.y - inactiveTextRect.origin.y) < 0.01 else {
            throw NSError(domain: "ModeBadgesTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Active and inactive textY must match for baseline parity: active=\(textRect.origin.y), inactive=\(inactiveTextRect.origin.y)"])
        }
        guard abs(textRect.maxX - inactiveTextRect.maxX) < 0.01 else {
            throw NSError(domain: "ModeBadgesTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Active and inactive right edge must align at same column: active=\(textRect.maxX), inactive=\(inactiveTextRect.maxX)"])
        }
    }
}

// 4. Verify synchronous ruler redraw propagation on mode changes
func testSynchronousModeStatePropagation() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "Alpha\nBeta\nGamma")
    tv.session = session
    scrollView.documentView = tv

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
    window.contentView?.addSubview(scrollView)

    ruler.needsDisplay = false

    // Transition from NORMAL to INSERT
    session.feedKeys("i")
    guard session.mode == VIM_MODE_INSERT else {
        throw NSError(domain: "ModeBadgesTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Expected INSERT mode"])
    }
    guard ruler.needsDisplay else {
        throw NSError(domain: "ModeBadgesTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Ruler needsDisplay must be true synchronously after mode change to INSERT"])
    }

    // Reset needsDisplay and transition back to NORMAL
    ruler.needsDisplay = false
    session.feedKeys("\u{1b}")
    guard session.mode == VIM_MODE_NORMAL else {
        throw NSError(domain: "ModeBadgesTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "Expected NORMAL mode"])
    }
    guard ruler.needsDisplay else {
        throw NSError(domain: "ModeBadgesTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Ruler needsDisplay must be true synchronously after mode change to NORMAL"])
    }
}

// 5. Verify LineNumberRulerView drawing execution across all modes
func testLineNumberRulerDrawingInDifferentModes() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let session = VimSession(initialText: "First line\nSecond line\nThird line\nFourth line\nFifth line")
    tv.session = session
    scrollView.documentView = tv

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler
    scrollView.rulersVisible = true

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
    window.contentView?.addSubview(scrollView)

    let image = NSImage(size: NSSize(width: max(1, ruler.bounds.width), height: max(1, ruler.bounds.height)))

    let keySequences = ["", "i", "\u{1b}v", "\u{1b}R", "\u{1b}"]
    for keys in keySequences {
        if !keys.isEmpty {
            session.feedKeys(keys)
        }
        image.lockFocus()
        ruler.draw(ruler.bounds)
        image.unlockFocus()
    }
}

print("=== Mode Badges & Theme Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testStatusBarModeBadgeStylingAndColors", testStatusBarModeBadgeStylingAndColors),
    ("testDocumentModeBadgeIntegrationAndCommandModeHiding", testDocumentModeBadgeIntegrationAndCommandModeHiding),
    ("testLineNumberRulerBadgeGeometry", testLineNumberRulerBadgeGeometry),
    ("testSynchronousModeStatePropagation", testSynchronousModeStatePropagation),
    ("testLineNumberRulerDrawingInDifferentModes", testLineNumberRulerDrawingInDifferentModes)
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
