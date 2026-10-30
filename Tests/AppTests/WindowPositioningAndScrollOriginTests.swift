import Foundation
import AppKit
import App
import Views
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

func expectedScrollOriginX(for scrollView: NSScrollView) -> CGFloat {
    return (scrollView.hasVerticalRuler && scrollView.rulersVisible) ? -(scrollView.verticalRulerView?.ruleThickness ?? 0) : 0
}

func testWindowPlacementInTopLeftQuadrant() throws {
    // Reset any cascade state before testing
    VimMDDocument.lastTopLeftPoint = nil

    let doc = VimMDDocument()
    let text = "# Test Top Left\nLine 1\nLine 2"
    try doc.read(from: text.data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc.makeWindowControllers()

    guard let window = doc.windowControllers.first?.window else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Window is nil"])
    }

    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

    // Window must be positioned in the top-left quadrant of the screen visibleFrame.
    // In Cocoa screen coordinates:
    // visibleFrame.maxY is the top boundary.
    // visibleFrame.minX is the left boundary.
    let windowTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

    // The top-left corner must be near the top: maxY within top 15% of visible height
    let allowedTopDeviation: CGFloat = max(80.0, visibleFrame.height * 0.15)
    guard abs(windowTopLeft.y - visibleFrame.maxY) <= allowedTopDeviation else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Window top \(windowTopLeft.y) is not near screen top \(visibleFrame.maxY) (frame: \(window.frame), visibleFrame: \(visibleFrame))"]
        )
    }

    // The top-left corner must be near the left edge: minX within 100 pt of visibleFrame.minX
    guard abs(windowTopLeft.x - visibleFrame.minX) <= 100.0 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Window left \(windowTopLeft.x) is not near screen left \(visibleFrame.minX) (frame: \(window.frame), visibleFrame: \(visibleFrame))"]
        )
    }

    // Must NOT be placed at the old hardcoded bottom location y=100
    guard window.frame.origin.y > 150.0 || visibleFrame.height <= 200 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Window is placed near bottom (y=\(window.frame.origin.y)) instead of top-left"]
        )
    }

    doc.close()
}

func testWindowCascadingFromTopLeft() throws {
    VimMDDocument.lastTopLeftPoint = nil

    let doc1 = VimMDDocument()
    try doc1.read(from: "# Doc 1".data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc1.makeWindowControllers()
    guard let win1 = doc1.windowControllers.first?.window else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    let doc2 = VimMDDocument()
    try doc2.read(from: "# Doc 2".data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc2.makeWindowControllers()
    guard let win2 = doc2.windowControllers.first?.window else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: nil)
    }

    let top1 = NSPoint(x: win1.frame.minX, y: win1.frame.maxY)
    let top2 = NSPoint(x: win2.frame.minX, y: win2.frame.maxY)

    // Doc 2 must cascade (offset from doc 1)
    guard top1 != top2 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Doc 2 window was not cascaded; identical top-left \(top1)"]
        )
    }

    doc1.close()
    doc2.close()
}

func testWideMarkdownFileOpensAtScrollOriginZero() throws {
    let doc = VimMDDocument()
    // Create a 5,000 character wide markdown heading
    let wideHeading = "# " + String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ", count: 200) + "\nSecond Line"
    guard let data = wideHeading.data(using: .utf8) else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    try doc.read(from: data, ofType: "net.daringfireball.markdown")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "doc.textView is nil"])
    }
    guard let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "enclosingScrollView is nil"])
    }

    // Force layout / ensure text view width has expanded to accommodate wide text
    tv.updateFrameForUnwrappedLines()

    guard tv.frame.width > 2000 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected text view frame width > 2000 for 5200 char line, got \(tv.frame.width)"])
    }

    // Crucial check: documentVisibleRect and clipView origin MUST be ruler-aware at top-left, NOT scrolled to the right!
    let visibleOrigin = scrollView.documentVisibleRect.origin
    let clipOrigin = scrollView.contentView.bounds.origin
    let expectedX = expectedScrollOriginX(for: scrollView)

    guard abs(visibleOrigin.x - expectedX) < 0.5 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "documentVisibleRect scrolled to right! x=\(visibleOrigin.x), expected \(expectedX)"]
        )
    }
    guard abs(visibleOrigin.y) < 0.001 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "documentVisibleRect scrolled vertically! y=\(visibleOrigin.y), expected 0"]
        )
    }
    guard abs(clipOrigin.x - expectedX) < 0.5 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "contentView.bounds.origin.x=\(clipOrigin.x), expected \(expectedX)"]
        )
    }

    doc.close()
}

