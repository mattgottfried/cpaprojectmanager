import Foundation

// Pure logic for document requests, recurring invoices, and expenses. Unit-tested.

// MARK: - Document requests

enum DocumentChecklist {
    /// Sensible starting checklists by client type. They're suggestions to tick or edit —
    /// every engagement differs.
    static func suggestions(for entity: EntityType) -> [String] {
        switch entity {
        case .individual1040:
            return [
                "W-2s", "1099s (interest, dividends, NEC/MISC, retirement)", "1098 mortgage interest",
                "Property tax statements", "Charitable donation receipts",
                "Health coverage forms (1095-A/B/C)", "Prior-year return", "IDs / SSNs for new dependents",
            ]
        case .sCorp1120S, .partnership1065, .cCorp1120:
            return [
                "Year-end P&L and balance sheet", "Bank and credit card statements",
                "Payroll reports (941s, W-2/W-3)", "Fixed asset purchases and sales",
                "Loan and lease statements", "Owner / shareholder details for K-1s",
                "Officer compensation and distributions", "Prior-year return",
            ]
        case .trust1041:
            return [
                "Trust or estate agreement", "Brokerage and bank statements", "1099s issued to the trust",
                "Distribution records", "Expenses paid (fiduciary, legal, accounting)", "Prior-year return",
            ]
        case .nonProfit990:
            return [
                "Year-end financial statements", "Board and officer list", "Major donor and grant records",
                "Program service descriptions", "Payroll reports", "Prior-year 990",
            ]
        case .other:
            return ["Prior-year return", "Bank statements", "Anything you received tax forms for"]
        }
    }

    /// Received / total for a set of requests.
    static func progress(received: Int, total: Int) -> Double {
        total > 0 ? Double(received) / Double(total) : 0
    }

    /// The email that chases whatever is still missing.
    static func requestEmailBody(clientName: String, items: [String], dueDate: Date?, firm: String) -> String {
        let list = items.map { "  • \($0)" }.joined(separator: "\n")
        var body = "Hi \(clientName),\n\nTo keep your work moving, I still need the following:\n\n\(list)\n"
        if let dueDate {
            body += "\nCould you send these by \(dueDate.formatted(date: .long, time: .omitted))?\n"
        }
        body += "\nYou can reply to this email with photos or PDFs attached. Thank you!\n\n\(firm)"
        return body
    }
}

// MARK: - Recurring invoices

enum RecurringInvoicePlanner {
    struct Plan: Equatable {
        /// Issue dates to draft an invoice for (oldest first).
        var issueDates: [Date]
        /// Where the schedule stands afterward (always after today).
        var nextIssueDate: Date
    }

    /// Everything due up to `now`. If the app wasn't opened for a while, at most
    /// `maxCatchUp` of the most recent missed periods are drafted — older ones are
    /// skipped rather than flooding the invoice list — and the schedule still moves
    /// past today.
    static func plan(
        nextIssue: Date,
        frequency: Frequency,
        now: Date = .now,
        maxCatchUp: Int = 3,
        calendar: Calendar = .current
    ) -> Plan {
        let today = calendar.startOfDay(for: now)
        var next = calendar.startOfDay(for: nextIssue)
        var due: [Date] = []
        var guardCount = 0
        while next <= today && guardCount < 1000 {
            due.append(next)
            let advanced = frequency.nextDate(after: next, calendar: calendar)
            if advanced <= next { break }   // defensive: never loop forever
            next = advanced
            guardCount += 1
        }
        return Plan(issueDates: Array(due.suffix(max(0, maxCatchUp))), nextIssueDate: next)
    }

    static func dueDate(issue: Date, termsDays: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: max(0, termsDays), to: calendar.startOfDay(for: issue)) ?? issue
    }
}

// MARK: - Expenses

enum ExpenseMath {
    struct Row: Equatable {
        var category: ExpenseCategory
        var date: Date
        var amount: Double
        var deductiblePercent: Int
    }

    struct CategoryTotal: Equatable, Identifiable {
        var category: ExpenseCategory
        var total: Double
        var deductible: Double
        var id: String { category.rawValue }
    }

    static func deductible(amount: Double, percent: Int) -> Double {
        let clamped = min(100, max(0, percent))
        return Double(InvoiceMath.cents(amount) * clamped / 100) / 100
    }

    /// Totals per category in `range`, biggest first.
    static func totalsByCategory(_ rows: [Row], in range: Range<Date>? = nil) -> [CategoryTotal] {
        var totals: [ExpenseCategory: (total: Int, deductible: Int)] = [:]
        for row in rows {
            if let range, !range.contains(row.date) { continue }
            let cents = InvoiceMath.cents(row.amount)
            let entry = totals[row.category] ?? (0, 0)
            totals[row.category] = (
                entry.total + cents,
                entry.deductible + cents * min(100, max(0, row.deductiblePercent)) / 100
            )
        }
        return totals
            .map { CategoryTotal(category: $0.key, total: Double($0.value.total) / 100, deductible: Double($0.value.deductible) / 100) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.category.rawValue < $1.category.rawValue }
    }

    /// The date range for a calendar year.
    static func yearRange(_ year: Int, calendar: Calendar = .current) -> Range<Date>? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        return start..<end
    }
}
