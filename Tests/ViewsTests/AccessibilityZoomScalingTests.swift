import Foundation
import AppKit
import Views
import App
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

// 1. LineNumberRulerView Scaling Tests
func testLineNumberRulerViewScaling() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    let session = VimSession(initialText: "line 1\nline 2\nline 3\n")
    textView.session = session
    scrollView.documentView = textView

    let ruler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    ruler.clientView = textView
    scrollView.hasVerticalRuler = true
    scrollView.verticalRulerView = ruler

    // Check default scale 1.0
    guard abs(ruler.uiScale - 1.0) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Default uiScale should be 1.0, got \(ruler.uiScale)"])
    }
    ruler.updateThickness(for: textView)
    let baseThickness = ruler.ruleThickness
    guard baseThickness >= 30.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected base thickness >= 30.0, got \(baseThickness)"])
    }
    guard ruler.activeFont.pointSize == 11.0 && ruler.inactiveFont.pointSize == 11.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected font size 11.0 at 1.0x scale"])
    }
    guard ruler.badgeHeight == 16.0 && ruler.horizontalPadding == 6.0 && ruler.textRightMargin == 8.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected badge geometry at 1.0x scale"])
    }

    // Scale to 1.5x
    ruler.uiScale = 1.5
    guard abs(ruler.uiScale - 1.5) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "uiScale should be 1.5, got \(ruler.uiScale)"])
    }
    guard abs(ruler.activeFont.pointSize - 16.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected font size 16.5 at 1.5x scale, got \(ruler.activeFont.pointSize)"])
    }
    guard abs(ruler.badgeHeight - 24.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected badgeHeight 24.0 at 1.5x scale, got \(ruler.badgeHeight)"])
    }
    guard abs(ruler.horizontalPadding - 9.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected horizontalPadding 9.0 at 1.5x scale, got \(ruler.horizontalPadding)"])
    }
    guard abs(ruler.textRightMargin - 12.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected textRightMargin 12.0 at 1.5x scale, got \(ruler.textRightMargin)"])
    }
    guard ruler.ruleThickness > baseThickness * 1.3 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "ruleThickness should scale up at 1.5x, got \(ruler.ruleThickness) vs base \(baseThickness)"])
    }

    // Centering in rowHeight 27.0 (18.0 * 1.5)
    let badgeRect = ruler.activeRowBadgeRect(for: 1, y: 0.0, rowHeight: 27.0)
    let expectedY: CGFloat = (27.0 - 24.0) / 2.0
    guard abs(Double(badgeRect.origin.y - expectedY)) < 0.1 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Expected centered badge y ~ \(expectedY), got \(badgeRect.origin.y)"])
    }

    // Scale to 2.0x
    ruler.uiScale = 2.0
    guard abs(ruler.activeFont.pointSize - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Expected font size 22.0 at 2.0x scale, got \(ruler.activeFont.pointSize)"])
    }
    guard abs(ruler.badgeHeight - 32.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 13, userInfo: [NSLocalizedDescriptionKey: "Expected badgeHeight 32.0 at 2.0x scale, got \(ruler.badgeHeight)"])
    }

    // Scale to 0.8x
    ruler.uiScale = 0.8
    guard abs(ruler.activeFont.pointSize - 8.8) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected font size 8.8 at 0.8x scale, got \(ruler.activeFont.pointSize)"])
    }
    guard abs(ruler.badgeHeight - 12.8) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 15, userInfo: [NSLocalizedDescriptionKey: "Expected badgeHeight 12.8 at 0.8x scale, got \(ruler.badgeHeight)"])
    }
}