func testReadWithExistingTextViewResetsScrollOrigin() throws {
    let doc = VimMDDocument()
    let initialText = "# Initial\nLine"
    try doc.read(from: initialText.data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    // Expand view and scroll horizontally to simulate a scrolled state
    tv.wrapLines = false
    tv.setFrameSize(NSSize(width: 4000, height: 1000))
    scrollView.contentView.scroll(to: NSPoint(x: 350, y: 150))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    guard scrollView.documentVisibleRect.origin.x > 100 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to simulate scrolled state"])
    }

    // Now read a new file into the existing document
    let newWideText = "# New Wide File " + String(repeating: "X", count: 3000)
    try doc.read(from: newWideText.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

    // After read, origin must be reset to ruler-aware top-left
    let visibleOrigin = scrollView.documentVisibleRect.origin
    let expectedX = expectedScrollOriginX(for: scrollView)
    guard abs(visibleOrigin.x - expectedX) < 0.5 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Expected visible origin x to be \(expectedX) after read, got \(visibleOrigin.x)"]
        )
    }
    guard abs(visibleOrigin.y) < 0.001 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Expected visible origin y to be 0 after read, got \(visibleOrigin.y)"]
        )
    }

    doc.close()
}

func testSynchronizeCaretAtOriginKeepsScrollOriginZeroOnWideContent() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    scrollView.documentView = tv
    tv.wrapLines = false

    let wideText = String(repeating: "Hello World Wide Line ", count: 200)
    let session = VimSession(initialText: wideText)
    tv.session = session

    tv.updateFrameForUnwrappedLines()

    // Position caret at 0 and synchronize
    session.setCursor(line: 1, byteCol: 1)
    tv.synchronizeCaretWithSession()

    let visibleOrigin = scrollView.documentVisibleRect.origin
    guard abs(visibleOrigin.x) < 0.001 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synchronizeCaretWithSession moved origin x to \(visibleOrigin.x)"]
        )
    }
    guard abs(visibleOrigin.y) < 0.001 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "synchronizeCaretWithSession moved origin y to \(visibleOrigin.y)"]
        )
    }
}

func testResetScrollToTopLeftMethod() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 3000, height: 2000))
    scrollView.documentView = tv

    // Artificially scroll away from top-left
    scrollView.contentView.scroll(to: NSPoint(x: 450, y: 300))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    guard scrollView.documentVisibleRect.origin.x > 400 && scrollView.documentVisibleRect.origin.y > 200 else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scroll setup failed"])
    }

    tv.resetScrollToTopLeft()

    guard abs(scrollView.documentVisibleRect.origin.x) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "resetScrollToTopLeft did not reset x: \(scrollView.documentVisibleRect.origin.x)"])
    }
    guard abs(scrollView.documentVisibleRect.origin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "resetScrollToTopLeft did not reset y: \(scrollView.documentVisibleRect.origin.y)"])
    }
}

func testUltraWideLineExceeding50kCharactersOpensAtScrollOriginZero() throws {
    let doc = VimMDDocument()
    // 1500 * 36 = 54,000 characters on line 1
    let ultraWideText = "# UltraWide " + String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", count: 1500) + "\nSecond Line"
    guard let data = ultraWideText.data(using: .utf8) else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    try doc.read(from: data, ofType: "net.daringfireball.markdown")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "doc.textView or scrollView is nil"])
    }

    tv.updateFrameForUnwrappedLines()

    guard tv.frame.width > 20000 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected text view frame width > 20000 for 54k char line, got \(tv.frame.width)"])
    }

    let visibleOrigin = scrollView.documentVisibleRect.origin
    let expectedX = expectedScrollOriginX(for: scrollView)
    guard abs(visibleOrigin.x - expectedX) < 0.5 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Ultra-wide file scrolled horizontally to \(visibleOrigin.x), expected \(expectedX)"])
    }
    guard abs(visibleOrigin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Ultra-wide file scrolled vertically to \(visibleOrigin.y)"])
    }

    doc.close()
}

