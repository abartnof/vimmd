import Foundation

public enum DiagnosticSeverity: Equatable {
    case warning
    case notice
}

public struct DocumentDiagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let message: String
    public let line: Int?

    public init(severity: DiagnosticSeverity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}

/// Pure (AppKit-free) detector for high-severity file malformations.
/// Deliberately conservative: only reports real structural problems.
public struct DocumentDiagnosticEngine {
    static let runawayFenceLineThreshold = 25

    public static func analyze(text: String, isTabular: Bool, isTSV: Bool, isMarkdown: Bool) -> [DocumentDiagnostic] {
        var result: [DocumentDiagnostic] = []

        if text.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 0xFFFD }) {
            result.append(DocumentDiagnostic(severity: .warning, message: "Invalid UTF-8 bytes or null characters detected", line: nil))
        }

        if isTabular {
            let delimiter: UInt8 = isTSV ? 0x09 : 0x2C
            let scan = scanRecords(text, delimiter: delimiter)
            if let quoteLine = scan.unclosedQuoteLine {
                result.append(DocumentDiagnostic(severity: .warning, message: "Unclosed quote at line \(quoteLine); rows swallowed to EOF", line: quoteLine))
            }
            if let header = scan.records.first, header.columns >= 2 {
                if let bad = scan.records.dropFirst().first(where: { $0.columns > header.columns }) {
                    result.append(DocumentDiagnostic(severity: .warning, message: "Inconsistent columns (Header: \(header.columns), Line \(bad.line): \(bad.columns))", line: bad.line))
                }
            }
            if !isTSV, let semi = semicolonNotice(text) {
                result.append(semi)
            }
        }

        if isMarkdown, let fence = unclosedFence(text) {
            result.append(fence)
        }

        // Warnings first, stable otherwise.
        return result.filter { $0.severity == .warning } + result.filter { $0.severity == .notice }
    }

    // MARK: - Tabular scanning (RFC 4180)

    private struct Record {
        let line: Int      // 1-based physical line where the record starts
        let columns: Int
    }

    private struct ScanResult {
        var records: [Record]
        var unclosedQuoteLine: Int?
    }

    private static func scanRecords(_ text: String, delimiter: UInt8) -> ScanResult {
        var bytes = Array(text.utf8)
        // A leading UTF-8 BOM is not field content (it would hide a quoted first header field).
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var records: [Record] = []
        var inQuotes = false
        var quoteStartLine = 0
        var line = 1
        var recordStartLine = 1
        var columns = 1
        var recordHasContent = false
        var fieldAtStart = true
        var i = 0
        let n = bytes.count

        func endRecord() {
            if recordHasContent || columns > 1 {
                records.append(Record(line: recordStartLine, columns: columns))
            }
            columns = 1
            recordHasContent = false
            fieldAtStart = true
        }

        while i < n {
            let b = bytes[i]
            if inQuotes {
                if b == 0x22 {
                    if i + 1 < n && bytes[i + 1] == 0x22 {
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else if b == 0x0A {
                    line += 1
                } else if b == 0x0D {
                    if i + 1 < n && bytes[i + 1] == 0x0A { i += 1 }
                    line += 1
                }
                i += 1
                continue
            }
            if b == 0x22 && fieldAtStart {
                inQuotes = true
                quoteStartLine = line
                recordHasContent = true
                fieldAtStart = false
            } else if b == delimiter {
                columns += 1
                recordHasContent = true
                fieldAtStart = true
            } else if b == 0x0A || b == 0x0D {
                if b == 0x0D && i + 1 < n && bytes[i + 1] == 0x0A { i += 1 }
                endRecord()
                line += 1
                recordStartLine = line
            } else {
                recordHasContent = true
                fieldAtStart = false
            }
            i += 1
        }
        if !inQuotes { endRecord() }
        return ScanResult(records: records, unclosedQuoteLine: inQuotes ? quoteStartLine : nil)
    }

    private static func semicolonNotice(_ text: String) -> DocumentDiagnostic? {
        let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let firstLine = body.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }).first ?? ""
        let commas = firstLine.filter { $0 == "," }.count
        let semis = firstLine.filter { $0 == ";" }.count
        guard commas == 0 && semis >= 2 else { return nil }
        return DocumentDiagnostic(severity: .notice, message: "Semicolon-delimited CSV detected; columns not parsed with commas", line: 1)
    }

    // MARK: - Markdown fences

    private static func unclosedFence(_ text: String) -> DocumentDiagnostic? {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        var effectiveCount = lines.count
        if let last = lines.last, last.isEmpty, effectiveCount > 0 { effectiveCount -= 1 }
        let firstFenceIndex = frontmatterEndIndex(lines) ?? 0
        var openLine: Int?
        var openMarker: Character = "`"
        var openLength = 0
        for (idx, raw) in lines.enumerated() where idx >= firstFenceIndex {
            let trimmed = raw.drop(while: { $0 == " " })
            guard raw.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else { continue }
            let run = trimmed.prefix(while: { $0 == first }).count
            guard run >= 3 else { continue }
            if let _ = openLine {
                let rest = trimmed.dropFirst(run)
                if first == openMarker && run >= openLength && rest.allSatisfy({ $0 == " " || $0 == "\t" }) {
                    openLine = nil
                }
            } else {
                if first == "`" && trimmed.dropFirst(run).contains("`") { continue }
                openLine = idx + 1
                openMarker = first
                openLength = run
            }
        }
        guard let start = openLine else { return nil }
        let remaining = effectiveCount - start
        guard remaining > runawayFenceLineThreshold else { return nil }
        return DocumentDiagnostic(severity: .notice, message: "Unclosed code block starting at line \(start)", line: start)
    }

    /// Index of the first line after a leading YAML frontmatter block (`---` ... `---`/`...`), if closed.
    private static func frontmatterEndIndex(_ lines: [Substring]) -> Int? {
        var first = lines.first ?? ""
        if first.hasPrefix("\u{FEFF}") { first = first.dropFirst() }
        guard first.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for idx in 1..<max(1, lines.count) {
            let t = lines[idx].trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." { return idx + 1 }
        }
        return nil
    }
}
