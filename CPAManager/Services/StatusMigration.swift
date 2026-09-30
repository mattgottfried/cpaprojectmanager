import Foundation
import SwiftData

/// One-time (idempotent) cleanup after the status lists were split: projects still holding
/// a status their flow no longer offers (Awaiting Docs, In Review, or a tax-only status on
/// non-tax work) are moved to the nearest one. Safe to run on every launch.
enum StatusMigration {
    @discardableResult
    static func run(context: ModelContext) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var changed = 0
        for project in projects {
            // Custom-pipeline jobs derive their status from a stage kind, so they use the
            // general list; built-in jobs use the flow for their service type.
            let flow: StatusFlow = project.pipelineID == nil ? StatusFlow.flow(for: project.serviceType) : .general
            let current = ProjectStatus(rawValue: project.statusRaw) ?? .notStarted
            let target = flow.normalize(current)
            if target != current {
                project.status = target
                changed += 1
            }
            if let resume = ProjectStatus(rawValue: project.holdResumeStatusRaw) {
                let resumeTarget = flow.normalize(resume)
                if resumeTarget != resume {
                    project.holdResumeStatusRaw = resumeTarget.rawValue
                    changed += 1
                }
            }
        }
        if changed > 0 { try? context.save() }
        return changed
    }
}
