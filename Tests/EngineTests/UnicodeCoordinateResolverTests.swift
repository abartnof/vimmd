import Foundation
import Engine

func runTest(name: String, test: () throws -> Void) -> Bool {
    print("[RUN ] \(name)")
    do {
        try test()
        print("[PASS] \(name)")
        return true
    } catch {
        print("[FAIL] \(name): \(error)")
        return false
    }
}

func testAsciiLineMapping() throws {
    let line = "Hello World"
    let map = LineCoordinateMap(line: line)

    guard map.utf8ByteCount == 11 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 11 UTF-8 bytes, got \(map.utf8ByteCount)"])
    }
    guard map.utf16Count == 11 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 11 UTF-16 units, got \(map.utf16Count)"])
    }
    guard map.graphemeClusterCount == 11 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 11 graphemes, got \(map.graphemeClusterCount)"])
    }

    // Col 1 is 'H' -> offset 0
    guard map.utf16Offset(fromVimByteColumn: 1) == 0 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Col 1 should map to UTF-16 offset 0"])
    }
    // Col 6 is ' ' -> offset 5
    guard map.utf16Offset(fromVimByteColumn: 6) == 5 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Col 6 should map to UTF-16 offset 5"])
    }
    // Col 11 is 'd' -> offset 10
    guard map.utf16Offset(fromVimByteColumn: 11) == 10 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Col 11 should map to UTF-16 offset 10"])
    }
    // Col 12 is terminal -> offset 11
    guard map.utf16Offset(fromVimByteColumn: 12) == 11 else {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Col 12 should map to UTF-16 offset 11"])
    }

    // Reverse mapping
    guard map.vimByteColumn(fromUtf16Offset: 0) == 1 else {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Offset 0 should map to Vim col 1"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 5) == 6 else {
        throw NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "Offset 5 should map to Vim col 6"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 10) == 11 else {
        throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Offset 10 should map to Vim col 11"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 11) == 12 else {
        throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "Offset 11 should map to Vim col 12"])
    }
}

func testMultibyteUtf8Mapping() throws {
    // 'é' (2 bytes, 1 utf16), '€' (3 bytes, 1 utf16), '🚀' (4 bytes, 2 utf16)
    let line = "é€🚀"
    let map = LineCoordinateMap(line: line)

    guard map.utf8ByteCount == 9 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 9 UTF-8 bytes (2+3+4), got \(map.utf8ByteCount)"])
    }
    guard map.utf16Count == 4 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 4 UTF-16 units (1+1+2), got \(map.utf16Count)"])
    }
    guard map.graphemeClusterCount == 3 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 3 graphemes, got \(map.graphemeClusterCount)"])
    }

    // 'é': bytes 1..2 -> offset 0
    guard map.utf16Offset(fromVimByteColumn: 1) == 0 && map.utf16Offset(fromVimByteColumn: 2) == 0 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Bytes 1..2 should map to offset 0"])
    }
    // '€': bytes 3..5 -> offset 1
    guard map.utf16Offset(fromVimByteColumn: 3) == 1 &&
          map.utf16Offset(fromVimByteColumn: 4) == 1 &&
          map.utf16Offset(fromVimByteColumn: 5) == 1 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Bytes 3..5 should map to offset 1"])
    }
    // '🚀': bytes 6..9 -> offset 2
    guard map.utf16Offset(fromVimByteColumn: 6) == 2 &&
          map.utf16Offset(fromVimByteColumn: 7) == 2 &&
          map.utf16Offset(fromVimByteColumn: 8) == 2 &&
          map.utf16Offset(fromVimByteColumn: 9) == 2 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Bytes 6..9 should map to offset 2"])
    }
    // Terminal: byte 10 -> offset 4
    guard map.utf16Offset(fromVimByteColumn: 10) == 4 else {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Byte 10 should map to terminal offset 4"])
    }

    // Reverse mapping
    guard map.vimByteColumn(fromUtf16Offset: 0) == 1 else {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Offset 0 should map to col 1"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 1) == 3 else {
        throw NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "Offset 1 should map to col 3"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 2) == 6 else {
        throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Offset 2 should map to col 6"])
    }
    // Intra-surrogate-pair: offset 3 snaps to col 6 ('🚀')
    guard map.vimByteColumn(fromUtf16Offset: 3) == 6 else {
        throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "Offset 3 should snap to col 6"])
    }
    guard map.vimByteColumn(fromUtf16Offset: 4) == 10 else {
        throw NSError(domain: "Test", code: 12, userInfo: [NSLocalizedDescriptionKey: "Offset 4 should map to terminal col 10"])
    }
}

