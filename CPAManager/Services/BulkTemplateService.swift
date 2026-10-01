import Foundation
import SwiftData

/// Store-facing: applies a template to several jobs, skipping tasks a job already has open.
enum BulkTemplateService {
    struct Result: Equatable {
        var jobs = 0
        var tasks = 0
        var skippedJobs = 0
        var message: String { BulkTemplate.summary(jobs: jobs, tasks: tasks, skippedJobs: skippedJobs) }
    }

    @discardableResult
    static func apply(_ template: WorkflowTemplate, to projects: [Project], startDate: Date = .now, context: ModelContext) -> Result {
        var result = Result()
        for project in projects {
            let skip = BulkTemplate.skipSet(openTaskTitles: project.taskList.filter { !$0.isDone }.map(\.title))
            let added = WorkflowEngine.applyTemplate(template, to: project, startDate: startDate, skipTitles: skip, into: context)
            if added > 0 { result.jobs += 1; result.tasks += added } else { result.skippedJobs += 1 }
        }
        if result.tasks > 0 {
            try? context.save()
            SnapshotBuilder.rebuild(context: context)
            NotificationScheduler.rescheduleAll(context: context)
        }
        return result
    }
}
