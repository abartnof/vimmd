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
    public static var delimiterColor: NSColor {
        get { DelimiterColorManager.shared.delimiterColor }
        set { DelimiterColorManager.shared.delimiterColor = newValue }
    }

    public init() {}

    public func renderTabularSyntax(in storage: NSTextStorage, isTSV: Bool, wrapTableCells: Bool = false, customColumnWidths: [Int: CGFloat] = [:]) {
        renderTabularSyntax(in: storage as NSMutableAttributedString, isTSV: isTSV, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)
    }

    public func parseRecordRanges(in fullString: NSString, isTSV: Bool) -> [NSRange] {
        let length = fullString.length
        guard length > 0 else { return [] }

        var recordRanges: [NSRange] = []
        var recordStart = 0
        var inQuotes = false
        var i = 0

        while i < length {
            let char = fullString.character(at: i)

            if !isTSV && char == 34 { // '"'
                if inQuotes {
                    if i + 1 < length && fullString.character(at: i + 1) == 34 {
                        // Escaped double quote ("") -> skip second quote
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if !inQuotes && (char == 10 || char == 13) {
                // Newline outside of quotes -> record delimiter
                if char == 13 && i + 1 < length && fullString.character(at: i + 1) == 10 {
                    // CRLF (\r\n)
                    let recordLen = (i + 2) - recordStart
                    recordRanges.append(NSRange(location: recordStart, length: recordLen))
                    i += 1
                    recordStart = i + 1
                } else {
                    // LF (\n) or lone CR (\r)
                    let recordLen = (i + 1) - recordStart
                    recordRanges.append(NSRange(location: recordStart, length: recordLen))
                    recordStart = i + 1
                }
            }
            i += 1
        }

        if recordStart < length {
            let recordLen = length - recordStart
            recordRanges.append(NSRange(location: recordStart, length: recordLen))
        }

        return recordRanges
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

        let recordRanges = parseRecordRanges(in: fullString, isTSV: isTSV)

        let regularFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        var maxCols = 1
        var parsedLines: [[(columnIndex: Int, range: NSRange)]] = []

        for recordRange in recordRanges {
            var contentLength = recordRange.length
            while contentLength > 0 {
                let char = fullString.character(at: recordRange.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }
            let contentRange = NSRange(location: recordRange.location, length: contentLength)
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

        // Find all RFC 4180 record ranges
        let recordRanges = parseRecordRanges(in: fullString, isTSV: isTSV)

        let regularFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let delimiterColor = DelimiterColorManager.shared.delimiterColor

        let colWidths = calculateColumnWidths(in: storage, isTSV: isTSV, wrapTableCells: wrapTableCells, customColumnWidths: customColumnWidths)

        // Build tabStops for paragraph style
        var tabStops: [NSTextTab] = []
        var runningX: CGFloat = 0
        for w in colWidths {
            runningX += w
            tabStops.append(NSTextTab(textAlignment: .left, location: runningX, options: [:]))
        }

        for (recordIndex, recordRange) in recordRanges.enumerated() {
            let isHeader = (recordIndex == 0)
            let baseFont = isHeader ? boldFont : regularFont
            let baseColor = NSColor.labelColor

            let pStyle = NSMutableParagraphStyle()
            pStyle.tabStops = tabStops
            pStyle.lineBreakMode = wrapTableCells ? .byWordWrapping : .byClipping

            // Clean/reset attributes across the record range
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: baseColor,
                .paragraphStyle: pStyle
            ], range: recordRange)

            // Content length excluding trailing newlines (\r, \n)
            var contentLength = recordRange.length
            while contentLength > 0 {
                let char = fullString.character(at: recordRange.location + contentLength - 1)
                if char == 10 || char == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }

            guard contentLength > 0 else {
                continue
            }

            let contentRange = NSRange(location: recordRange.location, length: contentLength)
            if isHeader {
                // Neutral subtle header shading
                storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: contentRange)
            } else {
                storage.removeAttribute(.backgroundColor, range: recordRange)
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
                storage.addAttribute(.foregroundColor, value: delimiterColor, range: delimRange)

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