func testComplexGraphemeClusters() throws {
    // US Flag: 8 UTF-8 bytes, 4 UTF-16 units, 1 grapheme
    let flag = "🇺🇸"
    let mapFlag = LineCoordinateMap(line: flag)
    guard mapFlag.graphemeClusterCount == 1 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flag should be 1 grapheme, got \(mapFlag.graphemeClusterCount)"])
    }
    guard mapFlag.utf8ByteCount == 8 && mapFlag.utf16Count == 4 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Flag counts mismatch"])
    }
    for b in 1...8 {
        guard mapFlag.utf16Offset(fromVimByteColumn: b) == 0 else {
            throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Flag intra-byte \(b) should map to 0"])
        }
    }
    for u in 0...3 {
        guard mapFlag.vimByteColumn(fromUtf16Offset: u) == 1 else {
            throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Flag intra-utf16 \(u) should map to 1"])
        }
    }
    guard mapFlag.utf16Offset(fromVimByteColumn: 9) == 4 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Flag terminal offset mismatch"])
    }
    guard mapFlag.vimByteColumn(fromUtf16Offset: 4) == 9 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Flag terminal col mismatch"])
    }

    // Family emoji: 👨‍👩‍👧‍👦 (25 UTF-8 bytes, 11 UTF-16 units, 1 grapheme)
    let family = "👨‍👩‍👧‍👦"
    let mapFamily = LineCoordinateMap(line: family)
    guard mapFamily.graphemeClusterCount == 1 else {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Family should be 1 grapheme"])
    }
    guard mapFamily.utf16Offset(fromVimByteColumn: 1) == 0 &&
          mapFamily.utf16Offset(fromVimByteColumn: 25) == 0 else {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Family intra-bytes should map to 0"])
    }
    guard mapFamily.utf16Offset(fromVimByteColumn: 26) == mapFamily.utf16Count else {
        throw NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "Family terminal byte should map to utf16Count"])
    }

    // Combining accent: "e\u{0301}" (3 bytes, 2 utf16 units, 1 grapheme)
    let accent = "e\u{0301}"
    let mapAccent = LineCoordinateMap(line: accent)
    guard mapAccent.graphemeClusterCount == 1 else {
        throw NSError(domain: "Test", code: 10, userInfo: [NSLocalizedDescriptionKey: "Combining accent should be 1 grapheme"])
    }
    guard mapAccent.utf16Offset(fromVimByteColumn: 1) == 0 &&
          mapAccent.utf16Offset(fromVimByteColumn: 2) == 0 &&
          mapAccent.utf16Offset(fromVimByteColumn: 3) == 0 else {
        throw NSError(domain: "Test", code: 11, userInfo: [NSLocalizedDescriptionKey: "Combining accent intra-bytes should map to 0"])
    }
}

func testBoundaryAndEdgeCases() throws {
    // Empty line
    let empty = LineCoordinateMap(line: "")
    guard empty.utf8ByteCount == 0 && empty.utf16Count == 0 && empty.graphemeClusterCount == 0 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty line counts should be 0"])
    }
    guard empty.utf16Offset(fromVimByteColumn: 1) == 0 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty line col 1 should map to 0"])
    }
    guard empty.utf16Offset(fromVimByteColumn: 0) == 0 && empty.utf16Offset(fromVimByteColumn: -10) == 0 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Negative/zero col should clamp to 0"])
    }
    guard empty.utf16Offset(fromVimByteColumn: 100) == 0 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Out-of-bounds col should clamp to 0"])
    }
    guard empty.vimByteColumn(fromUtf16Offset: 0) == 1 && empty.vimByteColumn(fromUtf16Offset: 50) == 1 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Empty line offset should map to col 1"])
    }

    // Single character line
    let single = LineCoordinateMap(line: "x")
    guard single.utf16Offset(fromVimByteColumn: -1) == 0 &&
          single.utf16Offset(fromVimByteColumn: 0) == 0 &&
          single.utf16Offset(fromVimByteColumn: 1) == 0 &&
          single.utf16Offset(fromVimByteColumn: 2) == 1 &&
          single.utf16Offset(fromVimByteColumn: 999) == 1 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Single char clamping mismatch"])
    }
}

