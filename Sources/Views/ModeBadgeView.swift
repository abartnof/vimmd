import AppKit
import Engine
import CBridge

/// A custom filled rounded pill badge view displaying the current Vim editing mode.
open class ModeBadgeView: NSTextField {
    public var mode: VimEngineMode = VIM_MODE_NORMAL {
        didSet {
            updateBadge()
        }
    }

    public var badgeColor: NSColor = VimModeTheme.normalColor {
        didSet {
            self.needsDisplay = true
        }
    }

    public var cornerRadius: CGFloat = 4.5 {
        didSet {
            self.needsDisplay = true
        }
    }

    public var horizontalPadding: CGFloat = 8.0 {
        didSet {
            updateBadge()
        }
    }

    public var textOriginXInSuperview: CGFloat {
        let sampleFont = self.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let textSize = (self.stringValue as NSString).size(withAttributes: [.font: sampleFont])
        let internalTextX = (self.bounds.width - textSize.width) / 2.0
        return self.frame.origin.x + internalTextX
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        self.isEditable = false
        self.isSelectable = false
        self.isBordered = false
        self.drawsBackground = false
        self.alignment = .center
        self.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        self.textColor = NSColor.white
        updateBadge()
    }

    public func updateBadge() {
        self.badgeColor = VimModeTheme.color(for: mode)
        self.stringValue = VimModeTheme.modeBadgeText(for: mode)
        self.textColor = NSColor.white
        updateFrameWidth()
        self.needsDisplay = true
    }

    public func updateFrameWidth() {
        guard !self.stringValue.isEmpty else { return }
        let sampleFont = self.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let textSize = (self.stringValue as NSString).size(withAttributes: [.font: sampleFont])
        let targetWidth = max(56.0, ceil(textSize.width + horizontalPadding * 2.0))
        let targetHeight = self.frame.height > 0 ? self.frame.height : 16.0
        if abs(self.frame.width - targetWidth) > 0.5 {
            self.setFrameSize(NSSize(width: targetWidth, height: targetHeight))
        }
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard !self.stringValue.isEmpty else { return }

        // 1. Draw rounded pill background
        let radius = cornerRadius > 0 ? cornerRadius : (bounds.height / 2.0)
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        badgeColor.setFill()
        pillPath.fill()

        // 2. Draw centered bold crisp white mode label
        let textFont = self.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: style
        ]
        let numStr = self.stringValue as NSString
        let textSize = numStr.size(withAttributes: attrs)
        let textY = bounds.origin.y + (bounds.height - textSize.height) / 2.0
        let textRect = NSRect(x: bounds.origin.x, y: textY, width: bounds.width, height: textSize.height)
        numStr.draw(in: textRect, withAttributes: attrs)
    }
}
