import Foundation

// Pure rules for stage time limits and stage conditions. A stage can have a time limit (days a
// job may sit in it) and conditions (things that must be true before the job moves on). Both are
// part of the stage's setup (`StageAutomation`). No SwiftData, no SwiftUI. Unit-tested.

/// Something that must be true before a job leaves a stage automatically.
enum StageCondition: String, Codable, CaseIterable, Identifiable {
    case allTasksDone
    case documentsReceived
    case invoicePaid
    case signaturesComplete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allTasksDone:       return "Every task on the job is done"
        case .documentsReceived:  return "All requested documents are received"
        case .invoicePaid:        return "The job's invoice is paid"
        case .signaturesComplete: return "No document is waiting for a signature"
        }
    }

    /// How an unmet condition reads on the job ("Waiting for …").
    var waitingText: String {
        switch self {
        case .allTasksDone:       return "open tasks to finish"
        case .documentsReceived:  return "requested documents"
        case .invoicePaid:        return "the invoice to be paid"
        case .signaturesComplete: return "a signature"
        }
    }
}

/// What the job looks like right now, flattened so the rules don't touch the store.
struct JobFacts: Equatable {
    var openTaskCount = 0
    var openRequestCount = 0
    var hasInvoice = false
    var invoicePaid = false
    var awaitingSignatureCount = 0
}

enum StageConditions {
    static func isMet(_ condition: StageCondition, facts: JobFacts) -> Bool {
        switch condition {
        case .allTasksDone:       return facts.openTaskCount == 0
        case .documentsReceived:  return facts.openRequestCount == 0
        case .invoicePaid:        return facts.hasInvoice && facts.invoicePaid
        case .signaturesComplete: return facts.awaitingSignatureCount == 0
        }
    }

    static func unmet(_ conditions: [StageCondition], facts: JobFacts) -> [StageCondition] {
        conditions.filter { !isMet($0, facts: facts) }
    }

    static func allMet(_ conditions: [StageCondition], facts: JobFacts) -> Bool {
        unmet(conditions, facts: facts).isEmpty
    }

    /// "Waiting for the invoice to be paid and a signature", or nil when nothing is unmet.
    static func waitingSummary(_ conditions: [StageCondition], facts: JobFacts) -> String? {
        let parts = unmet(conditions, facts: facts).map(\.waitingText)
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return "Waiting for \(parts[0])" }
        return "Waiting for \(parts.dropLast().joined(separator: ", ")) and \(parts[parts.count - 1])"
    }
}

/// How long a job has been in its stage and whether that is over the stage's limit.
enum StageClock {
    /// The clock restarts whenever the job's stage differs from the one it was stamped with.
    static func needsStamp(storedKey: String, currentKey: String, enteredAt: Date?) -> Bool {
        storedKey != currentKey || enteredAt == nil
    }

    static func daysInStage(enteredAt: Date?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let enteredAt else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: enteredAt), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// Days past the limit (0 when within it or when there's no limit).
    static func daysOver(limitDays: Int?, enteredAt: Date?, now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let limit = limitDays, limit > 0, let days = daysInStage(enteredAt: enteredAt, now: now, calendar: calendar) else { return 0 }
        return max(0, days - limit)
    }

    static func isOver(limitDays: Int?, enteredAt: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        daysOver(limitDays: limitDays, enteredAt: enteredAt, now: now, calendar: calendar) > 0
    }

    /// "4 days in stage · limit 3 (1 over)" for the job screen; nil without a clock.
    static func summary(limitDays: Int?, enteredAt: Date?, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let days = daysInStage(enteredAt: enteredAt, now: now, calendar: calendar) else { return nil }
        let base = days == 1 ? "1 day in stage" : "\(days) days in stage"
        guard let limit = limitDays, limit > 0 else { return base }
        let over = max(0, days - limit)
        return over > 0 ? "\(base) · limit \(limit) (\(over) over)" : "\(base) · limit \(limit)"
    }
}

/// The sweep that moves jobs on when a stage's automove rule is satisfied *without* a task
/// being completed — for example a payment arriving.
enum StageSweep {
    /// A stage moves a job on when automove is on, there is something to wait for (tasks the
    /// stage created, or conditions), every stage task is done, and every condition is met.
    static func shouldMove(autoMove: Bool, stageTasksDone: [Bool], conditions: [StageCondition], facts: JobFacts) -> Bool {
        guard autoMove else { return false }
        guard !stageTasksDone.isEmpty || !conditions.isEmpty else { return false }
        guard stageTasksDone.allSatisfy({ $0 }) else { return false }
        return StageConditions.allMet(conditions, facts: facts)
    }
}