// 2. ColumnLetterRulerView Scaling Tests
func testColumnLetterRulerViewScaling() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let ruler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)

    // Check default scale 1.0
    guard abs(ruler.uiScale - 1.0) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 20, userInfo: [NSLocalizedDescriptionKey: "Default uiScale should be 1.0, got \(ruler.uiScale)"])
    }
    guard abs(ruler.ruleThickness - 20.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 21, userInfo: [NSLocalizedDescriptionKey: "Expected ruleThickness 20.0 at 1.0x scale, got \(ruler.ruleThickness)"])
    }
    guard abs(ruler.font.pointSize - 11.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 22, userInfo: [NSLocalizedDescriptionKey: "Expected font size 11.0 at 1.0x scale, got \(ruler.font.pointSize)"])
    }

    // Scale to 1.5x
    ruler.uiScale = 1.5
    guard abs(ruler.ruleThickness - 30.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 23, userInfo: [NSLocalizedDescriptionKey: "Expected ruleThickness 30.0 at 1.5x scale, got \(ruler.ruleThickness)"])
    }
    guard abs(ruler.font.pointSize - 16.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 24, userInfo: [NSLocalizedDescriptionKey: "Expected font size 16.5 at 1.5x scale, got \(ruler.font.pointSize)"])
    }

    // Scale to 2.0x
    ruler.uiScale = 2.0
    guard abs(ruler.ruleThickness - 40.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 25, userInfo: [NSLocalizedDescriptionKey: "Expected ruleThickness 40.0 at 2.0x scale, got \(ruler.ruleThickness)"])
    }
    guard abs(ruler.font.pointSize - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 26, userInfo: [NSLocalizedDescriptionKey: "Expected font size 22.0 at 2.0x scale, got \(ruler.font.pointSize)"])
    }

    // Scale to 0.8x
    ruler.uiScale = 0.8
    guard abs(ruler.ruleThickness - 16.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 27, userInfo: [NSLocalizedDescriptionKey: "Expected ruleThickness 16.0 at 0.8x scale, got \(ruler.ruleThickness)"])
    }
    guard abs(ruler.font.pointSize - 8.8) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 28, userInfo: [NSLocalizedDescriptionKey: "Expected font size 8.8 at 0.8x scale, got \(ruler.font.pointSize)"])
    }
}

// 3. ModeBadgeView Scaling Tests
func testModeBadgeViewScaling() throws {
    let badge = ModeBadgeView(frame: NSRect(x: 0, y: 0, width: 68, height: 16))
    badge.mode = VIM_MODE_NORMAL
    badge.updateBadge()

    guard badge.frame.height == 16.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 30, userInfo: [NSLocalizedDescriptionKey: "Initial badge height should be 16.0, got \(badge.frame.height)"])
    }
    guard badge.font?.pointSize == 11.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 31, userInfo: [NSLocalizedDescriptionKey: "Initial font size should be 11.0, got \(String(describing: badge.font?.pointSize))"])
    }

    // Scale to 1.5x
    badge.applyScale(1.5)
    guard abs(badge.frame.height - 24.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 32, userInfo: [NSLocalizedDescriptionKey: "Expected badge height 24.0 at 1.5x, got \(badge.frame.height)"])
    }
    guard abs((badge.font?.pointSize ?? 0) - 16.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 33, userInfo: [NSLocalizedDescriptionKey: "Expected font size 16.5 at 1.5x, got \(String(describing: badge.font?.pointSize))"])
    }
    guard abs(badge.cornerRadius - 6.75) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 34, userInfo: [NSLocalizedDescriptionKey: "Expected corner radius 6.75 at 1.5x, got \(badge.cornerRadius)"])
    }

    // Scale to 2.0x
    badge.applyScale(2.0)
    guard abs(badge.frame.height - 32.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 35, userInfo: [NSLocalizedDescriptionKey: "Expected badge height 32.0 at 2.0x, got \(badge.frame.height)"])
    }
    guard abs((badge.font?.pointSize ?? 0) - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 36, userInfo: [NSLocalizedDescriptionKey: "Expected font size 22.0 at 2.0x, got \(String(describing: badge.font?.pointSize))"])
    }
    guard abs(badge.cornerRadius - 9.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 37, userInfo: [NSLocalizedDescriptionKey: "Expected corner radius 9.0 at 2.0x, got \(badge.cornerRadius)"])
    }

    // Scale to 0.8x
    badge.applyScale(0.8)
    guard abs(badge.frame.height - 13.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 38, userInfo: [NSLocalizedDescriptionKey: "Expected badge height 13.0 at 0.8x, got \(badge.frame.height)"])
    }
    guard abs((badge.font?.pointSize ?? 0) - 8.8) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 39, userInfo: [NSLocalizedDescriptionKey: "Expected font size 8.8 at 0.8x, got \(String(describing: badge.font?.pointSize))"])
    }
}

