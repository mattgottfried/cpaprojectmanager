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
        for (offset, templateTask) in template.taskList.enumerated() {
            let taskDue = cal.date(byAdding: .day, value: templateTask.dayOffset, to: baseDate)
            let item = TaskItem(
                title: templateTask.title,
                dueDate: taskDue,
                sortIndex: startIndex + offset,
                project: project
            )
            context.insert(item)
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
