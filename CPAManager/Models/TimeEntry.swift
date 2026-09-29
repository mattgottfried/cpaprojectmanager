import Foundation
import SwiftData

/// A tracked block of (usually billable) time. A running entry has `endedAt == nil`.
/// Client/project names are denormalized so the log and Live Activity stay readable.
@Model
final class TimeEntry {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date? = nil
    var notes: String = ""
    var isBillable: Bool = true
    var hourlyRate: Double = 0
    var projectTitle: String = ""
    var clientName: String = ""
    var createdAt: Date = Date.now
    /// Set once this entry has been added to an invoice's line items.
    var invoiceID: UUID? = nil

    var project: Project? = nil

    init(
        startedAt: Date = .now,
        endedAt: Date? = nil,
        notes: String = "",
        isBillable: Bool = true,
        hourlyRate: Double = 0,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.isBillable = isBillable
        self.hourlyRate = hourlyRate
        self.project = project
        self.projectTitle = project?.title ?? ""
        self.clientName = project?.client?.displayName ?? ""
        self.createdAt = .now
    }

    var isRunning: Bool { endedAt == nil }
    var isBilled: Bool { invoiceID != nil }
    var isUnbilled: Bool { !isRunning && isBillable && invoiceID == nil }

    /// Elapsed seconds — live if running, otherwise the fixed span.
    var durationSeconds: Double {
        let end = endedAt ?? .now
        return max(0, end.timeIntervalSince(startedAt))
    }

    /// Hours as billed: rounded up to the user's billing increment, if one is set.
    func billedHours(incrementMinutes: Int = TimeRounding.currentIncrement) -> Double {
        TimeRounding.hours(seconds: durationSeconds, incrementMinutes: incrementMinutes)
    }

    var billableAmount: Double {
        guard isBillable else { return 0 }
        return billedHours() * hourlyRate
    }
}
