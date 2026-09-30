import Foundation

// Pure logic for the money side: what finished work was never billed, turning a finished
// job into an invoice, wording of payment reminders, and per-client profitability.
// No SwiftData, no SwiftUI. Unit-tested. Money is compared in integer cents.

// MARK: - Unbilled work

struct UnbilledJobInput: Equatable {
    var id: UUID
    var title: String
    var clientName: String
    var isComplete: Bool
    var completedAt: Date?
    /// "" = not decided yet; otherwise see `BillingState`.
    var billingState: String
    var invoiceID: UUID?
    var unbilledAmountCents: Int
    var unbilledHours: Double
    /// Some of this job's time already went out on an invoice.
    var hasBilledTime: Bool
}

/// How a finished job was settled, when it wasn't by an invoice made from the job itself.
enum BillingState: String, CaseIterable, Identifiable {
    case invoiced, notBillable, billedElsewhere
    var id: String { rawValue }

    var label: String {
        switch self {
        case .invoiced:        return "Invoiced"
        case .notBillable:     return "Not billable"
        case .billedElsewhere: return "Billed elsewhere"
        }
    }
}

enum UnbilledReason: Equatable {
    /// Billable time is still waiting to go on an invoice.
    case unbilledTime
    /// Finished with nothing invoiced at all.
    case noInvoice
}

struct UnbilledJob: Equatable, Identifiable {
    var id: UUID
    var title: String
    var clientName: String
    var completedAt: Date?
    var reason: UnbilledReason
    var amountCents: Int
    var hours: Double
}

enum UnbilledWork {
    /// Older jobs are assumed settled, so a first run doesn't list years of history.
    static let lookbackDays = 366

    static func find(_ jobs: [UnbilledJobInput], now: Date = .now, calendar: Calendar = .current) -> [UnbilledJob] {
        let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) ?? .distantPast
        var result: [UnbilledJob] = []
        for job in jobs {
            guard job.isComplete, job.billingState.isEmpty, job.invoiceID == nil else { continue }
            if let done = job.completedAt, done < cutoff { continue }
            let reason: UnbilledReason
            if job.unbilledAmountCents > 0 {
                reason = .unbilledTime
            } else if !job.hasBilledTime {
                reason = .noInvoice
            } else {
                continue
            }
            result.append(UnbilledJob(id: job.id, title: job.title, clientName: job.clientName, completedAt: job.completedAt,
                                      reason: reason, amountCents: job.unbilledAmountCents, hours: job.unbilledHours))
        }
        return result.sorted { a, b in
            if a.amountCents != b.amountCents { return a.amountCents > b.amountCents }
            return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast)
        }
    }

    static func totalCents(_ jobs: [UnbilledJob]) -> Int { jobs.reduce(0) { $0 + $1.amountCents } }
}

// MARK: - Bill a finished job

struct BillLine: Equatable {
    var detail: String
    var quantity: Double
    var rate: Double
    var timeEntryID: UUID? = nil

    var amountCents: Int { Int((quantity * rate * 100).rounded()) }
}

struct BillEntryInput: Equatable {
    var id: UUID
    var label: String
    var hours: Double
    var rate: Double
}

struct BillFeeInput: Equatable {
    var name: String
    var unitPrice: Double
    var quantity: Double
}

enum BillFromJob {
    /// One line per chosen time entry (hours × its rate), then one per chosen fee-schedule
    /// item (quantity × price). Zero-quantity fees are dropped.
    static func lines(entries: [BillEntryInput], fees: [BillFeeInput]) -> [BillLine] {
        let time = entries.map {
            BillLine(detail: $0.label, quantity: (($0.hours * 100).rounded()) / 100, rate: $0.rate, timeEntryID: $0.id)
        }
        let fixed = fees.filter { $0.quantity > 0 }.map {
            BillLine(detail: $0.name, quantity: $0.quantity, rate: $0.unitPrice)
        }
        return time + fixed
    }

    static func totalCents(_ lines: [BillLine]) -> Int { lines.reduce(0) { $0 + $1.amountCents } }

    /// Next invoice number: one past the highest existing, starting at 1001.
    static func nextNumber(existing: [Int]) -> Int { (existing.max() ?? 1000) + 1 }
}

// MARK: - Payment reminders

enum ReminderTone: Equatable {
    case friendly, firm, final
}

