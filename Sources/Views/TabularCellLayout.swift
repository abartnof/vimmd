import AppKit
import Foundation

/// Custom NSLayoutManager that suppresses AppKit's default glyph and background drawing
/// when VimMDTextView handles tabular cell wrapping, clipping, and grid rendering directly.
public final class TabularLayoutManager: NSLayoutManager {
    override public func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let tv = textContainers.first?.textView as? VimMDTextView,
           tv.usesCustomTabularCellRendering {
            return
        }
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }

    override public func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let tv = textContainers.first?.textView as? VimMDTextView,
           tv.usesCustomTabularCellRendering {
            return
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

/// Pure, modular layout and rendering helper for tabular spreadsheet cells.
public enum TabularCellLayout {
    public static let cellHorizontalPadding: CGFloat = 4.0
    public static let defaultSingleLineHeight: CGFloat = 18.0

    public struct RowMetrics {
        public let rowOriginsY: [CGFloat]
        public let rowHeights: [CGFloat]
        public let totalHeight: CGFloat

        public static let empty = RowMetrics(rowOriginsY: [], rowHeights: [], totalHeight: defaultSingleLineHeight)
    }

    public static func cellTextRect(for cellRect: NSRect) -> NSRect {
        let insetX = min(cellHorizontalPadding, cellRect.width * 0.25)
        return NSRect(
            x: cellRect.minX + insetX,
            y: cellRect.minY,
            width: max(8.0, cellRect.width - insetX * 2.0),
            height: cellRect.height
        )
    }

    public static func singleLineHeight(for fontSize: CGFloat) -> CGFloat {
        let regularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let metricsHeight = ceil(regularFont.ascender - regularFont.descender + regularFont.leading)
        return max(defaultSingleLineHeight, metricsHeight + 2.0)
    }

    /// Computes per-row Y offsets and heights. Uses a fast-path check for short single-line
    /// cells so 100k-cell spreadsheets stay well within latency budgets.
    public static func computeRowMetrics(
        in fullString: NSString,
        recordRanges: [NSRange],
        colWidths: [CGFloat],
        isTSV: Bool,
        wrapTableCells: Bool,
        fontSize: CGFloat,
        resolver: TabularSyntaxResolver
    ) -> RowMetrics {
        guard !recordRanges.isEmpty else {
            return RowMetrics(rowOriginsY: [0], rowHeights: [singleLineHeight(for: fontSize)], totalHeight: singleLineHeight(for: fontSize))
        }

        let baseHeight = singleLineHeight(for: fontSize)
        let count = recordRanges.count

        if !wrapTableCells {
            var origins = [CGFloat]()
            origins.reserveCapacity(count)
            let heights = [CGFloat](repeating: baseHeight, count: count)
            var y: CGFloat = 0
            for _ in 0..<count {
                origins.append(y)
                y += baseHeight
            }
            return RowMetrics(rowOriginsY: origins, rowHeights: heights, totalHeight: max(baseHeight, y))
        }

        let regularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let boldCharWidth = ("M" as NSString).size(withAttributes: [.font: boldFont]).width
        let maxCharWidth = boldCharWidth * 1.25

        // Reusable TextKit stack for cells that exceed the fast-path single-line width
        let measureStorage = NSTextStorage()
        let measureLayout = NSLayoutManager()
        let measureContainer = NSTextContainer(size: NSSize(width: 240.0, height: CGFloat.greatestFiniteMagnitude))
        measureContainer.lineFragmentPadding = 0
        measureLayout.addTextContainer(measureContainer)
        measureStorage.addLayoutManager(measureLayout)

        let pStyle = NSMutableParagraphStyle()
        pStyle.lineBreakMode = .byWordWrapping

        var origins = [CGFloat]()
        var heights = [CGFloat]()
        origins.reserveCapacity(count)
        heights.reserveCapacity(count)

        var currentY: CGFloat = 0

        for (rowIdx, recordRange) in recordRanges.enumerated() {
            origins.append(currentY)

            var contentLength = recordRange.length
            while contentLength > 0 {
                let c = fullString.character(at: recordRange.location + contentLength - 1)
                if c == 10 || c == 13 {
                    contentLength -= 1
                } else {
                    break
                }
            }

            guard contentLength > 0 else {
                heights.append(baseHeight)
                currentY += baseHeight
                continue
            }

            let contentRange = NSRange(location: recordRange.location, length: contentLength)
            let (fields, _) = resolver.parseLine(in: fullString, range: contentRange, isTSV: isTSV)
            let font = (rowIdx == 0) ? boldFont : regularFont

            var rowHeight = baseHeight
            for field in fields {
                guard field.range.length > 0 else { continue }
                let colWidth = field.columnIndex < colWidths.count ? colWidths[field.columnIndex] : 240.0
                let availWidth = max(8.0, colWidth - min(cellHorizontalPadding, colWidth * 0.25) * 2.0)

                // Fast-path: if worst-case character width fits on one line and no embedded newline, skip TextKit
                let worstCaseWidth = CGFloat(field.range.length) * maxCharWidth
                if worstCaseWidth <= availWidth {
                    let hasNewline = fullString.range(of: "\n", options: [], range: field.range).location != NSNotFound
                        || fullString.range(of: "\r", options: [], range: field.range).location != NSNotFound
                    if !hasNewline {
                        continue
                    }
                }

                let cellText = fullString.substring(with: field.range)
                measureContainer.size = NSSize(width: availWidth, height: CGFloat.greatestFiniteMagnitude)
                measureStorage.setAttributedString(NSAttributedString(string: cellText, attributes: [
                    .font: font,
                    .paragraphStyle: pStyle
                ]))
                measureLayout.ensureLayout(for: measureContainer)
                let used = measureLayout.usedRect(for: measureContainer)
                let measuredHeight = ceil(used.height) + 2.0
                if measuredHeight > rowHeight {
                    rowHeight = measuredHeight
                }
            }

            heights.append(rowHeight)
            currentY += rowHeight
        }

        return RowMetrics(rowOriginsY: origins, rowHeights: heights, totalHeight: max(baseHeight, currentY))
    }

    /// Reusable TextKit stack for measuring, laying out, and rendering tabular cells
    /// without allocating a new NSTextStorage/NSLayoutManager/NSTextContainer per cell.
    public final class CellTextKitStack {
        public let textStorage: NSTextStorage
        public let layoutManager: NSLayoutManager
        public let textContainer: NSTextContainer
        private let paragraphStyle: NSMutableParagraphStyle

        public init() {
            self.textStorage = NSTextStorage()
            self.layoutManager = NSLayoutManager()
            self.textContainer = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            self.textContainer.lineFragmentPadding = 0
            self.paragraphStyle = NSMutableParagraphStyle()
            self.layoutManager.addTextContainer(self.textContainer)
            self.textStorage.addLayoutManager(self.layoutManager)
        }

        public func layout(
            text: String,
            font: NSFont,
            color: NSColor,
            availWidth: CGFloat,
            wrap: Bool
        ) {
            paragraphStyle.lineBreakMode = wrap ? .byWordWrapping : .byClipping
            let containerWidth = wrap ? max(8.0, availWidth) : CGFloat.greatestFiniteMagnitude
            textContainer.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            let attr = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ])
            textStorage.setAttributedString(attr)
            layoutManager.ensureLayout(for: textContainer)
        }

        public func selectionRects(for localSelRange: NSRange, in cellRect: NSRect) -> [NSRect] {
            let textLen = textStorage.length
            guard textLen > 0, localSelRange.length > 0, localSelRange.location >= 0, localSelRange.location < textLen else {
                return []
            }
            let clampedLen = min(localSelRange.length, textLen - localSelRange.location)
            let clampedCharRange = NSRange(location: localSelRange.location, length: clampedLen)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedCharRange, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return [] }

            let textRect = TabularCellLayout.cellTextRect(for: cellRect)
            var rects: [NSRect] = []
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: glyphRange,
                in: textContainer
            ) { rect, _ in
                let shifted = rect.offsetBy(dx: textRect.origin.x, dy: textRect.origin.y)
                let clipped = shifted.intersection(cellRect)
                if !clipped.isNull && clipped.width > 0 && clipped.height > 0 {
                    rects.append(clipped)
                }
            }
            return rects
        }
    }

    public static func localSelectionRange(selection: NSRange, fieldRange: NSRange) -> NSRange? {
        guard selection.length > 0, fieldRange.length > 0 else { return nil }
        let inter = NSIntersectionRange(selection, fieldRange)
        guard inter.length > 0 else { return nil }
        return NSRange(location: inter.location - fieldRange.location, length: inter.length)
    }

    public static func selectionRects(
        text: String,
        selectedRange: NSRange,
        font: NSFont,
        cellRect: NSRect,
        wrap: Bool,
        stack: CellTextKitStack
    ) -> [NSRect] {
        guard !text.isEmpty, selectedRange.length > 0, cellRect.width > 0, cellRect.height > 0 else { return [] }
        let textRect = cellTextRect(for: cellRect)
        stack.layout(
            text: text,
            font: font,
            color: NSColor.labelColor,
            availWidth: textRect.width,
            wrap: wrap
        )
        return stack.selectionRects(for: selectedRange, in: cellRect)
    }

    public static func drawCell(
        text: String,
        font: NSFont,
        color: NSColor,
        cellRect: NSRect,
        wrap: Bool,
        selectedRange: NSRange? = nil,
        stack: CellTextKitStack? = nil
    ) {
        guard !text.isEmpty, cellRect.width > 0, cellRect.height > 0 else { return }
        let textRect = cellTextRect(for: cellRect)
        let activeStack = stack ?? CellTextKitStack()
        activeStack.layout(
            text: text,
            font: font,
            color: color,
            availWidth: textRect.width,
            wrap: wrap
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cellRect).addClip()

        if let sel = selectedRange, sel.length > 0 {
            let selRects = activeStack.selectionRects(for: sel, in: cellRect)
            if !selRects.isEmpty {
                NSColor.selectedTextBackgroundColor.setFill()
                for r in selRects {
                    r.fill()
                }
            }
        }

        let glyphRange = activeStack.layoutManager.glyphRange(for: activeStack.textContainer)
        if glyphRange.location != NSNotFound && glyphRange.length > 0 {
            activeStack.layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textRect.origin)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    public static func insertionBaseRect(
        at charIndex: Int,
        in fullString: NSString,
        recordRanges: [NSRange],
        rowOriginsY: [CGFloat],
        rowHeights: [CGFloat],
        colWidths: [CGFloat],
        textContainerInset: NSSize,
        isTSV: Bool,
        wrapTableCells: Bool,
        fontSize: CGFloat,
        resolver: TabularSyntaxResolver,
        stack: CellTextKitStack? = nil
    ) -> NSRect {
        let baseHeight = singleLineHeight(for: fontSize)
        guard fullString.length > 0, !recordRanges.isEmpty else {
            return NSRect(
                x: textContainerInset.width + cellHorizontalPadding,
                y: textContainerInset.height,
                width: 2.0,
                height: baseHeight
            )
        }

        let clampedIndex = max(0, min(fullString.length, charIndex))

        // Trailing empty line after final newline
        if clampedIndex == fullString.length {
            let lastChar = fullString.character(at: fullString.length - 1)
            if lastChar == 10 || lastChar == 13 {
                let lastRowIdx = recordRanges.count - 1
                let lastY = (lastRowIdx < rowOriginsY.count ? rowOriginsY[lastRowIdx] : 0)
                let lastH = (lastRowIdx < rowHeights.count ? rowHeights[lastRowIdx] : baseHeight)
                return NSRect(
                    x: textContainerInset.width + cellHorizontalPadding,
                    y: textContainerInset.height + lastY + lastH,
                    width: 2.0,
                    height: baseHeight
                )
            }
        }

        // Binary search recordRanges for clampedIndex
        var rowIdx = recordRanges.count - 1
        var low = 0
        var high = recordRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let r = recordRanges[mid]
            if clampedIndex < r.location {
                high = mid - 1
            } else if clampedIndex >= NSMaxRange(r) && !(mid == recordRanges.count - 1 && clampedIndex == NSMaxRange(r)) {
                low = mid + 1
            } else {
                rowIdx = mid
                break
            }
        }

        let recordRange = recordRanges[rowIdx]
        let rowY = textContainerInset.height + (rowIdx < rowOriginsY.count ? rowOriginsY[rowIdx] : CGFloat(rowIdx) * baseHeight)
        let rowH = rowIdx < rowHeights.count ? rowHeights[rowIdx] : baseHeight

        var contentLength = recordRange.length
        while contentLength > 0 {
            let c = fullString.character(at: recordRange.location + contentLength - 1)
            if c == 10 || c == 13 {
                contentLength -= 1
            } else {
                break
            }
        }
        let contentRange = NSRange(location: recordRange.location, length: contentLength)
        let (fields, delimiters) = resolver.parseLine(in: fullString, range: contentRange, isTSV: isTSV)

        // Helper to compute column X
        func columnMinX(_ col: Int) -> CGFloat {
            var x = textContainerInset.width
            for i in 0..<min(col, colWidths.count) {
                x += colWidths[i]
            }
            return x
        }

        // Check if charIndex is inside or at the end of a field
        var targetField: (columnIndex: Int, range: NSRange)?
        for field in fields {
            if clampedIndex >= field.range.location && clampedIndex <= NSMaxRange(field.range) {
                targetField = field
                break
            }
        }

        // If charIndex is on a delimiter, anchor at end of preceding field
        if targetField == nil {
            for (dIdx, delim) in delimiters.enumerated() {
                if clampedIndex >= delim.location && clampedIndex < NSMaxRange(delim) {
                    if dIdx < fields.count {
                        targetField = fields[dIdx]
                    }
                    break
                }
            }
        }

        // Fallback: trailing newline at end of record -> anchor at end of last field
        if targetField == nil, let lastField = fields.last {
            targetField = lastField
        }

        guard let field = targetField else {
            return NSRect(x: textContainerInset.width + cellHorizontalPadding, y: rowY, width: 2.0, height: rowH)
        }

        let col = field.columnIndex
        let colWidth = col < colWidths.count ? colWidths[col] : 240.0
        let cellRect = NSRect(x: columnMinX(col), y: rowY, width: colWidth, height: rowH)
        let textRect = cellTextRect(for: cellRect)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: rowIdx == 0 ? .bold : .regular)

        if field.range.length == 0 {
            return NSRect(x: textRect.minX, y: textRect.minY, width: 2.0, height: baseHeight)
        }

        let localOffset = max(0, min(field.range.length, clampedIndex - field.range.location))
        let cellText = fullString.substring(with: field.range)
        let activeStack = stack ?? CellTextKitStack()
        activeStack.layout(
            text: cellText,
            font: font,
            color: NSColor.labelColor,
            availWidth: textRect.width,
            wrap: wrapTableCells
        )
        let layoutManager = activeStack.layoutManager
        let textContainer = activeStack.textContainer

        guard layoutManager.numberOfGlyphs > 0 else {
            return NSRect(x: textRect.minX, y: textRect.minY, width: 2.0, height: baseHeight)
        }

        let rawRect: NSRect
        if localOffset >= field.range.length {
            let lastGlyph = layoutManager.numberOfGlyphs - 1
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            let lastGlyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: lastGlyph, length: 1), in: textContainer)
            rawRect = NSRect(
                x: textRect.minX + lastGlyphRect.maxX,
                y: textRect.minY + lineRect.minY,
                width: 2.0,
                height: lineRect.height > 0 ? lineRect.height : baseHeight
            )
        } else {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: localOffset)
            let clampedGlyph = min(glyphIndex, layoutManager.numberOfGlyphs - 1)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: clampedGlyph, effectiveRange: nil)
            let pt = layoutManager.location(forGlyphAt: clampedGlyph)
            rawRect = NSRect(
                x: textRect.minX + pt.x,
                y: textRect.minY + lineRect.minY,
                width: 2.0,
                height: lineRect.height > 0 ? lineRect.height : baseHeight
            )
        }

        if !wrapTableCells {
            let clampedX = min(rawRect.origin.x, max(textRect.minX, cellRect.maxX - 2.0))
            return NSRect(x: clampedX, y: rawRect.origin.y, width: 2.0, height: rawRect.height)
        }
        return rawRect
    }
}
