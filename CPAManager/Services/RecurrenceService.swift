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

                // Past its end date: stop for good (the row stays for history).
                if RecurrencePreview.hasEnded(nextDue: engagement.nextDueDate, endDate: engagement.endDate, calendar: calendar) {
                    engagement.isActive = false
                    break
                }

                let alreadyDone = engagement.lastGeneratedDueDate.map {
                    calendar.isDate($0, inSameDayAs: engagement.nextDueDate)
                } ?? false

                if !alreadyDone {
                    createProject(for: engagement, context: context)
                    engagement.lastGeneratedDueDate = engagement.nextDueDate
                    created += 1
                }
                var next = engagement.frequency.nextDate(after: engagement.nextDueDate)
                if engagement.adjustForWeekends {
                    next = DateMath.skippingWeekend(next, calendar: calendar)
                }
                engagement.nextDueDate = next
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

        project.serviceType = engagement.serviceType
        // Use the service's default custom pipeline (if any) before pinning the due date.
        PipelineEngine.applyDefault(to: project, context: context)
        project.dueDate = engagement.nextDueDate
    }

    /// Titles the generated project by the period it covers, not its due date —
    /// e.g. a bookkeeping close due 6/27 is titled "05/2026" (matches the firm's
    /// `Client - MM/YYYY` naming convention) unless the engagement has its own pattern.
    private static func title(for engagement: RecurringEngagement) -> String {
        RecurringNaming.title(
            pattern: engagement.namingPattern,
            name: engagement.name,
            clientName: engagement.client?.displayName ?? "",
            frequency: engagement.frequency,
            due: engagement.nextDueDate
        )
    }
}