func testMultiMonitorTopLeftPlacement() throws {
    // Secondary monitor to the left (negative minX): e.g. -1920x1080
    let leftMonitor = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
    let leftAnchor = VimMDDocument.initialWindowTopLeftPoint(for: leftMonitor)
    guard leftAnchor.x == -1920 + 24 else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected left monitor x = \(-1920 + 24), got \(leftAnchor.x)"])
    }
    guard leftAnchor.y == 1080 - 24 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected left monitor y = \(1080 - 24), got \(leftAnchor.y)"])
    }

    // Secondary monitor to the right with vertical offset: e.g. 2560x1440 placed at x=1440, y=200
    let rightMonitor = NSRect(x: 1440, y: 200, width: 2560, height: 1440)
    let rightAnchor = VimMDDocument.initialWindowTopLeftPoint(for: rightMonitor)
    guard rightAnchor.x == 1440 + 24 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected right monitor x = \(1440 + 24), got \(rightAnchor.x)"])
    }
    guard rightAnchor.y == (200 + 1440) - 24 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected right monitor y = \((200 + 1440) - 24), got \(rightAnchor.y)"])
    }
}

func testEmptyFileOpensAtScrollOriginZero() throws {
    let doc = VimMDDocument()
    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    try doc.read(from: Data(), ofType: "public.plain-text")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "doc.textView or scrollView nil"])
    }

    tv.updateFrameForUnwrappedLines()

    let visibleOrigin = scrollView.documentVisibleRect.origin
    let expectedX = expectedScrollOriginX(for: scrollView)
    guard abs(visibleOrigin.x - expectedX) < 0.5 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty file x = \(visibleOrigin.x), expected \(expectedX)"])
    }
    guard abs(visibleOrigin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Empty file y = \(visibleOrigin.y)"])
    }

    doc.close()
}

func testRapidReloadsPreserveScrollOrigin() throws {
    let doc = VimMDDocument()
    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    let initial = "# Initial\nContent"
    try doc.read(from: initial.data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    for i in 1...20 {
        let text = "# Reload Iteration \(i) " + String(repeating: "Z", count: 200 * i) + "\nLine \(i)"
        try doc.read(from: text.data(using: .utf8)!, ofType: "net.daringfireball.markdown")

        let visibleOrigin = scrollView.documentVisibleRect.origin
        let expectedX = expectedScrollOriginX(for: scrollView)
        guard abs(visibleOrigin.x - expectedX) < 0.5 else {
            throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Rapid reload \(i) x = \(visibleOrigin.x), expected \(expectedX)"])
        }
        guard abs(visibleOrigin.y) < 0.001 else {
            throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Rapid reload \(i) y = \(visibleOrigin.y)"])
        }
    }

    doc.close()
}

func testLegitimateHorizontalScrollingWhenNavigatingToColumn80() throws {
    let doc = VimMDDocument()
    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    let wideText = "0123456789" + String(repeating: "abcdefghij", count: 30) // 310 chars
    try doc.read(from: wideText.data(using: .utf8)!, ofType: "public.plain-text")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView, let session = doc.session, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    tv.updateFrameForUnwrappedLines()

    // 1. Initial state at col 1 must be expectedX
    let initialOrigin = scrollView.documentVisibleRect.origin
    let expectedX = expectedScrollOriginX(for: scrollView)
    guard abs(initialOrigin.x - expectedX) < 0.5 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial x is \(initialOrigin.x), expected \(expectedX)"])
    }

    // 2. Navigate deep into line 1 (e.g. column 150)
    session.setCursor(line: 1, byteCol: 150)
    tv.synchronizeCaretWithSession()

    // Document visible rect should have legitimately scrolled right to bring caret into view
    let navigatedOrigin = scrollView.documentVisibleRect.origin
    guard navigatedOrigin.x > 50.0 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Expected horizontal scroll x > 50 for column 150, got \(navigatedOrigin.x)"]
        )
    }

    // 3. Navigate back to column 1 ('0' motion equivalent)
    session.setCursor(line: 1, byteCol: 1)
    tv.synchronizeCaretWithSession()

    let resetOrigin = scrollView.documentVisibleRect.origin
    guard abs(resetOrigin.x - expectedX) < 0.5 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Returning to column 1 did not reset origin.x to \(expectedX), got \(resetOrigin.x)"]
        )
    }

    doc.close()
}