// 4. VimMDDocument Full UI Scaling Tests
func testVimMDDocumentFullUIScaling() throws {
    let doc = try VimMDDocument(type: "net.daringfireball.markdown")
    doc.makeWindowControllers()

    guard let statusBar = doc.statusBar else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 40, userInfo: [NSLocalizedDescriptionKey: "Document statusBar should be accessible"])
    }
    guard let scrollView = doc.scrollView else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 41, userInfo: [NSLocalizedDescriptionKey: "Document scrollView should be accessible"])
    }

    // Initial 1.0x layout check
    guard abs(statusBar.frame.height - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 42, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height 22.0, got \(statusBar.frame.height)"])
    }
    guard abs(scrollView.frame.origin.y - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 43, userInfo: [NSLocalizedDescriptionKey: "Expected scrollView y origin 22.0, got \(scrollView.frame.origin.y)"])
    }
    guard doc.posLabel?.font?.pointSize == 11.0 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 44, userInfo: [NSLocalizedDescriptionKey: "Expected posLabel font size 11.0 at 1.0x"])
    }

    // Apply 1.5x scale
    doc.applyMagnificationScale(1.5)
    let expectedStatus15: CGFloat = ceil(22.0 * 1.5)
    guard abs(statusBar.frame.height - expectedStatus15) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 45, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus15) at 1.5x, got \(statusBar.frame.height)"])
    }
    guard abs(scrollView.frame.origin.y - expectedStatus15) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 46, userInfo: [NSLocalizedDescriptionKey: "Expected scrollView y origin \(expectedStatus15) at 1.5x, got \(scrollView.frame.origin.y)"])
    }
    guard abs((doc.posLabel?.font?.pointSize ?? 0) - 16.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 47, userInfo: [NSLocalizedDescriptionKey: "Expected posLabel font size 16.5 at 1.5x, got \(String(describing: doc.posLabel?.font?.pointSize))"])
    }
    guard abs((doc.messageLabel?.font?.pointSize ?? 0) - 16.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 48, userInfo: [NSLocalizedDescriptionKey: "Expected messageLabel font size 16.5 at 1.5x, got \(String(describing: doc.messageLabel?.font?.pointSize))"])
    }
    guard abs((doc.modeBadgeView?.frame.height ?? 0) - 24.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 49, userInfo: [NSLocalizedDescriptionKey: "Expected modeBadgeView height 24.0 at 1.5x, got \(String(describing: doc.modeBadgeView?.frame.height))"])
    }
    guard abs((doc.savedChipView?.frame.height ?? 0) - CGFloat(ceil(18.0 * 1.5))) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 50, userInfo: [NSLocalizedDescriptionKey: "Expected savedChipView height 27.0 at 1.5x, got \(String(describing: doc.savedChipView?.frame.height))"])
    }
    let ruler = scrollView.verticalRulerView as? LineNumberRulerView
    guard abs((ruler?.uiScale ?? 0) - 1.5) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 51, userInfo: [NSLocalizedDescriptionKey: "Expected LineNumberRulerView uiScale 1.5, got \(String(describing: ruler?.uiScale))"])
    }

    // Apply 2.0x scale
    doc.applyMagnificationScale(2.0)
    let expectedStatus20: CGFloat = ceil(22.0 * 2.0)
    guard abs(statusBar.frame.height - expectedStatus20) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 52, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus20) at 2.0x, got \(statusBar.frame.height)"])
    }
    guard abs((doc.posLabel?.font?.pointSize ?? 0) - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 53, userInfo: [NSLocalizedDescriptionKey: "Expected posLabel font size 22.0 at 2.0x, got \(String(describing: doc.posLabel?.font?.pointSize))"])
    }

    // Apply 0.8x scale
    doc.applyMagnificationScale(0.8)
    let expectedStatus08: CGFloat = ceil(22.0 * 0.8)
    guard abs(statusBar.frame.height - expectedStatus08) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 54, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus08) at 0.8x, got \(statusBar.frame.height)"])
    }
    guard abs((doc.posLabel?.font?.pointSize ?? 0) - 8.8) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 55, userInfo: [NSLocalizedDescriptionKey: "Expected posLabel font size 8.8 at 0.8x, got \(String(describing: doc.posLabel?.font?.pointSize))"])
    }
}

