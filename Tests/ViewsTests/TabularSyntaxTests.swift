import Foundation
import AppKit
import Views

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

func testCSVHeaderRowStyling() throws {
    let text = "name,age,city\nAlice,30,Seattle"
    let storage = NSTextStorage(string: text)
    let resolver = TabularSyntaxResolver()
    resolver.renderTabularSyntax(in: storage, isTSV: false)

    // Line 1: "name,age,city" (range 0..<13)
    // Check 'name' at index 0
    let fontAt0 = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let f0 = fontAt0 else {
        throw NSError(domain: "TabularTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing font at index 0"])
    }
    guard f0.pointSize == 13 else {
        throw NSError(domain: "TabularTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected font size 13, got \(f0.pointSize)"])
    }
    let isBold = NSFontManager.shared.traits(of: f0).contains(.boldFontMask)
    guard isBold else {
        throw NSError(domain: "TabularTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Expected bold font on header row"])
    }

    let colorAt0 = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    guard colorAt0 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected labelColor on header row, got \(String(describing: colorAt0))"])
    }

    let bgAt0 = storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
    guard bgAt0 == NSColor.quaternaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected quaternaryLabelColor background tint on header row, got \(String(describing: bgAt0))"])
    }

    // Check first delimiter comma at index 4 ("name,")
    let delimColor = storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
    guard delimColor == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected tertiaryLabelColor on delimiter, got \(String(describing: delimColor))"])
    }
}

func testCSVDataRowColumnColors() throws {
    let text = "col0,col1,col2,col3,col4,col5\nval0,val1,val2,val3,val4,val5"
    let storage = NSTextStorage(string: text)
    let resolver = TabularSyntaxResolver()
    resolver.renderTabularSyntax(in: storage, isTSV: false)

    let line2Start = 30 // "col0,col1,col2,col3,col4,col5\n" length = 30
    // Line 2: "val0,val1,val2,val3,val4,val5"

    // Check font of line 2 (regular weight)
    let fontLine2 = storage.attribute(.font, at: line2Start, effectiveRange: nil) as? NSFont
    guard let f2 = fontLine2, f2.pointSize == 13 else {
        throw NSError(domain: "TabularTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected font size 13 on data row"])
    }
    let isBoldLine2 = NSFontManager.shared.traits(of: f2).contains(.boldFontMask)
    guard !isBoldLine2 else {
        throw NSError(domain: "TabularTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Data row should not be bold"])
    }

    // val0: index 30..34 -> neutral labelColor
    let colorVal0 = storage.attribute(.foregroundColor, at: line2Start, effectiveRange: nil) as? NSColor
    guard colorVal0 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected neutral labelColor, got \(String(describing: colorVal0))"])
    }

    // delim at 34 (",") -> tertiaryLabelColor
    let delim1 = storage.attribute(.foregroundColor, at: line2Start + 4, effectiveRange: nil) as? NSColor
    guard delim1 == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected delimiter color, got \(String(describing: delim1))"])
    }

    // val1: index 35..39 -> neutral labelColor
    let colorVal1 = storage.attribute(.foregroundColor, at: line2Start + 5, effectiveRange: nil) as? NSColor
    guard colorVal1 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected col 1 neutral color, got \(String(describing: colorVal1))"])
    }

    // val2: index 40..44 -> neutral labelColor
    let colorVal2 = storage.attribute(.foregroundColor, at: line2Start + 10, effectiveRange: nil) as? NSColor
    guard colorVal2 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected col 2 neutral color, got \(String(describing: colorVal2))"])
    }

    // val3: col 3 -> neutral labelColor
    let colorVal3 = storage.attribute(.foregroundColor, at: line2Start + 15, effectiveRange: nil) as? NSColor
    guard colorVal3 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 8, userInfo: [NSLocalizedDescriptionKey: "Expected col 3 neutral color, got \(String(describing: colorVal3))"])
    }

    // val4: col 4 -> neutral labelColor
    let colorVal4 = storage.attribute(.foregroundColor, at: line2Start + 20, effectiveRange: nil) as? NSColor
    guard colorVal4 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Expected col 4 neutral color, got \(String(describing: colorVal4))"])
    }

    // val5: col 5 -> neutral labelColor
    let colorVal5 = storage.attribute(.foregroundColor, at: line2Start + 25, effectiveRange: nil) as? NSColor
    guard colorVal5 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Expected col 5 neutral color, got \(String(describing: colorVal5))"])
    }
}

