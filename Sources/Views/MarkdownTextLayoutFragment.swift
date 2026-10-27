import AppKit

// TextKit 2 compatibility types
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
    public var isCurrentEditingLine: Bool = false
    public var rawLineString: String = ""
    public let syntaxResolver: MarkdownSyntaxResolver = MarkdownSyntaxResolver()

    public override init(textElement: NSTextElement, range: NSTextRange?) {
        super.init(textElement: textElement, range: range)
    }

    /// Computes vertical height delta ΔH for viewport counter-scroll compensation per DESIGN.md §3.3.
    public static func computeScrollCompensation(beforeHeight: CGFloat, afterHeight: CGFloat) -> CGFloat {
        return afterHeight - beforeHeight
    }
}