func testDocumentCoordinateResolverBasics() throws {
    let docText = "Line 1\nLine 2 🚀\nLine 3"
    let resolver = DocumentCoordinateResolver(documentText: docText)

    guard resolver.lineCount == 3 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 lines, got \(resolver.lineCount)"])
    }

    // Line 1: "Line 1" (len 6) + '\n' (len 1) = 7
    guard resolver.documentUtf16Offset(line: 1, vimByteCol: 1) == 0 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Line 1 col 1 should be offset 0"])
    }
    guard resolver.documentUtf16Offset(line: 1, vimByteCol: 7) == 6 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Line 1 terminal should be offset 6"])
    }

    // Line 2: start offset 7. "Line 2 🚀": 'L' at 7, '2' at 12, ' ' at 13, '🚀' at 14 (len 2)
    guard resolver.documentUtf16Offset(line: 2, vimByteCol: 1) == 7 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Line 2 col 1 should be offset 7"])
    }
    // In Line 2, '🚀' starts at byte col 8 (1-based: "Line 2 " is 7 bytes) -> offset 7 + 7 = 14
    guard resolver.documentUtf16Offset(line: 2, vimByteCol: 8) == 14 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Line 2 rocket should be offset 14"])
    }

    // Reverse lookup: vimPosition(fromDocumentUtf16Offset:)
    let posStart = resolver.vimPosition(fromDocumentUtf16Offset: 0)
    guard posStart.line == 1 && posStart.byteCol == 1 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "Offset 0 should map to (1, 1), got \(posStart)"])
    }
    let posLine2 = resolver.vimPosition(fromDocumentUtf16Offset: 7)
    guard posLine2.line == 2 && posLine2.byteCol == 1 else {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Offset 7 should map to (2, 1), got \(posLine2)"])
    }
    let posRocket = resolver.vimPosition(fromDocumentUtf16Offset: 14)
    guard posRocket.line == 2 && posRocket.byteCol == 8 else {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "Offset 14 should map to (2, 8), got \(posRocket)"])
    }
}

func testDocumentCharacterRanges() throws {
    // Lines:
    // Line 1: "aaa" (len 3, offset 0..3), '\n' at 3
    // Line 2: "bbb" (len 3, offset 4..7), '\n' at 7
    // Line 3: "ccc" (len 3, offset 8..11)
    let doc = DocumentCoordinateResolver(documentText: "aaa\nbbb\nccc")

    // Replace line 1 alone (count 1)
    let r1 = doc.characterRange(startLine: 1, count: 1)
    guard r1.location == 0 && r1.length == 3 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Line 1 range mismatch: \(r1)"])
    }

    // Replace line 2 alone (count 1)
    let r2 = doc.characterRange(startLine: 2, count: 1)
    guard r2.location == 4 && r2.length == 3 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Line 2 range mismatch: \(r2)"])
    }

    // Replace lines 2 and 3 (count 2) -> "bbb\nccc" = len 7
    let r23 = doc.characterRange(startLine: 2, count: 2)
    guard r23.location == 4 && r23.length == 7 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Lines 2..3 range mismatch: \(r23)"])
    }

    // Replace all lines 1..3 (count 3) -> entire text = len 11
    let rAll = doc.characterRange(startLine: 1, count: 3)
    guard rAll.location == 0 && rAll.length == 11 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "All lines range mismatch: \(rAll)"])
    }
}