func testTSVTabDelimitedExtractionAndDelimiterDimming() throws {
    let text = "id\tname\trole\n101\tBob\tEngineer"
    let storage = NSTextStorage(string: text)
    let resolver = TabularSyntaxResolver()
    resolver.renderTabularSyntax(in: storage, isTSV: true)

    // Header row: "id\tname\trole\n"
    // 'id' at index 0: bold font, labelColor, background tint
    let f0 = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let font0 = f0, NSFontManager.shared.traits(of: font0).contains(.boldFontMask) else {
        throw NSError(domain: "TabularTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Header font should be bold"])
    }
    let c0 = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    guard c0 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Header text color should be labelColor"])
    }

    // Tab delimiter at index 2 ("id\t")
    let tab0Color = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
    guard tab0Color == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tab delimiter should be tertiaryLabelColor, got \(String(describing: tab0Color))"])
    }

    // Data row: "101\tBob\tEngineer"
    let line2Start = 13 // "id\tname\trole\n".count = 13
    // "101": col 0 (neutral labelColor)
    let color101 = storage.attribute(.foregroundColor, at: line2Start, effectiveRange: nil) as? NSColor
    guard color101 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected Col 0 neutral color on TSV field 0"])
    }

    // tab at line2Start + 3
    let tab1Color = storage.attribute(.foregroundColor, at: line2Start + 3, effectiveRange: nil) as? NSColor
    guard tab1Color == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected tertiaryLabelColor on data tab delimiter"])
    }

    // "Bob": col 1 (neutral labelColor)
    let colorBob = storage.attribute(.foregroundColor, at: line2Start + 4, effectiveRange: nil) as? NSColor
    guard colorBob == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Expected Col 1 neutral color on TSV field 1"])
    }

    // "Engineer": col 2 (neutral labelColor)
    let colorEng = storage.attribute(.foregroundColor, at: line2Start + 8, effectiveRange: nil) as? NSColor
    guard colorEng == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected Col 2 neutral color on TSV field 2"])
    }
}

func testQuotedCSVFieldsWithEmbeddedCommas() throws {
    let text = "Name,Address,Notes\n\"Smith, John\",\"123 Main St, Apt 4\",\"Likes \"\"quoted\"\" words\""
    let storage = NSTextStorage(string: text)
    let resolver = TabularSyntaxResolver()
    resolver.renderTabularSyntax(in: storage, isTSV: false)

    let line2Start = 19 // "Name,Address,Notes\n".count = 19
    // Line 2: "\"Smith, John\",\"123 Main St, Apt 4\",\"Likes \"\"quoted\"\" words\""
    // Field 0: "\"Smith, John\"" (length 13, index 19..<32)
    let colorField0 = storage.attribute(.foregroundColor, at: line2Start + 1, effectiveRange: nil) as? NSColor
    guard colorField0 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected neutral color on quoted field"])
    }
    // Embedded comma at index 19 + 6 ("Smith,") must NOT be delimiter color
    let embeddedComma0 = storage.attribute(.foregroundColor, at: line2Start + 6, effectiveRange: nil) as? NSColor
    guard embeddedComma0 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Embedded comma inside quoted string must stay text color, got \(String(describing: embeddedComma0))"])
    }

    // Delimiter comma after "\"Smith, John\"" is at index 19 + 13 = 32
    let delim0 = storage.attribute(.foregroundColor, at: line2Start + 13, effectiveRange: nil) as? NSColor
    guard delim0 == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Comma delimiter after quoted field must be tertiaryLabelColor"])
    }

    // Field 1: "\"123 Main St, Apt 4\"" (length 20, index 33..<53)
    let colorField1 = storage.attribute(.foregroundColor, at: line2Start + 14, effectiveRange: nil) as? NSColor
    guard colorField1 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected neutral color on field 1"])
    }
    // Embedded comma at index 33 + 12 = 45 ("Main St,") must stay text color
    let embeddedComma1 = storage.attribute(.foregroundColor, at: line2Start + 14 + 11, effectiveRange: nil) as? NSColor
    guard embeddedComma1 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Embedded comma inside second quoted string must stay text color"])
    }

    // Delimiter comma after field 1 is at index 53
    let delim1 = storage.attribute(.foregroundColor, at: line2Start + 13 + 1 + 20, effectiveRange: nil) as? NSColor
    guard delim1 == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Comma delimiter after second quoted field must be tertiaryLabelColor"])
    }

    // Field 2: "\"Likes \"\"quoted\"\" words\"" -> neutral labelColor
    let colorField2 = storage.attribute(.foregroundColor, at: line2Start + 35, effectiveRange: nil) as? NSColor
    guard colorField2 == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Expected neutral color on field with escaped quotes"])
    }
}

