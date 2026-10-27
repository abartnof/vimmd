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
    // Precompiled cached NSRegularExpression patterns
    public static let headerRegex = try! NSRegularExpression(pattern: "^(#{1,6}\\s+)")
    public static let boldRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(.*?)\\1")
    public static let italicRegex = try! NSRegularExpression(pattern: "(?<!\\*|_)(\\*|_)(?!\\*|_)(.*?)(?<!\\*|_)\\1(?!\\*|_)")
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
}
