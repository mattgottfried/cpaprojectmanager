import Foundation
import SwiftData

/// A unit of work / engagement for a client, e.g. "Smith 2025 Form 1040".
@Model
final class Project {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var statusRaw: String = ProjectStatus.notStarted.rawValue
    var serviceTypeRaw: String = ServiceType.taxReturn.rawValue
    var priorityRaw: String = Priority.normal.rawValue
    var startDate: Date? = nil
    var dueDate: Date? = nil
    var completedAt: Date? = nil
    var taxYear: Int = 0
    var templateName: String? = nil
    var createdAt: Date = Date.now

    var client: Client? = nil

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project)
    var timeEntries: [TimeEntry]? = []

    init(
        title: String = "",
        detail: String = "",
        status: ProjectStatus = .notStarted,
        serviceType: ServiceType = .taxReturn,
        priority: Priority = .normal,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        taxYear: Int? = nil,
        client: Client? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.statusRaw = status.rawValue
        self.serviceTypeRaw = serviceType.rawValue
        self.priorityRaw = priority.rawValue
        self.startDate = startDate
        self.dueDate = dueDate
        self.taxYear = taxYear ?? (Calendar.current.component(.year, from: .now) - 1)
        self.client = client
        self.createdAt = .now
    }

    // MARK: Typed accessors

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .notStarted }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue.isComplete ? (completedAt ?? .now) : nil
        }
    }

    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .other }
        set { serviceTypeRaw = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    // MARK: Convenience

    var taskList: [TaskItem] {
        (tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var completedTaskCount: Int { taskList.filter { $0.isDone }.count }
    var totalTaskCount: Int { taskList.count }

    var progress: Double {
        guard totalTaskCount > 0 else { return status.isComplete ? 1 : 0 }
        return Double(completedTaskCount) / Double(totalTaskCount)
    }

    var clientName: String { client?.displayName ?? "No client" }

    var isOverdue: Bool {
        guard let dueDate, !status.isComplete else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }

    /// Total tracked time across all entries, in seconds.
    var totalTrackedSeconds: Double {
        (timeEntries ?? []).reduce(0) { $0 + $1.durationSeconds }
    }
}
