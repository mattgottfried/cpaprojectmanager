import Foundation

// Pure logic for fee schedules, quotes and per-client billing rates.

enum QuoteStatus: String, CaseIterable, Identifiable, Codable {
    case draft, sent, accepted, declined

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft:    return "Draft"
        case .sent:     return "Sent"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }

    var state: SemanticState {
        switch self {
        case .draft:    return .neutral
        case .sent:     return .info
        case .accepted: return .good
        case .declined: return .bad
        }
    }
}

struct QuoteLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var detail: String
    var quantity: Double = 1
    var rate: Double = 0

    var amount: Double { Double(QuoteMath.lineCents(self)) / 100 }
}

enum QuoteMath {
    /// One line in integer cents (quantity may be fractional, e.g. 2.5 hours).
    static func lineCents(_ line: QuoteLine) -> Int {
        Int((line.quantity * line.rate * 100).rounded())
    }

    static func totalCents(_ lines: [QuoteLine]) -> Int {
        lines.reduce(0) { $0 + lineCents($1) }
    }

    static func total(_ lines: [QuoteLine]) -> Double { Double(totalCents(lines)) / 100 }

    /// Next quote number: one past the highest existing, starting at 1001.
    static func nextNumber(existing: [Int]) -> Int { (existing.max() ?? 1000) + 1 }

    static func displayNumber(_ number: Int) -> String { "Q-\(number)" }

    /// Lines with a blank description are dropped (they're empty editor rows).
    static func cleaned(_ lines: [QuoteLine]) -> [QuoteLine] {
        lines.filter { !$0.detail.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func isExpired(validUntil: Date?, status: QuoteStatus, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let validUntil, status == .sent else { return false }
        return calendar.startOfDay(for: validUntil) < calendar.startOfDay(for: now)
    }
}

enum RateResolver {
    /// The hourly rate to bill: the client's own rate when set, else the firm default.
    static func rate(clientOverride: Double, defaultRate: Double) -> Double {
        clientOverride > 0 ? clientOverride : defaultRate
    }
}

enum QuoteText {
    /// Plain text of a quote, rendered to PDF by `LetterPDF` (with a signature block so
    /// the client can accept it).
    static func body(
        number: Int,
        clientName: String,
        firmName: String,
        date: Date,
        validUntil: Date?,
        lines: [QuoteLine],
        notes: String,
        formatDate: (Date) -> String,
        formatMoney: (Double) -> String
    ) -> String {
        var out: [String] = []
        out.append(formatDate(date))
        out.append("")
        out.append("Quote \(QuoteMath.displayNumber(number))")
        if !clientName.isEmpty { out.append("Prepared for \(clientName)") }
        if !firmName.isEmpty { out.append("Prepared by \(firmName)") }
        out.append("")
        for line in lines {
            let qty = line.quantity == 1 ? "" : " (\(trimmed(line.quantity)) × \(formatMoney(line.rate)))"
            out.append("• \(line.detail)\(qty) — \(formatMoney(line.amount))")
        }
        out.append("")
        out.append("Total: \(formatMoney(QuoteMath.total(lines)))")
        if let validUntil { out.append("Valid until \(formatDate(validUntil)).") }
        let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            out.append("")
            out.append(extra)
        }
        return out.joined(separator: "\n")
    }

    private static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