// 5. Zoom In/Out Actions & Notification Propagation Tests
func testZoomActionsAndNotificationPropagation() throws {
    let doc = try VimMDDocument(type: "net.daringfireball.markdown")
    doc.makeWindowControllers()

    guard let scrollView = doc.scrollView else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 60, userInfo: [NSLocalizedDescriptionKey: "Missing scrollView"])
    }
    guard let statusBar = doc.statusBar else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 61, userInfo: [NSLocalizedDescriptionKey: "Missing statusBar"])
    }

    // Test zoomIn action on doc
    doc.zoomIn(nil)
    guard abs(scrollView.magnification - 1.1) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 62, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.1 after zoomIn, got \(scrollView.magnification)"])
    }
    let expectedStatus11: CGFloat = ceil(22.0 * 1.1)
    guard abs(statusBar.frame.height - expectedStatus11) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 63, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus11) after zoomIn, got \(statusBar.frame.height)"])
    }

    // Test zoomOut action on doc
    doc.zoomOut(nil)
    guard abs(scrollView.magnification - 1.0) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 64, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.0 after zoomOut, got \(scrollView.magnification)"])
    }
    guard abs(statusBar.frame.height - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 65, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height 22.0 after zoomOut, got \(statusBar.frame.height)"])
    }

    // Test zoomIn from textView
    doc.textView?.zoomIn(nil)
    guard abs(scrollView.magnification - 1.1) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 66, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.1 after textView.zoomIn, got \(scrollView.magnification)"])
    }
    guard abs(statusBar.frame.height - expectedStatus11) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 67, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus11) after textView.zoomIn, got \(statusBar.frame.height)"])
    }

    // Test actualSize from textView
    doc.textView?.actualSize(nil)
    guard abs(scrollView.magnification - 1.0) < 0.001 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 68, userInfo: [NSLocalizedDescriptionKey: "Expected magnification 1.0 after textView.actualSize, got \(scrollView.magnification)"])
    }
    guard abs(statusBar.frame.height - 22.0) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 69, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height 22.0 after textView.actualSize, got \(statusBar.frame.height)"])
    }

    // Test didEndLiveMagnifyNotification propagation (e.g. pinch to zoom)
    scrollView.magnification = 1.4
    NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    let expectedStatus14: CGFloat = ceil(22.0 * 1.4)
    guard abs(statusBar.frame.height - expectedStatus14) < 0.01 else {
        throw NSError(domain: "AccessibilityZoomScalingTests", code: 70, userInfo: [NSLocalizedDescriptionKey: "Expected status bar height \(expectedStatus14) after live magnify notification, got \(statusBar.frame.height)"])
    }
}

let tests = [
    ("testLineNumberRulerViewScaling", testLineNumberRulerViewScaling),
    ("testColumnLetterRulerViewScaling", testColumnLetterRulerViewScaling),
    ("testModeBadgeViewScaling", testModeBadgeViewScaling),
    ("testVimMDDocumentFullUIScaling", testVimMDDocumentFullUIScaling),
    ("testZoomActionsAndNotificationPropagation", testZoomActionsAndNotificationPropagation),
]

var passedCount = 0
for (name, test) in tests {
    if runTest(name: name, test: test) {
        passedCount += 1
    } else {
        exit(1)
    }
}
print("Result: \(passedCount)/\(tests.count) tests passed.")
