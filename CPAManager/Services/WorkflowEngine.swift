import Foundation
import SwiftData

/// Turns a `WorkflowTemplate` into real work: a `Project` plus dated `TaskItem`s.
enum WorkflowEngine {

    /// Create a brand-new project from a template.
    @discardableResult
    static func instantiate(
        template: WorkflowTemplate,
        for client: Client?,
        startDate: Date = .now,
        into context: ModelContext,
        titleOverride: String? = nil
    ) -> Project {
        let cal = Calendar.current
        let due = cal.date(byAdding: .day, value: template.defaultDurationDays, to: startDate)

        let project = Project(
            title: titleOverride ?? defaultTitle(template: template, client: client),
            detail: template.detail,
            status: .notStarted,
            serviceType: template.serviceType,
            startDate: startDate,
            dueDate: due,
            client: client
        )
        project.templateName = template.name
        context.insert(project)

        addTasks(from: template, to: project, baseDate: startDate, startIndex: 0, into: context)

        // Jobs from a pipeline-linked template start in that pipeline's chosen stage,
        // which also runs the stage's entry automation.
        if let pipelineID = template.pipelineID {
            let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
            if let pipeline = pipelines.first(where: { $0.id == pipelineID }) {
                PipelineEngine.assign(project, to: pipeline, startStageKey: template.startStageKey, context: context)
            }
        } else {
            PipelineEngine.applyDefault(to: project, context: context)
        }
        return project
    }

    /// Append a template's tasks onto an existing project (used by "Apply template").
    static func applyTemplate(
        _ template: WorkflowTemplate,
        to project: Project,
        startDate: Date? = nil,
        into context: ModelContext
    ) {
        let base = startDate ?? project.startDate ?? .now
        addTasks(from: template, to: project, baseDate: base, startIndex: project.taskList.count, into: context)
        if project.templateName == nil { project.templateName = template.name }
    }

    private static func addTasks(
        from template: WorkflowTemplate,
        to project: Project,
        baseDate: Date,
        startIndex: Int,
        into context: ModelContext
    ) {
        let cal = Calendar.current
        // Steps go one at a time: only the first is dated. Each later step waits on the one
        // before it and is dated when that one is completed (`TaskCompletion.complete`).
        let steps = template.taskList
        let delays = TaskDependencies.chainDelays(offsets: steps.map(\.dayOffset))
        var previous: TaskItem?
        for (offset, templateTask) in steps.enumerated() {
            let item = TaskItem(
                title: templateTask.title,
                dueDate: previous == nil ? cal.date(byAdding: .day, value: templateTask.dayOffset, to: baseDate) : nil,
                sortIndex: startIndex + offset,
                project: project
            )
            item.startDate = previous == nil ? baseDate : nil
            if let previous {
                item.blockedByID = previous.id
                item.dueInDaysAfterBlocker = delays[offset]
            }
            context.insert(item)
            previous = item
        }
    }

    static func defaultTitle(template: WorkflowTemplate, client: Client?) -> String {
        let name = client?.displayName ?? "New"
        if template.serviceType == .taxReturn {
            let year = Calendar.current.component(.year, from: .now) - 1
            return "\(year) - \(name) - \(template.name)"
        }
        return "\(name) - \(template.name)"
    }
}