func testDocumentLineUpdates() throws {
    var doc = DocumentCoordinateResolver(documentText: "First\nSecond\nThird")
    guard doc.lineCount == 3 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Initial line count mismatch"])
    }

    // 1. Replace middle line "Second" (startLine: 2, deleted: 1) with 2 lines ["New Second", "Second and a Half"]
    doc.updateLines(at: 2, deleted: 1, inserted: ["New Second", "Second and a Half"])
    guard doc.lineCount == 4 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "After middle replacement lineCount should be 4, got \(doc.lineCount)"])
    }

    // Line 1: "First" (5) + '\n' (1) -> offset 6
    guard doc.documentUtf16Offset(line: 2, vimByteCol: 1) == 6 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Line 2 start offset should be 6"])
    }
    // Line 2: "New Second" (10) + '\n' (1) -> offset 6 + 11 = 17
    guard doc.documentUtf16Offset(line: 3, vimByteCol: 1) == 17 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Line 3 start offset should be 17"])
    }
    // Line 3: "Second and a Half" (17) + '\n' (1) -> offset 17 + 18 = 35
    guard doc.documentUtf16Offset(line: 4, vimByteCol: 1) == 35 else {
        throw NSError(domain: "Test", code: 5, userInfo: [NSLocalizedDescriptionKey: "Line 4 start offset should be 35"])
    }

    // 2. Replace at start: line 1 replaced with ["Header Alpha", "Header Beta"]
    doc.updateLines(at: 1, deleted: 1, inserted: ["Header Alpha", "Header Beta"])
    guard doc.lineCount == 5 else {
        throw NSError(domain: "Test", code: 6, userInfo: [NSLocalizedDescriptionKey: "After start replacement lineCount should be 5, got \(doc.lineCount)"])
    }
    guard doc.documentUtf16Offset(line: 1, vimByteCol: 1) == 0 else {
        throw NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Line 1 start should be 0"])
    }

    // 3. Delete at end: delete last 2 lines
    doc.updateLines(at: 4, deleted: 2, inserted: ["Final Only"])
    guard doc.lineCount == 4 else {
        throw NSError(domain: "Test", code: 8, userInfo: [NSLocalizedDescriptionKey: "After end replacement lineCount should be 4, got \(doc.lineCount)"])
    }
}

func testBidirectionalRoundTripFidelity() throws {
    let mixed = "Hello 🚀 Swift: 日本語, café au lait, flags 🇺🇸 and family 👨‍👩‍👧‍👦."
    let map = LineCoordinateMap(line: mixed)

    var byteOffset = 0
    var utf16Offset = 0
    for char in mixed {
        let col = byteOffset + 1
        let mappedUtf16 = map.utf16Offset(fromVimByteColumn: col)
        guard mappedUtf16 == utf16Offset else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Char '\(char)' col \(col) expected utf16 \(utf16Offset), got \(mappedUtf16)"])
        }
        let roundTripCol = map.vimByteColumn(fromUtf16Offset: mappedUtf16)
        guard roundTripCol == col else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Char '\(char)' roundtrip col expected \(col), got \(roundTripCol)"])
        }
        byteOffset += char.utf8.count
        utf16Offset += char.utf16.count
    }
}

func testLineEndingVariations() throws {
    let docEmptyLines = DocumentCoordinateResolver(documentText: "\n\n")
    guard docEmptyLines.lineCount == 3 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected 3 empty lines for '\\n\\n', got \(docEmptyLines.lineCount)"])
    }
    guard docEmptyLines.documentUtf16Offset(line: 1, vimByteCol: 1) == 0 &&
          docEmptyLines.documentUtf16Offset(line: 2, vimByteCol: 1) == 1 &&
          docEmptyLines.documentUtf16Offset(line: 3, vimByteCol: 1) == 2 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty lines offsets mismatch"])
    }

    let docTrailingNewline = DocumentCoordinateResolver(documentText: "Alpha\nBeta\n")
    guard docTrailingNewline.lineCount == 3 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected 3 lines (last empty), got \(docTrailingNewline.lineCount)"])
    }
    guard docTrailingNewline.documentUtf16Offset(line: 3, vimByteCol: 1) == 11 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Trailing empty line offset mismatch"])
    }
}

