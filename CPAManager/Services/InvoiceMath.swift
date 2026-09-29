import Foundation

/// Pure money/aging rules for invoices. Unit-tested.
enum InvoiceMath {
    /// Money is compared in cents so 0.1 + 0.2 style float dust never leaves a
    /// phantom balance.
    static func cents(_ amount: Double) -> Int { Int((amount * 100).rounded()) }

    static func balance(total: Double, payments: [Double]) -> Double {
        let paid = payments.reduce(0) { $0 + cents($1) }
        return Double(max(0, cents(total) - paid)) / 100
    }

    static func isPaidInFull(total: Double, payments: [Double]) -> Bool {
        cents(total) > 0 && balance(total: total, payments: payments) == 0
    }

    /// Only a *sent* invoice with money still owed can be overdue (a draft hasn't
    /// been billed; a paid one owes nothing).
    static func isOverdue(status: InvoiceStatus, dueDate: Date, balance: Double, now: Date = .now, calendar: Calendar = .current) -> Bool {
        status == .sent && cents(balance) > 0 && calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }

    enum AgingBucket: String, CaseIterable, Identifiable {
        case current, days1to30, days31to60, days61to90, over90

        var id: String { rawValue }

        var label: String {
            switch self {
            case .current:    return "Current"
            case .days1to30:  return "1–30 days"
            case .days31to60: return "31–60 days"
            case .days61to90: return "61–90 days"
            case .over90:     return "90+ days"
            }
        }
    }

    static func agingBucket(dueDate: Date, now: Date = .now, calendar: Calendar = .current) -> AgingBucket {
        let due = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: now)
        let late = calendar.dateComponents([.day], from: due, to: today).day ?? 0
        switch late {
        case ..<1:     return .current
        case 1...30:   return .days1to30
        case 31...60:  return .days31to60
        case 61...90:  return .days61to90
        default:       return .over90
        }
    }

    /// How much of a QuickBooks-side payment we haven't recorded locally yet.
    /// QuickBooks reports `TotalAmt` and the remaining `Balance`; what it has collected
    /// is the difference. Returns nil when we're already caught up.
    static func unrecordedQBOPayment(qboTotal: Double, qboBalance: Double, locallyPaid: Double) -> Double? {
        let collected = cents(qboTotal) - cents(qboBalance)
        let missing = collected - cents(locallyPaid)
        return missing > 0 ? Double(missing) / 100 : nil
    }

    /// Body of a polite reminder email.
    static func reminderBody(clientName: String, number: String, balance: Double, dueDate: Date, firm: String) -> String {
        let due = dueDate.formatted(date: .long, time: .omitted)
        let amount = Format.currency(balance)
        return """
        Hi \(clientName),

        A quick reminder that invoice \(number) for \(amount) was due on \(due). \
        If you've already sent payment, thank you — please disregard this note.

        Let me know if you have any questions.

        \(firm)
        """
    }

    /// `mailto:` URL for the reminder (works on iPhone, iPad and Mac).
    static func reminderURL(to email: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}

struct QBOInvoiceBalanceResponse: Decodable {
    struct Body: Decodable {
        struct Row: Decodable {
            let Id: String?
            let Balance: Double?
            let TotalAmt: Double?
        }
        let Invoice: [Row]?
    }
    let QueryResponse: Body
}
