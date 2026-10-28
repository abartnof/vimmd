import Foundation
import AppKit

public struct TabularSyntaxResolver {
    public static let columnColors: [NSColor] = [
        NSColor.systemTeal,    // Col 0: Cyan / Teal
        NSColor.systemPurple,  // Col 1: Purple / Indigo
        NSColor.systemBlue,    // Col 2: Blue / Azure
        NSColor.systemGreen,   // Col 3: Green / Emerald
        NSColor.systemOrange   // Col 4: Orange / Amber
    ]

    public init() {}

    public func renderTabularSyntax(in storage: NSTextStorage, isTSV: Bool) {
        renderTabularSyntax(in: storage as NSMutableAttributedString, isTSV: isTSV)
    }

    public func renderTabularSyntax(in storage: NSMutableAttributedString, isTSV: Bool) {
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return }

        // Find all line ranges
        var lineRanges: [NSRange] = []
        var idx = 0
        while idx < fullString.length {
            let lr = fullString.lineRange(for: NSRange(location: idx, length: 0))
            lineRanges.append(lr)
            idx = lr.location + lr.length
        }

        let regularFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        for (lineIndex, lineRange) in lineRanges.enumerated() {
            let isHeader = (lineIndex == 0)
            let baseFont = isHeader ? boldFont : regularFont
            let baseColor = NSColor.labelColor

            // Clean/reset attributes across the line range
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: baseColor
            ], range: lineRange)

            // Content length excluding trailing newlines (\r, \n)
            var contentLength = lineRange.length
            while contentLength > 0 {
                let char = fullString.character(at: lineRange.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }

            guard contentLength > 0 else {
                continue
            }

            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            if isHeader {
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentRange)
            } else {
                storage.removeAttribute(.backgroundColor, range: lineRange)
            }

            // Parse fields and delimiters within contentRange
            let (fields, delimiters) = parseLine(in: fullString, range: contentRange, isTSV: isTSV)

            // Apply field attributes
            for (colIdx, fieldRange) in fields {
                guard fieldRange.length > 0 else { continue }
                if isHeader {
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fieldRange)
                    storage.addAttribute(.font, value: boldFont, range: fieldRange)
                } else {
                    let colColor = Self.columnColors[colIdx % Self.columnColors.count]
                    storage.addAttribute(.foregroundColor, value: colColor, range: fieldRange)
                    storage.addAttribute(.font, value: regularFont, range: fieldRange)
                }
            }

            // Apply delimiter attributes
            for delimRange in delimiters {
                guard delimRange.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: delimRange)
            }
        }
    }

    public func parseLine(in fullString: NSString, range: NSRange, isTSV: Bool) -> (fields: [(columnIndex: Int, range: NSRange)], delimiters: [NSRange]) {
        var fields: [(columnIndex: Int, range: NSRange)] = []
        var delimiters: [NSRange] = []

        let start = range.location
        let length = range.length
        let delimiterChar: unichar = isTSV ? 9 : 44 // 9 = '\t', 44 = ','

        var colIdx = 0
        var fieldStart = start
        var i = start
        var inQuotes = false

        while i < start + length {
            let c = fullString.character(at: i)
            if !isTSV && c == 34 { // '"'
                if inQuotes {
                    // Check for escaped double quote ("")
                    if i + 1 < start + length && fullString.character(at: i + 1) == 34 {
                        i += 1 // Skip escaped quote
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if c == delimiterChar && !inQuotes {
                // End of current field
                let fieldRange = NSRange(location: fieldStart, length: i - fieldStart)
                fields.append((columnIndex: colIdx, range: fieldRange))
                delimiters.append(NSRange(location: i, length: 1))
                colIdx += 1
                fieldStart = i + 1
            }
            i += 1
        }

        // Final field
        let fieldRange = NSRange(location: fieldStart, length: (start + length) - fieldStart)
        fields.append((columnIndex: colIdx, range: fieldRange))

        return (fields, delimiters)
    }
}
