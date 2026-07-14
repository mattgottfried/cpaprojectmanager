import Foundation
import SwiftData

/// Generates projects from active recurring engagements when their lead-time window
/// opens, then advances each engagement's schedule. Safe to run on every launch.
enum RecurrenceService {

    @discardableResult
    static func run(context: ModelContext, now: Date = .now) -> Int {
        let descriptor = FetchDescriptor<RecurringEngagement>(
            predicate: #Predicate { $0.isActive }
        )
        guard let engagements = try? context.fetch(descriptor) else { return 0 }

        let calendar = Calendar.current
        var created = 0

        for engagement in engagements {
            // Catch up on any periods that elapsed while the app was closed, with a
            // hard cap so a stale nextDueDate can never spin forever.
            var iterations = 0
            while engagement.isActive, engagement.generationDate <= now, iterations < 24 {
                iterations += 1

                let alreadyDone = engagement.lastGeneratedDueDate.map {
                    calendar.isDate($0, inSameDayAs: engagement.nextDueDate)
                } ?? false

                if !alreadyDone {
                    createProject(for: engagement, context: context)
                    engagement.lastGeneratedDueDate = engagement.nextDueDate
                    created += 1
                }
                engagement.nextDueDate = engagement.frequency.nextDate(after: engagement.nextDueDate)
            }
        }

        if created > 0 { try? context.save() }
        return created
    }

    private static func createProject(for engagement: RecurringEngagement, context: ModelContext) {
        let start = min(engagement.generationDate, .now)
        let project: Project

        if let template = engagement.template {
            project = WorkflowEngine.instantiate(
                template: template,
                for: engagement.client,
                startDate: start,
                into: context,
                titleOverride: title(for: engagement)
            )
        } else {
            project = Project(
                title: title(for: engagement),
                serviceType: engagement.serviceType,
                startDate: start,
                dueDate: engagement.nextDueDate,
                client: engagement.client
            )
            context.insert(project)
        }

        project.dueDate = engagement.nextDueDate
        project.serviceType = engagement.serviceType
    }

    private static func title(for engagement: RecurringEngagement) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "\(engagement.name) — \(formatter.string(from: engagement.nextDueDate))"
    }
}