func testWindowCascadeResetsWhenReachingScreenBoundaries() throws {
    VimMDDocument.lastTopLeftPoint = nil
    defer { VimMDDocument.lastTopLeftPoint = nil }

    var docs: [VimMDDocument] = []
    defer { docs.forEach { $0.close() } }

    var sawWrapAround = false
    var previousX: CGFloat? = nil

    for i in 1...20 {
        let doc = VimMDDocument()
        doc.makeWindowControllers()
        docs.append(doc)

        guard let win = doc.windowControllers.first?.window else {
            throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
        }

        let screen = win.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Window must stay within reasonable screen bounds (not falling off screen)
        guard win.frame.minX >= visibleFrame.minX - 50 && win.frame.minX <= visibleFrame.maxX else {
            throw NSError(
                domain: "WindowPositioningTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Window \(i) fell off screen horizontally: minX=\(win.frame.minX), visibleFrame=\(visibleFrame)"]
            )
        }

        if let prevX = previousX {
            if win.frame.minX < prevX {
                sawWrapAround = true
            }
        }
        previousX = win.frame.minX
    }

    // Over 20 cascade iterations, cascading must have reached boundary and wrapped around
    guard sawWrapAround else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Window cascade did not wrap around after 20 iterations"]
        )
    }
}

func testWideDocumentLoadedViaVimMDDocumentHasCursorAtTopLeftAndVisibleOriginZeroAsync() throws {
    let doc = VimMDDocument()
    let wideLine = "# Title " + String(repeating: "ABCDEFGHIJKLMNOPQRSTUVWXYZ ", count: 200) + "\nLine 2"
    guard let data = wideLine.data(using: .utf8) else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: nil)
    }

    UserDefaults.standard.set(false, forKey: VimMDDocument.wrapLinesPreferenceKey)
    defer {
        UserDefaults.standard.removeObject(forKey: VimMDDocument.wrapLinesPreferenceKey)
    }

    try doc.read(from: data, ofType: "net.daringfireball.markdown")
    doc.wrapLines = false
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "doc.textView or scrollView is nil"])
    }

    // Verify synchronously
    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Sync caret location expected 0, got \(tv.selectedRange().location)"])
    }
    guard let session = tv.session, session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Sync session cursor expected (1, 1), got \(String(describing: tv.session?.cursorPosition))"])
    }
    let syncOrigin = scrollView.documentVisibleRect.origin
    let expectedX = expectedScrollOriginX(for: scrollView)
    guard abs(syncOrigin.x - expectedX) < 0.5 && abs(syncOrigin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Sync documentVisibleRect expected (\(expectedX),0), got \(syncOrigin)"])
    }

    // Pump main run loop to execute scheduled async blocks (DispatchQueue.main.async)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    // Verify asynchronously
    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Async caret location expected 0, got \(tv.selectedRange().location)"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "WindowPositioningTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Async session cursor expected (1, 1), got \(session.cursorPosition)"])
    }
    let asyncOrigin = scrollView.documentVisibleRect.origin
    guard abs(asyncOrigin.x - expectedX) < 0.5 && abs(asyncOrigin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Async documentVisibleRect expected (\(expectedX),0), got \(asyncOrigin)"])
    }

    doc.close()
}

