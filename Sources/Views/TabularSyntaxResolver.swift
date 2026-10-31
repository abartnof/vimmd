import Foundation
import AppKit

public struct TabularSyntaxResolver {
    /// Preserved for backward compatibility, mapped to neutral styling.
    public static let columnColors: [NSColor] = [
        NSColor.labelColor,
        NSColor.labelColor,
        NSColor.labelColor,
        NSColor.labelColor,
        NSColor.labelColor
    ]

    public static let neutralTextColor = NSColor.labelColor
    public static let headerBackgroundColor = NSColor.quaternaryLabelColor
    public static let delimiterColor = NSColor.tertiaryLabelColor

    public init() {}

    public func renderTabularSyntax(in storage: NSTextStorage, isTSV: Bool, wrapTableCells: Bool = false, customColumnWidths: [Int: CGFloat] = [:]) {
        renderTabularSyntax(in: storage as NSMutableAttributedString, isTSV: isTSV, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)
    }

    public func calculateColumnWidths(
        in storage: NSAttributedString,
        isTSV: Bool,
        wrapTableCells: Bool,
        defaultWrapWidth: CGFloat = 240.0,
        minColumnWidth: CGFloat = 60.0,
        padding: CGFloat = 20.0,
        customColumnWidths: [Int: CGFloat] = [:]
    ) -> [CGFloat] {
        let fullString = storage.string as NSString
        guard fullString.length > 0 else { return [] }

        var lineRanges: [NSRange] = []
        var idx = 0
        while idx < fullString.length {
            let lr = fullString.lineRange(for: NSRange(location: idx, length: 0))
            lineRanges.append(lr)
            idx = lr.location + lr.length
        }

        let regularFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        var maxCols = 1
        var parsedLines: [[(columnIndex: Int, range: NSRange)]] = []

        for lineRange in lineRanges {
            var contentLength = lineRange.length
            while contentLength > 0 {
                let char = fullString.character(at: lineRange.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            let (fields, _) = parseLine(in: fullString, range: contentRange, isTSV: isTSV)
            parsedLines.append(fields)
            if fields.count > maxCols {
                maxCols = fields.count
            }
        }

        if wrapTableCells {
            var widths = Array(repeating: defaultWrapWidth, count: maxCols)
            for (lineIdx, fields) in parsedLines.enumerated() {
                let isHeader = (lineIdx == 0)
                let font = isHeader ? boldFont : regularFont
                for field in fields {
                    let col = field.columnIndex
                    guard col < maxCols else { continue }
                    guard field.range.location + field.range.length <= fullString.length else { continue }
                    let cellText = fullString.substring(with: field.range)
                    let cellWidth = (cellText as NSString).size(withAttributes: [.font: font]).width
                    let requiredWidth = ceil(cellWidth + padding)
                    if requiredWidth > widths[col] {
                        widths[col] = requiredWidth
                    }
                }
            }
            for (col, w) in customColumnWidths {
                if col < maxCols {
                    let clampedW = max(30.0, (w.isFinite && !w.isNaN) ? w : 30.0)
                    widths[col] = clampedW
                }
            }
            return widths
        }

        var colWidths = Array(repeating: minColumnWidth, count: maxCols)

        for (lineIdx, fields) in parsedLines.enumerated() {
            let isHeader = (lineIdx == 0)
            let font = isHeader ? boldFont : regularFont
            for field in fields {
                let col = field.columnIndex
                guard col < maxCols else { continue }
                guard field.range.location + field.range.length <= fullString.length else { continue }
                let cellText = fullString.substring(with: field.range)
                let cellWidth = (cellText as NSString).size(withAttributes: [.font: font]).width
                let requiredWidth = ceil(cellWidth + padding)
                if requiredWidth > colWidths[col] {
                    colWidths[col] = requiredWidth
                }
            }
        }

        for (col, w) in customColumnWidths {
            if col < maxCols {
                let clampedW = max(30.0, (w.isFinite && !w.isNaN) ? w : 30.0)
                colWidths[col] = clampedW
            }
        }

        return colWidths
    }

    public func renderTabularSyntax(in storage: NSMutableAttributedString, isTSV: Bool, wrapTableCells: Bool = false, customColumnWidths: [Int: CGFloat] = [:]) {
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

        let colWidths = calculateColumnWidths(in: storage, isTSV: isTSV, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)

        // Build tabStops for paragraph style
        var tabStops: [NSTextTab] = []
        var runningX: CGFloat = 0
        for w in colWidths {
            runningX += w
            tabStops.append(NSTextTab(textAlignment: .left, location: runningX, options: [:]))
        }

        for (lineIndex, lineRange) in lineRanges.enumerated() {
            let isHeader = (lineIndex == 0)
            let baseFont = isHeader ? boldFont : regularFont
            let baseColor = NSColor.labelColor

            let pStyle = NSMutableParagraphStyle()
            pStyle.tabStops = tabStops
            pStyle.lineBreakMode = wrapTableCells ? .byWordWrapping : .byClipping

            // Clean/reset attributes across the line range
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: baseColor,
                .paragraphStyle: pStyle
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
                // Neutral subtle header shading
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentRange)
            } else {
                storage.removeAttribute(.backgroundColor, range: lineRange)
            }

            // Parse fields and delimiters within contentRange
            let (fields, delimiters) = parseLine(in: fullString, range: contentRange, isTSV: isTSV)

            // Apply field attributes (neutral labelColor / textColor)
            for (_, fieldRange) in fields {
                guard fieldRange.length > 0 else { continue }
                if isHeader {
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fieldRange)
                    storage.addAttribute(.font, value: boldFont, range: fieldRange)
                } else {
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fieldRange)
                    storage.addAttribute(.font, value: regularFont, range: fieldRange)
                }
            }

            // Apply delimiter attributes and CSV kern alignment
            for (dIdx, delimRange) in delimiters.enumerated() {
                guard delimRange.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: delimRange)

                if !isTSV && dIdx < fields.count && dIdx < colWidths.count {
                    // For CSV, align next column by kerning delimiter comma
                    let field = fields[dIdx]
                    let fieldText = fullString.substring(with: field.range)
                    let fieldFont = isHeader ? boldFont : regularFont
                    let fieldWidth = (fieldText as NSString).size(withAttributes: [.font: fieldFont]).width
                    let commaWidth = ("," as NSString).size(withAttributes: [.font: fieldFont]).width
                    let targetColWidth = colWidths[dIdx]
                    let kern = max(0, targetColWidth - fieldWidth - commaWidth)
                    storage.addAttribute(.kern, value: kern, range: delimRange)
                }
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
