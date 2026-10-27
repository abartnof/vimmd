import AppKit

// TextKit 2 (macOS 12.0+) compatibility declarations for environments
// building against macOS 11.3 CommandLineTools SDK.
#if !canImport(TextKit2Compatibility)
@objc open class NSTextElement: NSObject {}
@objc open class NSTextRange: NSObject {}

@objc open class NSTextLayoutFragment: NSObject {
    public let textElement: NSTextElement
    public let range: NSTextRange?

    public init(textElement: NSTextElement, range: NSTextRange?) {
        self.textElement = textElement
        self.range = range
        super.init()
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif

/// Layout fragment override for in-place Markdown concealment per Section 3.3 of DESIGN.md.
open class MarkdownTextLayoutFragment: NSTextLayoutFragment {
    public override init(textElement: NSTextElement, range: NSTextRange?) {
        super.init(textElement: textElement, range: range)
    }
}
