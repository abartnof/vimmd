#!/usr/bin/env swift
import Foundation

let outputDir = "/tmp/vimmd_edge_cases"
let fm = FileManager.default

try? fm.removeItem(atPath: outputDir)
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)

print("Generating edge-case stress test files in \(outputDir)...")

// 1. many_columns.csv (250 columns x 50 rows)
do {
    var content = ""
    let colCount = 250
    let rowCount = 50
    content += (0..<colCount).map { "Col_\($0)" }.joined(separator: ",") + "\n"
    for r in 1...rowCount {
        content += (0..<colCount).map { "R\(r)C\($0)" }.joined(separator: ",") + "\n"
    }
    let path = "\(outputDir)/many_columns.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated many_columns.csv (250 columns x 50 rows)")
}

// 2. many_rows.csv (15,000 rows x 8 columns)
do {
    var content = "ID,Name,Category,Price,Quantity,Status,Timestamp,Notes\n"
    for r in 1...15000 {
        content += "\(r),Item_\(r),Cat_\(r % 10),\(Double(r) * 1.25),\(r % 50),active,2026-10-31 12:00:00,Note for record \(r)\n"
    }
    let path = "\(outputDir)/many_rows.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated many_rows.csv (15,000 rows x 8 columns)")
}

// 3. wide_columns.csv (extremely wide text, single long word, multi-paragraph cells)
do {
    var content = "ID,Short,VeryLongWord,LongParagraph,Numeric\n"
    let longWord = String(repeating: "supercalifragilisticexpialidocious_", count: 40) // 1440 chars without space
    let paragraph = "This is a very long descriptive paragraph that contains lots of words meant to test word wrapping inside spreadsheet cells without spilling across column boundaries. " + String(repeating: "Word wrap test in vimmd. ", count: 30)
    for r in 1...30 {
        content += "\(r),ShortVal,\(longWord),\"\(paragraph)\",\(r * 100)\n"
    }
    let path = "\(outputDir)/wide_columns.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated wide_columns.csv (1,400+ char continuous words & long cells)")
}

// 4. multiline_quoted_fields.csv (embedded \n in quotes, escaped quotes, unclosed quote at EOF)
do {
    var content = "ID,Title,Description,Amount\n"
    content += "1,Item A,\"This is a field\nwith an embedded newline\nand multiple lines!\",42.50\n"
    content += "2,Item B,\"This has \"\"escaped quotes\"\" inside it and a comma, right here\",99.00\n"
    content += "3,Item C,\"Another multiline\n\nwith empty lines in between\",15.20\n"
    content += "4,Item D,\"Final unclosed quote test at EOF without closing quote"
    let path = "\(outputDir)/multiline_quoted_fields.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated multiline_quoted_fields.csv (embedded newlines & escaped quotes)")
}

// 5. ragged_irregular_columns.csv (varying column counts per line)
do {
    var content = "Col1,Col2,Col3,Col4,Col5\n"
    content += "Val1,Val2\n" // only 2 cols
    content += "A,B,C,D,E,F,G,H,I,J,K,L,M,N,O\n" // 15 cols
    content += "\n" // empty line
    content += "Single\n" // 1 col
    content += ",,,,,\n" // only delimiters
    content += "1,2,3,4,5\n" // 5 cols
    let path = "\(outputDir)/ragged_irregular_columns.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated ragged_irregular_columns.csv (ragged line lengths & empty lines)")
}

// 6. illegal_characters_and_encodings.csv (surrogate pairs, emojis, zero-width, RTL)
do {
    var content = "ID,Emoji,RTL_Arabic,ZeroWidth,Symbols,ReplacementChar\n"
    content += "1,😀🚀🔥💻🎉,مرحبا بالعالم,Zero​Width​Space,§±!@#$%^&*(),\u{FFFD}\n"
    content += "2,👨‍👩‍👧‍👦 (ZWJ Family),שלום עולם,Soft­Hyphen,«»—–…,ValidEnd\n"
    content += "3,CJK_漢字_한국어_日本語,Mixed_العربية_English,BOM_\u{FEFF}_Embedded,¢£¥€,Done\n"
    let path = "\(outputDir)/illegal_characters_and_encodings.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated illegal_characters_and_encodings.csv (multibyte UTF-8, ZWJ, RTL, symbols)")
}

// 7. illegal_markdown_formatting.md (malformed syntax tokens)
do {
    var content = """
    # Normal Header
    
    ### 
    
    ###### H6 with no space
    
    Here is an unclosed **bold with *unclosed italic and ~~unclosed strike at EOF
    
    ```swift
    func brokenFence() {
        // No closing backticks for 500 lines!
    """
    for i in 1...200 {
        content += "\n    print(\"Line \(i)\")"
    }
    content += "\n\n> > > > > > > > > > 10 levels of nested blockquotes!\n\n"
    content += "| Col 1 | Col 2\n| broken table without pipes\n||| empty pipes |||\n\n"
    content += "[Broken Link with no closing paren](https://example.com/foo\n\n"
    content += "UltraWideLine: " + String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 200) + "\n"
    
    let path = "\(outputDir)/illegal_markdown_formatting.md"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated illegal_markdown_formatting.md (malformed tokens & unclosed fences)")
}

// 8. wide_csv_115_columns.csv (synthetic reproduction of Twitter API dataset)
do {
    var content = ""
    let colNames = (0..<115).map { "field_\($0)_property_name_header" }.joined(separator: ",") + "\n"
    content += colNames
    for r in 1...100 {
        let row = (0..<115).map { col in
            if col == 10 {
                return "\"Multiline content in column 10\nsecond line of tweet\nthird line of text\""
            } else if col % 5 == 0 {
                return "\"Quoted, with comma\""
            } else {
                return "val_\(r)_\(col)"
            }
        }.joined(separator: ",") + "\n"
        content += row
    }
    let path = "\(outputDir)/wide_csv_115_columns.csv"
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print(" [✓] Generated wide_csv_115_columns.csv (115 columns x 100 rows reproduction)")
}

print("\nAll 8 edge-case samples generated in \(outputDir):")
let files = try fm.contentsOfDirectory(atPath: outputDir)
for f in files.sorted() {
    let p = "\(outputDir)/\(f)"
    let attrs = try fm.attributesOfItem(atPath: p)
    let size = attrs[.size] as? Int64 ?? 0
    print("  - \(f) (\(size) bytes)")
}
