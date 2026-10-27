import Foundation

/// Fast, bidirectional translation between Vim 1-based UTF-8 byte offsets,
/// Cocoa 0-based UTF-16 code-unit offsets, and visual grapheme cluster boundaries.
public struct LineCoordinateMap {
    public let rawString: String
    public let graphemeClusterCount: Int
    public let utf8ByteCount: Int
    public let utf16Count: Int

    private let byteToUtf16Table: [Int]
    private let utf16ToByteColTable: [Int]

    public init(line: String) {
        self.rawString = line

        if line.isEmpty {
            self.graphemeClusterCount = 0
            self.utf8ByteCount = 0
            self.utf16Count = 0
            self.byteToUtf16Table = [0]
            self.utf16ToByteColTable = [1]
            return
        }

        let totalU8 = line.utf8.count
        let totalU16 = line.utf16.count

        var byteTable = [Int](repeating: 0, count: totalU8 + 1)
        var utf16Table = [Int](repeating: 1, count: totalU16 + 1)

        var currentByteOffset = 0
        var currentUtf16Offset = 0
        var clusterCount = 0

        for character in line {
            clusterCount += 1
            let charU8 = character.utf8.count
            let charU16 = character.utf16.count
            let startCol = currentByteOffset + 1

            for b in 0..<charU8 {
                byteTable[currentByteOffset + b] = currentUtf16Offset
            }

            for u in 0..<charU16 {
                utf16Table[currentUtf16Offset + u] = startCol
            }

            currentByteOffset += charU8
            currentUtf16Offset += charU16
        }

        // Terminal boundary (after last character)
        byteTable[currentByteOffset] = currentUtf16Offset
        utf16Table[currentUtf16Offset] = currentByteOffset + 1

        self.graphemeClusterCount = clusterCount
        self.utf8ByteCount = currentByteOffset
        self.utf16Count = currentUtf16Offset
        self.byteToUtf16Table = byteTable
        self.utf16ToByteColTable = utf16Table
    }

    /// Converts a 1-based Vim UTF-8 byte column to a 0-based Cocoa UTF-16 offset.
    /// Handles intra-grapheme-cluster clamping and boundary conditions.
    public func utf16Offset(fromVimByteColumn col: Int) -> Int {
        if col <= 1 {
            return 0
        }
        if col > utf8ByteCount {
            return utf16Count
        }
        let zeroBasedByte = col - 1
        return byteToUtf16Table[zeroBasedByte]
    }

    /// Converts a 0-based Cocoa UTF-16 offset to a 1-based Vim UTF-8 byte column.
    /// Intra-character / surrogate-pair offsets snap to the start byte column of that cluster.
    public func vimByteColumn(fromUtf16Offset utf16Offset: Int) -> Int {
        if utf16Offset <= 0 {
            return 1
        }
        if utf16Offset >= utf16Count {
            return utf8ByteCount + 1
        }
        return utf16ToByteColTable[utf16Offset]
    }
}

/// Maintains the per-line coordinate maps and prefix sums for an entire document.
public struct DocumentCoordinateResolver {
    private var lines: [LineCoordinateMap]
    private var lineStartOffsets: [Int]

    public init(documentText: String) {
        // Normalize CRLF (\r\n) and lone CR (\r) to standard newline (\n)
        let normalized = documentText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let stringLines = normalized.components(separatedBy: "\n")
        self.lines = stringLines.map { LineCoordinateMap(line: $0) }
        self.lineStartOffsets = []
        rebuildOffsets()
    }

    public var lineCount: Int {
        return lines.count
    }

    public func lineMap(at line: Int) -> LineCoordinateMap? {
        guard line >= 1 && line <= lines.count else { return nil }
        return lines[line - 1]
    }

    /// Total UTF-16 code units in the document.
    public var totalUtf16Length: Int {
        guard !lines.isEmpty else { return 0 }
        return lineStartOffsets[lines.count - 1] + lines[lines.count - 1].utf16Count
    }

