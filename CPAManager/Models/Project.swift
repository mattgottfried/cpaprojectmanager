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

    /// Date documents/data were received from the client (tax-return intake).
    var receivedDate: Date? = nil
    /// Free-text "what happens next" note, shown alongside the project (e.g.
    /// "Request documents from client").
    var nextAction: String = ""
    /// Hold bookkeeping — set together by `putOnHold(reason:detail:)` and cleared
    /// by `takeOffHold()`. `holdResumeStatusRaw` remembers the stage to return to.
    var holdReasonRaw: String = ""
    var holdDetail: String = ""
    var holdResumeStatusRaw: String = ""

    /// nil = the built-in tax-return pipeline (the stage is `statusRaw`); otherwise the
    /// `Pipeline` this job lives in, with the current stage in `stageKey`.
    var pipelineID: UUID? = nil
    var stageKey: String = ""

    /// The invoice made from this job (`BillingService.createInvoice`).
    var invoiceID: UUID? = nil
    /// How a finished job was settled when not by its own invoice: "" (undecided),
    /// "invoiced", "notBillable" or "billedElsewhere" (see `BillingState`).
    var billingStateRaw: String = ""
    /// This job's folder in Google Drive; empty = none chosen.
    var driveFolderID: String = ""
    var driveFolderName: String = ""

    var client: Client? = nil

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project)
    var timeEntries: [TimeEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.project)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentRequest.project)
    var documentRequests: [DocumentRequest]? = []

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

    var holdReason: HoldReason? {
        get { HoldReason(rawValue: holdReasonRaw) }
        set { holdReasonRaw = newValue?.rawValue ?? "" }
    }

    // MARK: Workflow (advance / hold)
    //
    // Mirrors the firm's "Auto Advance" and "Put On Hold" / "Take Off Hold"
    // Shortcuts: `advance()` steps a project to the next pipeline stage and pushes
    // the due date out (see `DateMath.advancedDueDate`); holding stashes the current
    // stage so taking it off hold can resume there.

    /// The status list this work uses: tax returns have their own stages; everything else
    /// uses Not Started / In Progress / Waiting on Client / Completed.
    var statusFlow: StatusFlow { StatusFlow.flow(for: serviceType) }

    /// The status as it should read for this kind of work ("On Hold" on a return,
    /// "Waiting on Client" elsewhere).
    var statusLabel: String { statusFlow.label(statusFlow.normalize(status)) }

    /// On hold / waiting on the client. Custom-pipeline jobs express waiting as a stage
    /// instead, so they are never "on hold" in this sense.
    var isOnHold: Bool { pipelineID == nil && status == .waitingOnClient }

    /// The stage `advance()` would move to, or `nil` if already on hold/complete.
    var nextStatusPreview: ProjectStatus? {
        guard !isOnHold else { return nil }
        return statusFlow.next(after: status)
    }

    var canAdvance: Bool { nextStatusPreview != nil }

    @discardableResult
    func advance() -> Bool {
        guard let next = nextStatusPreview else { return false }
        status = next
        if status != .complete {
            dueDate = DateMath.advancedDueDate()
        }
        return true
    }

    func putOnHold(reason: HoldReason, detail: String) {
        guard pipelineID == nil, status != .waitingOnClient, status != .complete else { return }
        holdResumeStatusRaw = statusRaw
        holdReason = reason
        holdDetail = detail
        status = .waitingOnClient
    }

    func takeOffHold() {
        guard isOnHold else { return }
        status = statusFlow.normalize(ProjectStatus(rawValue: holdResumeStatusRaw) ?? .inProgress)
        dueDate = DateMath.advancedDueDate()
        holdReasonRaw = ""
        holdDetail = ""
        holdResumeStatusRaw = ""
    }

    // MARK: Convenience

    var taskList: [TaskItem] {
        (tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The task to do next on this job (see `NextStep`).
    var nextTask: TaskItem? {
        let list = taskList
        let inputs = list.map {
            NextStepTask(id: $0.id, title: $0.title, dueDate: $0.dueDate, sortIndex: $0.sortIndex,
                         isDone: $0.isDone, blockedByID: $0.blockedByID)
        }
        guard let pick = NextStep.pick(inputs) else { return nil }
        return list.first { $0.id == pick.id }
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
