import Foundation
import AppKit

public enum MarkdownDelimiterType: Equatable {
    case header(level: Int)
    case bold
    case italic
    case inlineCode
    case strikethrough
    case link
}

public struct MarkdownDelimiter: Equatable {
    public let range: NSRange
    public let type: MarkdownDelimiterType

    public init(range: NSRange, type: MarkdownDelimiterType) {
        self.range = range
        self.type = type
    }
}

public struct MarkdownSyntaxResolver {
    // Precompiled cached NSRegularExpression patterns conforming to CommonMark delimiter rules
    public static let headerRegex = try! NSRegularExpression(pattern: "^(#{1,6}\\s+)")
    public static let boldRegex = try! NSRegularExpression(pattern: "(?<!\\*|_)(\\*\\*|__)(?!\\s)((?:(?!\\1)[^\\n])+?)(?<!\\s)\\1(?!\\*|_)")
    public static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*|_)(\\*|_)(?!\\s|\\*|_)((?:(?!\\1)[^\\n])+?)(?<!\\s|\\*|_)\\1(?!\\*|_)")
    public static let codeRegex = try! NSRegularExpression(pattern: "`([^`]+)`")
    public static let strikeRegex = try! NSRegularExpression(pattern: "~~([^~]+)~~")
    public static let linkRegex = try! NSRegularExpression(pattern: "\\[(.*?)\\]\\((.*?)\\)")

    public init() {}

    public func extractDelimiters(from line: String) -> [MarkdownDelimiter] {
        guard !line.isEmpty else { return [] }
        var delimiters: [MarkdownDelimiter] = []
        let nsLine = line as NSString
        let fullLength = nsLine.length

        // 1. Headers: ^(#{1,6}\s+)
        if let match = Self.headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: fullLength)) {
            let matchRange = match.range(at: 1)
            let hashesCount = line.prefix(while: { $0 == "#" }).count
            delimiters.append(MarkdownDelimiter(range: matchRange, type: .header(level: hashesCount)))
        }

        // 2. Bold: \*\*([^\*]+)\*\* or __([^__]+)__
        for m in Self.boldRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            delimiters.append(MarkdownDelimiter(range: m.range, type: .bold))
        }

        // 3. Italic: *([^\*]+)* or _([^_]+)_
        for m in Self.italicRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            delimiters.append(MarkdownDelimiter(range: m.range, type: .italic))
        }

        // 4. Inline code: `([^`]+)`
        for m in Self.codeRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            delimiters.append(MarkdownDelimiter(range: m.range, type: .inlineCode))
        }

        // 5. Strikethrough: ~~([^~]+)~~
        for m in Self.strikeRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            delimiters.append(MarkdownDelimiter(range: m.range, type: .strikethrough))
        }

        // 6. Links: \[(.*?)\]\((.*?)\)
        for m in Self.linkRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            delimiters.append(MarkdownDelimiter(range: m.range, type: .link))
        }

        return delimiters
    }

    public func concealedRanges(in line: String) -> [NSRange] {
        guard !line.isEmpty else { return [] }
        var ranges: [NSRange] = []
        let nsLine = line as NSString
        let fullLength = nsLine.length

        // Headers
        if let match = Self.headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: fullLength)) {
            ranges.append(match.range(at: 1))
        }

        // Bold: opening and closing delimiters (2 chars each)
        for m in Self.boldRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            if m.range.length >= 4 {
                let openRange = NSRange(location: m.range.location, length: 2)
                let closeRange = NSRange(location: m.range.location + m.range.length - 2, length: 2)
                ranges.append(openRange)
                ranges.append(closeRange)
            }
        }

        // Italic: opening and closing delimiters (1 char each)
        for m in Self.italicRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            if m.range.length >= 2 {
                let openRange = NSRange(location: m.range.location, length: 1)
                let closeRange = NSRange(location: m.range.location + m.range.length - 1, length: 1)
                ranges.append(openRange)
                ranges.append(closeRange)
            }
        }

        // Inline Code: opening and closing backtick (1 char each)
        for m in Self.codeRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            if m.range.length >= 2 {
                let openRange = NSRange(location: m.range.location, length: 1)
                let closeRange = NSRange(location: m.range.location + m.range.length - 1, length: 1)
                ranges.append(openRange)
                ranges.append(closeRange)
            }
        }

        // Strikethrough: opening and closing ~~ (2 chars each)
        for m in Self.strikeRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            if m.range.length >= 4 {
                let openRange = NSRange(location: m.range.location, length: 2)
                let closeRange = NSRange(location: m.range.location + m.range.length - 2, length: 2)
                ranges.append(openRange)
                ranges.append(closeRange)
            }
        }

        // Links: conceal '[' and '](url)'
        for m in Self.linkRegex.matches(in: line, range: NSRange(location: 0, length: fullLength)) {
            let openBracketRange = NSRange(location: m.range.location, length: 1)
            let textLength = m.range(at: 1).length
            let closeAndUrlRange = NSRange(
                location: m.range.location + 1 + textLength,
                length: m.range.length - (1 + textLength)
            )
            ranges.append(openBracketRange)
            ranges.append(closeAndUrlRange)
        }

        return ranges.sorted { $0.location < $1.location }
    }

    public func styledAttributedString(from line: String, isCurrentEditingLine: Bool) -> NSAttributedString {
        guard !line.isEmpty else {
            return NSAttributedString(string: "")
        }

        if isCurrentEditingLine {
            let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            return NSAttributedString(string: line, attributes: [.font: monoFont])
        }

        // Concealed Mode: strip delimiter characters from display string and apply typography
        let nsLine = line as NSString
        var displayText = line

        // Check for Header
        if let match = Self.headerRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
            let headerPrefix = nsLine.substring(with: match.range(at: 1))
            let content = nsLine.substring(from: match.range(at: 1).length)
            displayText = content
            let level = headerPrefix.filter { $0 == "#" }.count
            let size: CGFloat = max(14, 24 - CGFloat(level * 2))
            let headerFont = NSFont.boldSystemFont(ofSize: size)
            return NSAttributedString(string: displayText, attributes: [.font: headerFont])
        }

        let baseFont = NSFont.systemFont(ofSize: 14)
        return NSAttributedString(string: displayText, attributes: [.font: baseFont])
    }

    public func renderSyntax(
        in textStorage: NSMutableAttributedString,
        activeLineIndex: Int? = nil,
        isInsertMode: Bool = false
    ) {
        let fullString = textStorage.string as NSString
        guard fullString.length > 0 else { return }

        // Find all line ranges
        var lineRanges: [NSRange] = []
        var idx = 0
        while idx < fullString.length {
            let lr = fullString.lineRange(for: NSRange(location: idx, length: 0))
            lineRanges.append(lr)
            idx = lr.location + lr.length
        }

        let defaultFont = NSFont.systemFont(ofSize: 14)
        let defaultTextColor = NSColor.labelColor

        for lineRange in lineRanges {
            // Apply markdown formatting permanently to all lines in all modes (NORMAL, VISUAL, INSERT)
            textStorage.setAttributes([
                .font: defaultFont,
                .foregroundColor: defaultTextColor
            ], range: lineRange)

            let lineString = fullString.substring(with: lineRange)
            let nsLine = lineString as NSString
            let lineLength = nsLine.length

            var lineFont = defaultFont

            // 1. Headers: ^(#{1,6}\s+)
            if let hMatch = Self.headerRegex.firstMatch(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let prefix = nsLine.substring(with: hMatch.range(at: 1))
                let level = prefix.filter { $0 == "#" }.count
                let size: CGFloat = {
                    switch level {
                    case 1: return 22
                    case 2: return 18
                    case 3: return 16
                    case 4: return 15
                    case 5: return 14
                    default: return 13
                    }
                }()
                let hFont = NSFont.boldSystemFont(ofSize: size)
                lineFont = hFont
                textStorage.addAttribute(.font, value: hFont, range: lineRange)

                // Header delimiter styling (muted/concealed)
                let delimRange = NSRange(location: lineRange.location + hMatch.range(at: 1).location, length: hMatch.range(at: 1).length)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: delimRange)

                // Paragraph style for header spacing
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = 3
                pStyle.paragraphSpacing = 3
                textStorage.addAttribute(.paragraphStyle, value: pStyle, range: lineRange)
            }

            // 2. Bold spans: (**...** or __...__)
            for m in Self.boldRegex.matches(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let fullMatchRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)
                let boldFont = NSFontManager.shared.convert(lineFont, toHaveTrait: .boldFontMask)
                textStorage.addAttribute(.font, value: boldFont, range: fullMatchRange)

                if m.range.length >= 4 {
                    let openDelim = NSRange(location: fullMatchRange.location, length: 2)
                    let closeDelim = NSRange(location: fullMatchRange.location + fullMatchRange.length - 2, length: 2)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openDelim)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeDelim)
                }
            }

            // 3. Italic spans: (*...* or _..._)
            for m in Self.italicRegex.matches(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let fullMatchRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)
                let italicFont = NSFontManager.shared.convert(lineFont, toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: fullMatchRange)

                if m.range.length >= 2 {
                    let openDelim = NSRange(location: fullMatchRange.location, length: 1)
                    let closeDelim = NSRange(location: fullMatchRange.location + fullMatchRange.length - 1, length: 1)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openDelim)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeDelim)
                }
            }

            // 4. Inline code spans: `...`
            for m in Self.codeRegex.matches(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let fullMatchRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)
                let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                textStorage.addAttribute(.font, value: codeFont, range: fullMatchRange)
                textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: fullMatchRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullMatchRange)

                if m.range.length >= 2 {
                    let openDelim = NSRange(location: fullMatchRange.location, length: 1)
                    let closeDelim = NSRange(location: fullMatchRange.location + fullMatchRange.length - 1, length: 1)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openDelim)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeDelim)
                }
            }

            // 5. Links: [title](url)
            for m in Self.linkRegex.matches(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let fullMatchRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)
                let titleLocalRange = m.range(at: 1)
                let titleMatchRange = NSRange(location: lineRange.location + titleLocalRange.location, length: titleLocalRange.length)

                textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: titleMatchRange)
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: titleMatchRange)

                // Conceal / subtle style delimiters '[' and '](url)'
                let openBracket = NSRange(location: fullMatchRange.location, length: 1)
                let closeAndUrl = NSRange(location: titleMatchRange.location + titleMatchRange.length, length: fullMatchRange.length - (1 + titleLocalRange.length))
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openBracket)
                textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeAndUrl)
            }

            // 6. Strikethrough: ~~...~~
            for m in Self.strikeRegex.matches(in: lineString, range: NSRange(location: 0, length: lineLength)) {
                let fullMatchRange = NSRange(location: lineRange.location + m.range.location, length: m.range.length)
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullMatchRange)

                if m.range.length >= 4 {
                    let openDelim = NSRange(location: fullMatchRange.location, length: 2)
                    let closeDelim = NSRange(location: fullMatchRange.location + fullMatchRange.length - 2, length: 2)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: openDelim)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: closeDelim)
                }
            }
        }
    }
}
