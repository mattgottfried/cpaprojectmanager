import Foundation

// Pure logic for the client health card, the extension tracker, and year-over-year
// carryover. No SwiftData, no SwiftUI. Unit-tested.

// MARK: - Client health

struct ClientHealthInput: Equatable {
    var lastContactedAt: Date?
    var followUpDate: Date?
    var openJobCount: Int
    var openTaskCount: Int
    var overdueTaskCount: Int
    /// Sent invoices' unpaid balance, in cents.
    var balanceOwedCents: Int
    var overdueBalanceCents: Int
    /// The soonest open job or task due date that isn't in the past, with what it is.
    var nextDeadlineTitle: String?
    var nextDeadlineDate: Date?
}

struct ClientHealth: Equatable {
    enum Level: Equatable { case good, watch, atRisk }

    var level: Level
    var headline: String
    /// Short, specific reasons the level isn't "good" (empty when it is).
    var reasons: [String]
}

enum ClientHealthLogic {
    static func assess(_ input: ClientHealthInput, quietDays: Int = 14, now: Date = .now, calendar: Calendar = .current) -> ClientHealth {
        var risks: [String] = []
        var watches: [String] = []

        if input.overdueBalanceCents > 0 { risks.append("Overdue balance") }
        if input.overdueTaskCount > 0 {
            risks.append(input.overdueTaskCount == 1 ? "1 overdue task" : "\(input.overdueTaskCount) overdue tasks")
        }

        if let follow = input.followUpDate, calendar.startOfDay(for: follow) <= calendar.startOfDay(for: now) {
            watches.append("Follow-up due")
        }
        let hasOpenWork = input.openJobCount > 0 || input.openTaskCount > 0
        if hasOpenWork {
            if let days = ClientActivity.daysSince(input.lastContactedAt, now: now, calendar: calendar) {
                if days >= quietDays { watches.append("No contact in \(days) days") }
            } else {
                watches.append("Never contacted")
            }
        }
        if input.balanceOwedCents > 0 && input.overdueBalanceCents == 0 { watches.append("Balance outstanding") }

        if !risks.isEmpty {
            return ClientHealth(level: .atRisk, headline: "Needs attention", reasons: risks + watches)
        }
        if !watches.isEmpty {
            return ClientHealth(level: .watch, headline: "Keep an eye on", reasons: watches)
        }
        return ClientHealth(level: .good, headline: "On track", reasons: [])
    }
}

// MARK: - Extension tracker

struct ExtClientInput: Equatable {
    var id: UUID
    var name: String
    var entity: EntityType
    var isActive: Bool
    var extensionYears: Set<Int>
    /// The tax-year return for this client is finished (filed / complete).
    var returnIsDone: Bool
    /// Where the tax-year return stands ("In Progress"…), nil if none was started.
    var returnStageLabel: String?
}

enum ExtensionState: Equatable {
    /// No extension and the return isn't finished: decide whether to extend.
    case needsDecision
    case extended
    /// The return is finished; nothing to extend.
    case done
}

struct ExtensionRow: Equatable, Identifiable {
    var id: UUID
    var name: String
    var formLabel: String
    var state: ExtensionState
    var originalDue: Date
    var extendedDue: Date
    var returnStageLabel: String?
    /// Days from today to the original due date (negative once it has passed).
    var daysToOriginal: Int
}

enum ExtensionTracker {
    /// One row per active client with a federal form, ordered so the most urgent decision
    /// is first: undecided by original due date, then extended by extended due date, then done.
    static func rows(_ clients: [ExtClientInput], taxYear: Int, now: Date = .now, calendar: Calendar = .current) -> [ExtensionRow] {
        let today = calendar.startOfDay(for: now)
        var rows: [ExtensionRow] = []
        for client in clients where client.isActive {
            guard let form = TaxCalendar.form(for: client.entity) else { continue }
            let original = TaxCalendar.dueDate(form: form, taxYear: taxYear, extended: false, calendar: calendar)
            let extended = TaxCalendar.dueDate(form: form, taxYear: taxYear, extended: true, calendar: calendar)
            let state: ExtensionState
            if client.extensionYears.contains(taxYear) {
                state = .extended
            } else if client.returnIsDone {
                state = .done
            } else {
                state = .needsDecision
            }
            let days = calendar.dateComponents([.day], from: today, to: original).day ?? 0
            rows.append(ExtensionRow(id: client.id, name: client.name, formLabel: form.label, state: state,
                                     originalDue: original, extendedDue: extended,
                                     returnStageLabel: client.returnStageLabel, daysToOriginal: days))
        }
        func rank(_ s: ExtensionState) -> Int {
            switch s { case .needsDecision: return 0; case .extended: return 1; case .done: return 2 }
        }
        return rows.sorted { a, b in
            if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
            let da = a.state == .extended ? a.extendedDue : a.originalDue
            let db = b.state == .extended ? b.extendedDue : b.originalDue
            if da != db { return da < db }
            return a.name < b.name
        }
    }

    /// How urgent the decision is, for the row's badge.
    static func urgency(for row: ExtensionRow) -> String? {
        guard row.state == .needsDecision else { return nil }
        switch row.daysToOriginal {
        case ..<0:    return "Past the original due date"
        case 0:       return "Due today"
        case 1...30:  return "Due in \(row.daysToOriginal) days"
        default:      return nil
        }
    }

    /// The summary line logged on the client's timeline.
    static func logSummary(formLabel: String, taxYear: Int, extendedDue: Date) -> String {
        "Extension filed for \(taxYear) \(formLabel) — extended due \(extendedDue.formatted(date: .abbreviated, time: .omitted))"
    }
}

// MARK: - Year-over-year carryover

struct CarryJobInput: Equatable {
    var id: UUID
    var clientID: UUID?
    var serviceTypeRaw: String
    var taxYear: Int
}

enum Carryover {
    /// The most recent earlier job of the same service for the same client, if any.
    static func priorJob(for clientID: UUID, serviceTypeRaw: String, taxYear: Int, in jobs: [CarryJobInput]) -> CarryJobInput? {
        jobs
            .filter { $0.clientID == clientID && $0.serviceTypeRaw == serviceTypeRaw && $0.taxYear < taxYear }
            .max { $0.taxYear < $1.taxYear }
    }

    /// Task titles from last year's job that the template doesn't already create — the
    /// one-off steps worth repeating. Compared case-insensitively; years are bumped
    /// ("2024 estimate" → "2025 estimate").
    static func extraTasks(prior: [String], templateTitles: [String], priorYear: Int, newYear: Int) -> [String] {
        let known = Set(templateTitles.map { normalized($0) })
        var seen = known
        var result: [String] = []
        for title in prior {
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized(clean)
            guard !clean.isEmpty, seen.insert(key).inserted else { continue }
            result.append(clean.replacingOccurrences(of: String(priorYear), with: String(newYear)))
        }
        return result
    }

    /// Last year's fee: the invoice made from the job if there is one, else the invoices
    /// its time went out on. `totals` maps invoice id → total in cents.
    static func priorFeeCents(invoiceID: UUID?, timeInvoiceIDs: [UUID], totals: [UUID: Int]) -> Int? {
        if let invoiceID, let total = totals[invoiceID] { return total }
        let unique = Set(timeInvoiceIDs)
        let cents = unique.compactMap { totals[$0] }
        return cents.isEmpty ? nil : cents.reduce(0, +)
    }

    private static func normalized(_ title: String) -> String {
        title.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