func testPinViewportToTopLeftGuaranteesVisibleRectOriginZero() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 3000, height: 2000))
    let session = VimSession(initialText: "First line of document\nSecond line\nThird line")
    tv.wrapLines = false
    tv.session = session
    tv.setFrameSize(NSSize(width: 3000, height: 2000))
    scrollView.documentView = tv

    // Artificially move caret and scroll away from top-left
    session.setCursor(line: 2, byteCol: 5)
    tv.synchronizeCaretWithSession()
    tv.setFrameOrigin(NSPoint(x: 100, y: 100))
    scrollView.contentView.scroll(to: NSPoint(x: 550, y: 350))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    guard scrollView.documentVisibleRect.origin.x > 400 && scrollView.documentVisibleRect.origin.y > 200 else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scroll setup failed: origin is \(scrollView.documentVisibleRect.origin)"])
    }

    // Call pinViewportToTopLeft()
    tv.pinViewportToTopLeft()

    guard tv.frame.origin == .zero else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected tv.frame.origin .zero, got \(tv.frame.origin)"])
    }
    guard abs(scrollView.documentVisibleRect.origin.x) < 0.001 && abs(scrollView.documentVisibleRect.origin.y) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected visibleRect (0, 0), got \(scrollView.documentVisibleRect.origin)"])
    }
    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected caret location 0, got \(tv.selectedRange().location)"])
    }
    guard session.cursorPosition.line == 1 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "WindowPositioningTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected session cursor (1, 1), got \(session.cursorPosition)"])
    }

    // Also test VimMDDocument pinViewportToTopLeft delegation
    let doc = VimMDDocument()
    doc.textView = tv
    doc.pinViewportToTopLeft()
    guard tv.frame.origin == .zero else {
        throw NSError(domain: "WindowPositioningTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Doc delegation failed to maintain frame origin zero"])
    }
}

func testNavigatingFromRow2Col0ToRow1Col0WithRulerKeepsFirstCharVisible() throws {
    let doc = VimMDDocument()
    let text = "HeaderA,HeaderB\nValA,ValB\nRow2A,Row2B"
    try doc.read(from: text.data(using: .utf8)!, ofType: "public.comma-separated-values-text")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView, let session = tv.session else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "textView, scrollView, or session nil"])
    }

    // Position at line 2, byteCol 1 (Row 2, col 0)
    session.setCursor(line: 2, byteCol: 1)
    tv.synchronizeCaretWithSession()

    guard session.cursorPosition.line == 2 && session.cursorPosition.byteCol == 1 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Setup cursor failed"])
    }

    // Navigate up to line 1, byteCol 1 (Row 1, col 0)
    session.setCursor(line: 1, byteCol: 1)
    tv.synchronizeCaretWithSession()

    guard tv.selectedRange().location == 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected caret at 0, got \(tv.selectedRange().location)"])
    }

    let rulerThickness = scrollView.verticalRulerView?.ruleThickness ?? 0
    guard rulerThickness > 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "rulerThickness should be > 0"])
    }

    // Clip view origin x must be at -rulerThickness (ruler-aware origin), NOT shifted to 0 which hides text behind the ruler!
    let clipOriginX = scrollView.contentView.bounds.origin.x
    guard abs(clipOriginX - (-rulerThickness)) < 0.5 else {
        throw NSError(
            domain: "WindowPositioningTests",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Clip view origin x (\(clipOriginX)) is not at ruler origin (-\(rulerThickness)); first character is hidden behind the ruler!"]
        )
    }

    doc.close()
}

func testRulerlessAndHiddenRulerScrollViewsHaveZeroOrigin() throws {
    // 1. Rulerless NSScrollView
    let sv1 = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv1 = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1000))
    let session1 = VimSession(initialText: "Rulerless line 1\nRulerless line 2")
    tv1.session = session1
    sv1.documentView = tv1

    tv1.resetScrollToTopLeft()
    guard abs(sv1.documentVisibleRect.origin.x) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Rulerless origin.x is \(sv1.documentVisibleRect.origin.x), expected 0.0"])
    }

    // 2. Hidden ruler: rulersVisible = false
    let sv2 = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let tv2 = VimMDTextView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1000))
    let session2 = VimSession(initialText: "Hidden ruler line 1\nHidden ruler line 2")
    tv2.session = session2
    sv2.documentView = tv2

    let ruler = LineNumberRulerView(scrollView: sv2, orientation: .verticalRuler)
    ruler.clientView = tv2
    sv2.hasVerticalRuler = true
    sv2.verticalRulerView = ruler
    sv2.rulersVisible = false // Ruler hidden!

    tv2.resetScrollToTopLeft()
    guard abs(sv2.documentVisibleRect.origin.x) < 0.001 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Hidden ruler origin.x is \(sv2.documentVisibleRect.origin.x), expected 0.0"])
    }
}

