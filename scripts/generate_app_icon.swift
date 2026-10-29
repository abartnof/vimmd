import Foundation
import AppKit

guard let outputPath = CommandLine.arguments.last, outputPath.hasSuffix(".icns") else {
    print("Usage: generate_app_icon.swift <output.icns>")
    exit(1)
}
let outputURL = URL(fileURLWithPath: outputPath)

// Ensure parent directory exists
let parentDir = outputURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)

let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VimMDAppIcon_\(ProcessInfo.processInfo.globallyUniqueString).iconset")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

defer {
    try? FileManager.default.removeItem(at: tempDir)
}

guard let symbol = NSImage(systemSymbolName: "v.circle", accessibilityDescription: "VimMD") else {
    print("Error: Could not load SF Symbol 'v.circle'")
    exit(1)
}

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in iconSizes {
    let px = item.px
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Error: Could not allocate bitmap for size \(px)")
        exit(1)
    }

    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let fpx = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: fpx, height: fpx)
    let circleRect = rect.insetBy(dx: fpx * 0.07, dy: fpx * 0.07)
    let circlePath = NSBezierPath(ovalIn: circleRect)

    // 1. Fill circular body with solid pure white
    NSColor.white.setFill()
    circlePath.fill()

    // 2. Stroke subtle border
    NSColor(white: 0.85, alpha: 1.0).setStroke()
    circlePath.lineWidth = max(1.0, fpx * 0.015)
    circlePath.stroke()

    // 3. Draw v.circle symbol crisply in dark/black over the white-filled circle
    symbol.draw(in: rect)

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Error: Could not generate PNG data for \(item.name)")
        exit(1)
    }

    let filePath = tempDir.appendingPathComponent(item.name)
    try pngData.write(to: filePath)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", outputURL.path, tempDir.path]

try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    print("Error: iconutil exited with status \(process.terminationStatus)")
    exit(Int32(process.terminationStatus))
}

print("AppIcon.icns generated successfully at \(outputPath)")
