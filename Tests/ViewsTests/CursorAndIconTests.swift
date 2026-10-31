import Foundation
import AppKit
import Engine
import Views
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

func extractPixelColors(from image: NSImage) -> (hasWhite: Bool, hasBlack: Bool) {
    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData) else {
        return (false, false)
    }

    var hasWhite = false
    var hasBlack = false

    let width = rep.pixelsWide
    let height = rep.pixelsHigh

    for y in 0..<height {
        for x in 0..<width {
            guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else {
                continue
            }
            if color.redComponent > 0.85 && color.greenComponent > 0.85 && color.blueComponent > 0.85 {
                hasWhite = true
            }
            if color.redComponent < 0.15 && color.greenComponent < 0.15 && color.blueComponent < 0.15 {
                hasBlack = true
            }
        }
    }

    return (hasWhite, hasBlack)
}

func testDownwardArrowCursorHighContrast() throws {
    let cursor = VimMDTextView.downwardArrowCursor
    let image = cursor.image
    guard image.size.width > 0 && image.size.height > 0 else {
        throw NSError(domain: "CursorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "downwardArrowCursor image must have non-zero size"])
    }

    // Exact hotspot assertion: bottom tip for downward arrow
    guard cursor.hotSpot == NSPoint(x: 10, y: 18) else {
        throw NSError(domain: "CursorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "downwardArrowCursor hotspot must be exact point (10, 18), got \(cursor.hotSpot)"])
    }

    let colors = extractPixelColors(from: image)
    guard colors.hasWhite else {
        throw NSError(domain: "CursorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "downwardArrowCursor must have white fill for high-contrast visibility"])
    }
    guard colors.hasBlack else {
        throw NSError(domain: "CursorTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "downwardArrowCursor must have black outline for high-contrast visibility"])
    }
}

func testRightwardArrowCursorHighContrast() throws {
    let cursor = VimMDTextView.rightwardArrowCursor
    let image = cursor.image
    guard image.size.width > 0 && image.size.height > 0 else {
        throw NSError(domain: "CursorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "rightwardArrowCursor image must have non-zero size"])
    }

    // Exact hotspot assertion: right tip for rightward arrow
    guard cursor.hotSpot == NSPoint(x: 18, y: 10) else {
        throw NSError(domain: "CursorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "rightwardArrowCursor hotspot must be exact point (18, 10), got \(cursor.hotSpot)"])
    }

    let colors = extractPixelColors(from: image)
    guard colors.hasWhite else {
        throw NSError(domain: "CursorTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "rightwardArrowCursor must have white fill for high-contrast visibility"])
    }
    guard colors.hasBlack else {
        throw NSError(domain: "CursorTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "rightwardArrowCursor must have black outline for high-contrast visibility"])
    }
}

func testCursorSelectionInSpreadsheet() throws {
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    let textView = VimMDTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
    textView.string = "Col1,Col2,Col3\nVal1,Val2,Val3\nVal4,Val5,Val6"
    textView.documentSyntaxType = .csv
    textView.isTabularDocument = true
    scrollView.documentView = textView
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)

    let colRuler = ColumnLetterRulerView(scrollView: scrollView, orientation: .horizontalRuler)
    colRuler.clientView = textView
    scrollView.horizontalRulerView = colRuler

    let lineRuler = LineNumberRulerView(scrollView: scrollView, orientation: .verticalRuler)
    lineRuler.clientView = textView
    scrollView.verticalRulerView = lineRuler

    // State 1: ColumnLetterRulerView yields downwardArrowCursor
    let headerCursor = colRuler.cursorForPoint(NSPoint(x: 50, y: 10))
    guard headerCursor == VimMDTextView.downwardArrowCursor else {
        throw NSError(domain: "CursorTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Hovering column letter ruler must yield downwardArrowCursor, got \(String(describing: headerCursor))"])
    }

    // State 2: LineNumberRulerView yields rightwardArrowCursor
    let lineCursor = lineRuler.cursorForPoint(NSPoint(x: 10, y: 50))
    guard lineCursor == VimMDTextView.rightwardArrowCursor else {
        throw NSError(domain: "CursorTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Hovering line number ruler must yield rightwardArrowCursor, got \(String(describing: lineCursor))"])
    }

    // State 3: Header and Body cells in text view yield nil (default I-beam / arrow)
    guard let r0 = textView.rowRect(for: 0),
          let r1 = textView.rowRect(for: 1) else {
        throw NSError(domain: "CursorTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve row rects for test"])
    }
    let widths = textView.columnWidths()
    guard !widths.isEmpty else {
        throw NSError(domain: "CursorTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve column widths"])
    }

    let ptHeader = NSPoint(x: 10, y: r0.midY)
    let ptColA = NSPoint(x: 10, y: r1.midY)
    let ptBody = NSPoint(x: 10 + widths[0] + 10, y: r1.midY)

    guard textView.cursorForPoint(ptHeader) == nil else {
        throw NSError(domain: "CursorTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Hovering header cell in text view must yield nil"])
    }
    guard textView.cursorForPoint(ptColA) == nil else {
        throw NSError(domain: "CursorTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Hovering Col A cell in text view must yield nil"])
    }
    guard textView.cursorForPoint(ptBody) == nil else {
        throw NSError(domain: "CursorTests", code: 11, userInfo: [NSLocalizedDescriptionKey: "Hovering body cell must yield nil"])
    }

    // State 4: Non-tabular document yields nil everywhere
    textView.documentSyntaxType = .plainText
    textView.isTabularDocument = false
    let nonTabularColRulerCursor = colRuler.cursorForPoint(NSPoint(x: 50, y: 10))
    let nonTabularLineRulerCursor = lineRuler.cursorForPoint(NSPoint(x: 10, y: 50))
    guard nonTabularColRulerCursor == nil && nonTabularLineRulerCursor == nil else {
        throw NSError(domain: "CursorTests", code: 12, userInfo: [NSLocalizedDescriptionKey: "Non-tabular document rulers must yield nil cursor"])
    }
}

func testAppIconConfiguration() throws {
    guard let icon = AppDelegate.configureApplicationIcon() else {
        throw NSError(domain: "AppIconTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "AppDelegate.configureApplicationIcon() must return valid NSImage"])
    }

    guard NSApplication.shared.applicationIconImage != nil else {
        throw NSError(domain: "AppIconTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "NSApplication.shared.applicationIconImage should be set"])
    }

    // Verify it is non-empty
    guard icon.size.width > 0 && icon.size.height > 0 else {
        throw NSError(domain: "AppIconTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Application icon must have positive dimensions"])
    }

    // Verify white fill and dark glyph pixels in white-filled icon representation
    let colors = extractPixelColors(from: icon)
    guard colors.hasWhite else {
        throw NSError(domain: "AppIconTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Application icon must have pure white filled circle body"])
    }
    guard colors.hasBlack else {
        throw NSError(domain: "AppIconTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Application icon must have dark glyph/border outline"])
    }
}