func testEmptyDocumentResolver() throws {
    let doc = DocumentCoordinateResolver(documentText: "")
    guard doc.lineCount == 1 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty doc should have lineCount 1, got \(doc.lineCount)"])
    }
    guard doc.documentUtf16Offset(line: 1, vimByteCol: 1) == 0 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty doc line 1 col 1 offset should be 0"])
    }
    let pos = doc.vimPosition(fromDocumentUtf16Offset: 0)
    guard pos.line == 1 && pos.byteCol == 1 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Empty doc offset 0 position should be (1, 1), got \(pos)"])
    }
}

func testCharacterRangeEofInsertion() throws {
    // "First\nSecond" -> Line 1 len 5 + 1 = 6; Line 2 len 6 -> Total UTF-16 length = 12
    let doc = DocumentCoordinateResolver(documentText: "First\nSecond")
    let rangeEof = doc.characterRange(startLine: 3, count: 0)
    guard rangeEof.location == 12 && rangeEof.length == 0 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected EOF range {12, 0}, got \(rangeEof)"])
    }

    let rangeBeyondEof = doc.characterRange(startLine: 99, count: 5)
    guard rangeBeyondEof.location == 12 && rangeBeyondEof.length == 0 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected beyond-EOF range {12, 0}, got \(rangeBeyondEof)"])
    }
}

func testCrlfAndCrNormalization() throws {
    let docCrlf = DocumentCoordinateResolver(documentText: "Windows\r\nCRLF\r\nLines")
    guard docCrlf.lineCount == 3 else {
        throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "CRLF lineCount expected 3, got \(docCrlf.lineCount)"])
    }
    // "Windows\n" has 8 UTF-16 code units (7 + 1)
    guard docCrlf.documentUtf16Offset(line: 2, vimByteCol: 1) == 8 else {
        throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Line 2 start expected 8, got \(docCrlf.documentUtf16Offset(line: 2, vimByteCol: 1))"])
    }

    let docCr = DocumentCoordinateResolver(documentText: "Classic\rMac\rLines")
    guard docCr.lineCount == 3 else {
        throw NSError(domain: "Test", code: 3, userInfo: [NSLocalizedDescriptionKey: "CR lineCount expected 3, got \(docCr.lineCount)"])
    }
    guard docCr.documentUtf16Offset(line: 2, vimByteCol: 1) == 8 else {
        throw NSError(domain: "Test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Line 2 start expected 8, got \(docCr.documentUtf16Offset(line: 2, vimByteCol: 1))"])
    }
}

print("=== UnicodeCoordinateResolver Unit Tests ===")
var total = 0
var passed = 0

let resolverTests: [(String, () throws -> Void)] = [
    ("testAsciiLineMapping", testAsciiLineMapping),
    ("testMultibyteUtf8Mapping", testMultibyteUtf8Mapping),
    ("testComplexGraphemeClusters", testComplexGraphemeClusters),
    ("testBoundaryAndEdgeCases", testBoundaryAndEdgeCases),
    ("testDocumentCoordinateResolverBasics", testDocumentCoordinateResolverBasics),
    ("testDocumentCharacterRanges", testDocumentCharacterRanges),
    ("testDocumentLineUpdates", testDocumentLineUpdates),
    ("testBidirectionalRoundTripFidelity", testBidirectionalRoundTripFidelity),
    ("testLineEndingVariations", testLineEndingVariations),
    ("testEmptyDocumentResolver", testEmptyDocumentResolver),
    ("testCharacterRangeEofInsertion", testCharacterRangeEofInsertion),
    ("testCrlfAndCrNormalization", testCrlfAndCrNormalization)
]

for (name, test) in resolverTests {
    total += 1
    if runTest(name: name, test: test) {
        passed += 1
    }
}

print("Result: \(passed)/\(total) tests passed.")
if passed != total {
    exit(1)
}
