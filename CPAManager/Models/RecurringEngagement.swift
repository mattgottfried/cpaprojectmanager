import Foundation
import SwiftData

/// A recurring piece of work (e.g. "Monthly Bookkeeping — Acme LLC"). When its
/// next due date comes within `leadTimeDays`, `RecurrenceService` instantiates a
/// project from the linked template and advances the schedule.
@Model
final class RecurringEngagement {
    var id: UUID = UUID()
    var name: String = ""
    var frequencyRaw: String = Frequency.monthly.rawValue
    var serviceTypeRaw: String = ServiceType.bookkeeping.rawValue
    var isActive: Bool = true
    /// The next date a deliverable is due.
    var nextDueDate: Date = Date.now
    /// Create the project this many days before it is due.
    var leadTimeDays: Int = 14
    /// The due date we most recently generated a project for (dedupe guard).
    var lastGeneratedDueDate: Date? = nil
    /// If the computed next due date lands on a weekend, push it to the following
    /// business day (see `DateMath.skippingWeekend`).
    var adjustForWeekends: Bool = true
    var createdAt: Date = Date.now

    var client: Client? = nil
    var template: WorkflowTemplate? = nil

    init(
        name: String = "",
        frequency: Frequency = .monthly,
        serviceType: ServiceType = .bookkeeping,
        isActive: Bool = true,
        nextDueDate: Date = .now,
        leadTimeDays: Int = 14,
        adjustForWeekends: Bool = true,
        client: Client? = nil,
        template: WorkflowTemplate? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.frequencyRaw = frequency.rawValue
        self.serviceTypeRaw = serviceType.rawValue
        self.isActive = isActive
        self.nextDueDate = nextDueDate
        self.leadTimeDays = leadTimeDays
        self.adjustForWeekends = adjustForWeekends
        self.client = client
        self.template = template
        self.createdAt = .now
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .other }
        set { serviceTypeRaw = newValue.rawValue }
    }

    /// The date on which the next project should be created.
    var generationDate: Date {
        Calendar.current.date(byAdding: .day, value: -leadTimeDays, to: nextDueDate) ?? nextDueDate
    }
}