func testAppBundleIconAndPlist() throws {
    let bundlePath = "build/VimMD.app"
    let iconPath = "\(bundlePath)/Contents/Resources/AppIcon.icns"
    let plistPath = "\(bundlePath)/Contents/Info.plist"

    // Unconditional assertion: bundle and resources MUST exist
    guard FileManager.default.fileExists(atPath: bundlePath) else {
        throw NSError(domain: "AppIconTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "build/VimMD.app not found"])
    }
    guard FileManager.default.fileExists(atPath: iconPath) else {
        throw NSError(domain: "AppIconTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "AppIcon.icns not found in app bundle at \(iconPath)"])
    }
    guard FileManager.default.fileExists(atPath: plistPath) else {
        throw NSError(domain: "AppIconTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Info.plist not found in app bundle at \(plistPath)"])
    }

    let attrs = try FileManager.default.attributesOfItem(atPath: iconPath)
    let size = attrs[.size] as? Int64 ?? 0
    guard size > 1000 && size < 2_500_000 else {
        throw NSError(domain: "AppIconTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "AppIcon.icns size out of expected bounds: \(size) bytes"])
    }

    let plistContent = try String(contentsOfFile: plistPath, encoding: .utf8)
    guard plistContent.contains("<key>CFBundleIconFile</key>") && plistContent.contains("<string>AppIcon</string>") else {
        throw NSError(domain: "AppIconTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "CFBundleIconFile missing from Info.plist"])
    }
}

// Main execution
var passed = true
passed = runTest(name: "testDownwardArrowCursorHighContrast", test: testDownwardArrowCursorHighContrast) && passed
passed = runTest(name: "testRightwardArrowCursorHighContrast", test: testRightwardArrowCursorHighContrast) && passed
passed = runTest(name: "testCursorSelectionInSpreadsheet", test: testCursorSelectionInSpreadsheet) && passed
passed = runTest(name: "testAppIconConfiguration", test: testAppIconConfiguration) && passed
passed = runTest(name: "testAppBundleIconAndPlist", test: testAppBundleIconAndPlist) && passed

if !passed {
    exit(1)
}
print("All CursorAndIconTests passed successfully!")