    /// Calculates the full-document UTF-16 character range for a block of lines.
    /// Designed for TextKit 2 delta replacements per DESIGN.md §3.5.
    public func characterRange(startLine: Int, count: Int) -> NSRange {
        guard !lines.isEmpty else {
            return NSRange(location: 0, length: 0)
        }

        let totalLength = self.totalUtf16Length

        // If startLine is beyond the end of the document, return insertion range at EOF
        if startLine > lines.count {
            return NSRange(location: totalLength, length: 0)
        }

        let startIdx = max(0, startLine - 1)
        let startOffset = lineStartOffsets[startIdx]

        if count <= 0 {
            return NSRange(location: startOffset, length: 0)
        }

        let endIdx = max(startIdx, min(lines.count - 1, startIdx + count - 1))
        let endOffset = lineStartOffsets[endIdx] + lines[endIdx].utf16Count
        let length = max(0, endOffset - startOffset)

        return NSRange(location: startOffset, length: length)
    }

    /// Converts 1-based line number and 1-based Vim byte column to 0-based document UTF-16 offset.
    public func documentUtf16Offset(line: Int, vimByteCol: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        let lineIdx = max(0, min(lines.count - 1, line - 1))
        let lineStart = lineStartOffsets[lineIdx]
        let offsetInLine = lines[lineIdx].utf16Offset(fromVimByteColumn: vimByteCol)
        return lineStart + offsetInLine
    }

    /// Converts 0-based document UTF-16 offset to 1-based line number and 1-based Vim byte column.
    public func vimPosition(fromDocumentUtf16Offset offset: Int) -> (line: Int, byteCol: Int) {
        guard !lines.isEmpty else { return (1, 1) }

        let totalLength = self.totalUtf16Length
        let clamped = max(0, min(totalLength, offset))

        // Binary search for the line index containing clamped offset
        var low = 0
        var high = lines.count - 1
        var lineIdx = 0

        while low <= high {
            let mid = (low + high) / 2
            let lineStart = lineStartOffsets[mid]
            let lineEnd = lineStart + lines[mid].utf16Count

            if clamped < lineStart {
                high = mid - 1
            } else if clamped > lineEnd {
                if mid == lines.count - 1 {
                    lineIdx = mid
                    break
                }
                low = mid + 1
            } else {
                // clamped is within line mid or at its trailing boundary
                lineIdx = mid
                break
            }
        }

        let lineStart = lineStartOffsets[lineIdx]
        let lineOffset = clamped - lineStart
        let byteCol = lines[lineIdx].vimByteColumn(fromUtf16Offset: lineOffset)
        return (line: lineIdx + 1, byteCol: byteCol)
    }

    /// Incrementally updates lines affected by an Ex command (:s) or edit delta.
    /// Avoids reindexing the entire document.
    public mutating func updateLines(at startLine: Int, deleted: Int, inserted: [String]) {
        let startIdx = max(0, min(lines.count, startLine - 1))
        let deleteCount = max(0, min(lines.count - startIdx, deleted))

        let normalizedInserted = inserted.flatMap {
            $0.replacingOccurrences(of: "\r\n", with: "\n")
              .replacingOccurrences(of: "\r", with: "\n")
              .components(separatedBy: "\n")
        }
        let newMaps = normalizedInserted.map { LineCoordinateMap(line: $0) }
        lines.replaceSubrange(startIdx..<(startIdx + deleteCount), with: newMaps)

        if lines.isEmpty {
            lines = [LineCoordinateMap(line: "")]
        }

        rebuildOffsets()
    }

    private mutating func rebuildOffsets() {
        lineStartOffsets.removeAll(keepingCapacity: true)
        lineStartOffsets.reserveCapacity(lines.count)

        var currentOffset = 0
        for (idx, line) in lines.enumerated() {
            lineStartOffsets.append(currentOffset)
            currentOffset += line.utf16Count
            // Account for '\n' separator between lines (except after the last line)
            if idx < lines.count - 1 {
                currentOffset += 1
            }
        }
    }
}

public typealias LineIndexTable = DocumentCoordinateResolver