func testDynamicRulerThicknessScalingMaintainsViewportAlignment() throws {
    let doc = VimMDDocument()
    // Start with 5 lines (1 digit)
    let shortText = (1...5).map { "Line \($0)" }.joined(separator: "\n")
    try doc.read(from: shortText.data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    doc.makeWindowControllers()

    guard let tv = doc.textView, let scrollView = tv.enclosingScrollView, let ruler = scrollView.verticalRulerView as? LineNumberRulerView else {
        throw NSError(domain: "WindowPositioningTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "doc views nil"])
    }

    let thickness5 = ruler.ruleThickness
    guard thickness5 > 0 else {
        throw NSError(domain: "WindowPositioningTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Initial thickness <= 0"])
    }
    let expectedX5 = expectedScrollOriginX(for: scrollView)
    guard abs(scrollView.documentVisibleRect.origin.x - expectedX5) < 0.5 else {
        throw NSError(domain: "WindowPositioningTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Initial visible origin \(scrollView.documentVisibleRect.origin.x) != \(expectedX5)"])
    }

    // Now expand to 250 lines (3 digits)
    let longText = (1...250).map { "Line \($0)" }.joined(separator: "\n")
    try doc.read(from: longText.data(using: .utf8)!, ofType: "net.daringfireball.markdown")
    ruler.updateThickness(for: tv)

    let thickness250 = ruler.ruleThickness
    guard thickness250 >= thickness5 else {
        throw NSError(domain: "WindowPositioningTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expanded thickness (\(thickness250)) < initial (\(thickness5))"])
    }

    // Viewport must remain aligned to the scaled ruler thickness
    let expectedX250 = expectedScrollOriginX(for: scrollView)
    guard abs(scrollView.documentVisibleRect.origin.x - expectedX250) < 0.5 else {
        throw NSError(domain: "WindowPositioningTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expanded visible origin \(scrollView.documentVisibleRect.origin.x) != \(expectedX250)"])
    }

    doc.close()
}

print("=== Window Positioning & Viewport Scroll Origin Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testWindowPlacementInTopLeftQuadrant", testWindowPlacementInTopLeftQuadrant),
    ("testWindowCascadingFromTopLeft", testWindowCascadingFromTopLeft),
    ("testWideMarkdownFileOpensAtScrollOriginZero", testWideMarkdownFileOpensAtScrollOriginZero),
    ("testReadWithExistingTextViewResetsScrollOrigin", testReadWithExistingTextViewResetsScrollOrigin),
    ("testSynchronizeCaretAtOriginKeepsScrollOriginZeroOnWideContent", testSynchronizeCaretAtOriginKeepsScrollOriginZeroOnWideContent),
    ("testResetScrollToTopLeftMethod", testResetScrollToTopLeftMethod),
    ("testUltraWideLineExceeding50kCharactersOpensAtScrollOriginZero", testUltraWideLineExceeding50kCharactersOpensAtScrollOriginZero),
    ("testMultiMonitorTopLeftPlacement", testMultiMonitorTopLeftPlacement),
    ("testEmptyFileOpensAtScrollOriginZero", testEmptyFileOpensAtScrollOriginZero),
    ("testRapidReloadsPreserveScrollOrigin", testRapidReloadsPreserveScrollOrigin),
    ("testLegitimateHorizontalScrollingWhenNavigatingToColumn80", testLegitimateHorizontalScrollingWhenNavigatingToColumn80),
    ("testWindowCascadeResetsWhenReachingScreenBoundaries", testWindowCascadeResetsWhenReachingScreenBoundaries),
    ("testWideDocumentLoadedViaVimMDDocumentHasCursorAtTopLeftAndVisibleOriginZeroAsync", testWideDocumentLoadedViaVimMDDocumentHasCursorAtTopLeftAndVisibleOriginZeroAsync),
    ("testPinViewportToTopLeftGuaranteesVisibleRectOriginZero", testPinViewportToTopLeftGuaranteesVisibleRectOriginZero),
    ("testNavigatingFromRow2Col0ToRow1Col0WithRulerKeepsFirstCharVisible", testNavigatingFromRow2Col0ToRow1Col0WithRulerKeepsFirstCharVisible),
    ("testRulerlessAndHiddenRulerScrollViewsHaveZeroOrigin", testRulerlessAndHiddenRulerScrollViewsHaveZeroOrigin),
    ("testDynamicRulerThicknessScalingMaintainsViewportAlignment", testDynamicRulerThicknessScalingMaintainsViewportAlignment)
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