func testTabularSyntaxEdgeCases() throws {
    let resolver = TabularSyntaxResolver()

    // 1. Empty storage
    let emptyStorage = NSTextStorage(string: "")
    resolver.renderTabularSyntax(in: emptyStorage, isTSV: false)
    guard emptyStorage.length == 0 else {
        throw NSError(domain: "TabularTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty storage modified"])
    }

    // 2. Storage with only newlines
    let newlinesStorage = NSTextStorage(string: "\n\n\n")
    resolver.renderTabularSyntax(in: newlinesStorage, isTSV: false)
    guard newlinesStorage.string == "\n\n\n" else {
        throw NSError(domain: "TabularTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Newline storage modified"])
    }

    // 3. Storage with empty fields: "a,,c\n1,,3"
    let emptyFieldsStorage = NSTextStorage(string: "a,,c\n1,,3")
    resolver.renderTabularSyntax(in: emptyFieldsStorage, isTSV: false)
    // Check delim at 1 (',') and 2 (',')
    let d1 = emptyFieldsStorage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
    let d2 = emptyFieldsStorage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
    guard d1 == NSColor.tertiaryLabelColor && d2 == NSColor.tertiaryLabelColor else {
        throw NSError(domain: "TabularTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Adjacent commas should both be styled as delimiters"])
    }

    // 4. Incomplete/unclosed quote while live typing: "name,notes\nAlice,\"unfinished quote"
    let unclosedStorage = NSTextStorage(string: "name,notes\nAlice,\"unfinished quote")
    resolver.renderTabularSyntax(in: unclosedStorage, isTSV: false)
    let colorUnclosed = unclosedStorage.attribute(.foregroundColor, at: 18, effectiveRange: nil) as? NSColor
    guard colorUnclosed == NSColor.labelColor else {
        throw NSError(domain: "TabularTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unfinished quoted field should be styled as neutral labelColor"])
    }

    // 5. Single line CSV
    let singleLineStorage = NSTextStorage(string: "HeaderA,HeaderB,HeaderC")
    resolver.renderTabularSyntax(in: singleLineStorage, isTSV: false)
    let fSingle = singleLineStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    guard let fontSingle = fSingle, NSFontManager.shared.traits(of: fontSingle).contains(.boldFontMask) else {
        throw NSError(domain: "TabularTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Single line should be styled as bold header"])
    }
}

print("=== TabularSyntax Unit Tests ===")
var total = 0
var passed = 0

let tests: [(String, () throws -> Void)] = [
    ("testCSVHeaderRowStyling", testCSVHeaderRowStyling),
    ("testCSVDataRowColumnColors", testCSVDataRowColumnColors),
    ("testTSVTabDelimitedExtractionAndDelimiterDimming", testTSVTabDelimitedExtractionAndDelimiterDimming),
    ("testQuotedCSVFieldsWithEmbeddedCommas", testQuotedCSVFieldsWithEmbeddedCommas),
    ("testTabularSyntaxEdgeCases", testTabularSyntaxEdgeCases)
]

for (name, test) in tests {
    total += 1
    if runTest(name: name, test: test) {
        passed += 1
    }
}

print("Result: \(passed)/\(total) tests passed.")
if passed != total {
    exit(1)
}