enum InvoiceReminder {
    static func daysLate(dueDate: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let due = calendar.startOfDay(for: dueDate)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: due, to: today).day ?? 0)
    }

    /// Gentle at first, plainer as it drags on.
    static func tone(daysLate: Int) -> ReminderTone {
        switch daysLate {
        case ..<15:  return .friendly
        case 15..<45: return .firm
        default:     return .final
        }
    }

    static func subject(number: String, tone: ReminderTone) -> String {
        switch tone {
        case .friendly: return "Reminder: invoice \(number)"
        case .firm:     return "Past due: invoice \(number)"
        case .final:    return "Final notice: invoice \(number)"
        }
    }

    static func body(clientName: String, number: String, balance: Double, dueDate: Date, firm: String,
                     tone: ReminderTone, daysLate: Int) -> String {
        let due = dueDate.formatted(date: .long, time: .omitted)
        let amount = Format.currency(balance)
        let signoff = firm.isEmpty ? "Thank you" : "Thank you,\n\(firm)"
        switch tone {
        case .friendly:
            return """
            Hi \(clientName),

            A quick reminder that invoice \(number) for \(amount) was due on \(due). \
            If you've already sent payment, thank you — please disregard this note.

            Let me know if you have any questions.

            \(signoff)
            """
        case .firm:
            return """
            Hi \(clientName),

            Invoice \(number) for \(amount) was due on \(due) and is now \(daysLate) days past due. \
            Please arrange payment this week, or let me know if there's an issue with the invoice.

            \(signoff)
            """
        case .final:
            return """
            Hi \(clientName),

            This is a final reminder that invoice \(number) for \(amount), due \(due), is \(daysLate) days past due. \
            Please send payment right away or contact me today so we can settle it. \
            I may need to pause further work until the balance is cleared.

            \(signoff)
            """
        }
    }

    /// What gets logged on the client's timeline when a reminder is sent.
    static func logSummary(number: String) -> String { "Payment reminder sent — \(number)" }

    /// When this invoice was last reminded, from the client's logged interaction summaries.
    static func lastReminder(number: String, in interactions: [(summary: String, date: Date)]) -> Date? {
        interactions
            .filter { $0.summary == logSummary(number: number) }
            .map { $0.date }
            .max()
    }
}

// MARK: - Profitability

struct ProfitInput: Equatable {
    var clientID: UUID
    var clientName: String
    /// Sent and paid invoices issued in the period, in cents.
    var revenueCents: Int
    /// All time logged in the period, billable or not.
    var hours: Double
    /// The rate this client is normally billed at (client override or firm default).
    var standardRate: Double
}

struct ProfitRow: Equatable, Identifiable {
    var id: UUID
    var clientName: String
    var revenue: Double
    var hours: Double
    /// Revenue ÷ hours; nil when no time was logged.
    var effectiveRate: Double?
    var standardRate: Double
    /// Effective rate is under the standard rate.
    var isBelowStandard: Bool
}

enum Profitability {
    /// Lowest effective rate first (the clients to re-price), no-time clients last.
    static func rows(_ inputs: [ProfitInput]) -> [ProfitRow] {
        inputs
            .filter { $0.revenueCents > 0 || $0.hours > 0 }
            .map { input in
                let revenue = Double(input.revenueCents) / 100
                let rate: Double? = input.hours > 0 ? revenue / input.hours : nil
                let below = rate.map { input.standardRate > 0 && $0 < input.standardRate } ?? false
                return ProfitRow(id: input.clientID, clientName: input.clientName, revenue: revenue, hours: input.hours,
                                 effectiveRate: rate, standardRate: input.standardRate, isBelowStandard: below)
            }
            .sorted { a, b in
                switch (a.effectiveRate, b.effectiveRate) {
                case let (x?, y?): return x != y ? x < y : a.clientName < b.clientName
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):   return a.clientName < b.clientName
                }
            }
    }

    /// Invoiced ÷ hours across clients that have logged time (revenue with no time logged
    /// would inflate the rate).
    static func overallRate(_ rows: [ProfitRow]) -> Double? {
        let timed = rows.filter { $0.hours > 0 }
        let hours = timed.reduce(0) { $0 + $1.hours }
        guard hours > 0 else { return nil }
        return timed.reduce(0) { $0 + $1.revenue } / hours
    }
}
