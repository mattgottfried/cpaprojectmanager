import Foundation

/// RFC 4180 CSV output with spreadsheet-injection protection. Unit-tested.
enum CSVWriter {
    /// Quotes a field when it contains a comma, quote, or line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Text that starts with `= + - @` (or a control character) would be executed as a
    /// formula by Excel/Numbers/Sheets, so it gets a leading apostrophe. Plain numbers
    /// (including negatives) are left alone.
    static func sanitize(_ text: String) -> String {
        guard let first = text.unicodeScalars.first else { return text }
        let risky = ["=", "+", "-", "@", "\t", "\r"].contains(String(first))
        guard risky else { return text }
        if Double(text) != nil { return text }
        return "'" + text
    }

    /// Full document; rows end with CRLF as the RFC specifies. Every cell is sanitized.
    static func encode(headers: [String], rows: [[String]]) -> String {
        let lines = ([headers] + rows).map { row in
            row.map { escape(sanitize($0)) }.joined(separator: ",")
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func date(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Two decimals, no currency symbol — spreadsheets sum these.
    static func money(_ amount: Double) -> String {
        String(format: "%.2f", Double(InvoiceMath.cents(amount)) / 100)
    }
}
