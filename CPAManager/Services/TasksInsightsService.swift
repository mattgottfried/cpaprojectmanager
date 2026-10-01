import Foundation
import SwiftData

// Store-facing side of the Tasks page and Insights: turn models into the plain rows the pure
// logic works on, and apply bulk edits.

enum TaskTableService {
    /// Every task as a table row: job and client resolved, stage named, subtasks counted,
    /// and "waiting" worked out from the other open tasks.
    static func rows(tasks: [TaskItem], pipelines: [Pipeline]) -> [TaskTableRow] {
        let openIDs = Set(tasks.filter { !$0.isDone }.map(\.id))
        return tasks.map { task in
            let client = task.client ?? task.project?.client
            let progress = MarkdownBlocks.checkboxProgress(task.checklist)
            return TaskTableRow(
                id: task.id, title: task.title,
                jobID: task.project?.id, jobTitle: task.project?.title ?? "",
                clientID: client?.id, clientName: client?.displayName ?? "",
                stageName: task.project.map { PipelineEngine.info(for: $0, in: pipelines).name } ?? "",
                serviceTypeRaw: task.project?.serviceTypeRaw ?? "",
                status: task.status, priority: task.priority,
                dueDate: task.dueDate, startDate: task.startDate,
                createdAt: task.createdAt, completedAt: task.completedAt,
                isDone: task.isDone,
                isBlocked: TaskDependencies.isBlocked(blockedByID: task.blockedByID, openTaskIDs: openIDs),
                subtasksDone: progress.done, subtasksTotal: progress.total
            )
        }
    }

    /// CSV of the rows the table is showing (same escaping and formula guard as every export).
    static func csv(_ rows: [TaskTableRow]) -> String {
        CSVWriter.encode(
            headers: ["Task", "Job", "Client", "Stage", "Status", "Priority", "Due", "Start", "Created", "Completed", "Subtasks"],
            rows: rows.map { row in
                [
                    row.title, row.jobTitle, row.clientName, row.stageName, row.status.label, row.priority.label,
                    CSVWriter.date(row.dueDate), CSVWriter.date(row.startDate),
                    CSVWriter.date(row.createdAt), CSVWriter.date(row.completedAt),
                    row.subtasksTotal == 0 ? "" : "\(row.subtasksDone)/\(row.subtasksTotal)",
                ]
            }
        )
    }
}

extension BulkActions {
    /// Completes each task through `TaskCompletion` (repeats and chained tasks behave normally).
    static func complete(_ tasks: [TaskItem], context: ModelContext) {
        for task in tasks where !task.isDone { TaskCompletion.complete(task, context: context) }
    }

    static func setDueDate(_ tasks: [TaskItem], to date: Date) {
        for task in tasks { task.dueDate = date }
    }

    static func setPriority(_ priority: Priority, for tasks: [TaskItem]) {
        for task in tasks { task.priority = priority }
    }

    static func setStatus(_ status: TaskStatus, for tasks: [TaskItem]) {
        for task in tasks { task.status = status }
    }
}

enum InsightsService {
    static func jobs(projects: [Project], pipelines: [Pipeline], context: ModelContext? = nil, now: Date = .now) -> [InsightsJob] {
        projects.map { project in
            let info = PipelineEngine.info(for: project, in: pipelines)
            var latest = project.createdAt
            for task in project.tasks ?? [] {
                latest = max(latest, task.createdAt)
                if let done = task.completedAt { latest = max(latest, done) }
            }
            for entry in project.timeEntries ?? [] { latest = max(latest, entry.startedAt) }
            for document in project.documents ?? [] { latest = max(latest, document.createdAt) }
            let status = project.status
            var over = 0
            if let context, !status.isComplete {
                let limit = StageRules.timeLimit(for: project, pipelines: pipelines, context: context)
                over = StageClock.daysOver(limitDays: limit, enteredAt: project.stageEnteredAt, now: now)
            }
            return InsightsJob(
                id: project.id, title: project.title, clientName: project.clientName,
                serviceTypeRaw: project.serviceTypeRaw, stageName: info.name, stageOrder: stageOrder(project, pipelines: pipelines),
                isComplete: status.isComplete,
                isInProgress: ![.notStarted, .waitingOnClient, .complete].contains(status),
                dueDate: project.dueDate, lastActivity: latest, stageDaysOver: over
            )
        }
    }

    private static func stageOrder(_ project: Project, pipelines: [Pipeline]) -> Int {
        if let custom = PipelineEngine.pipeline(for: project, in: pipelines) {
            return custom.stages.firstIndex { $0.id == project.stageKey } ?? 0
        }
        let key = project.statusFlow.normalize(project.status).rawValue
        return PipelineDefinition.builtIn(for: project.serviceType).stages.firstIndex { $0.id == key } ?? 0
    }

    struct MoneyTime: Equatable {
        var unbilledCents = 0
        var outstandingCents = 0
        var overdueCents = 0
        var weekSeconds = 0.0
        var monthSeconds = 0.0
        var monthBillableCents = 0
    }

    static func moneyTime(projects: [Project], invoices: [Invoice], timeEntries: [TimeEntry],
                          now: Date = .now, calendar: Calendar = .current) -> MoneyTime {
        var result = MoneyTime()
        result.unbilledCents = BillingService.unbilledInputs(projects).reduce(0) { $0 + $1.unbilledAmountCents }
        let sent = invoices.filter { $0.status == .sent }
        result.outstandingCents = sent.reduce(0) { $0 + InvoiceMath.cents($1.balance) }
        result.overdueCents = sent.filter(\.isOverdue).reduce(0) { $0 + InvoiceMath.cents($1.balance) }

        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        for entry in timeEntries where !entry.isRunning {
            if let week, week.contains(entry.startedAt) { result.weekSeconds += entry.durationSeconds }
            if let month, month.contains(entry.startedAt) {
                result.monthSeconds += entry.durationSeconds
                result.monthBillableCents += InvoiceMath.cents(entry.billableAmount)
            }
        }
        return result
    }
}
