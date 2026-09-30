import Foundation
import SwiftData

/// Reads the store into plain values for `DataHealth`, and applies its safe fixes.
enum DataHealthService {
    static func scan(context: ModelContext, now: Date = .now) -> DataHealthReport {
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let templates = (try? context.fetch(FetchDescriptor<WorkflowTemplate>())) ?? []
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let running = (try? context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.endedAt == nil }))) ?? []

        return DataHealth.report(
            invoices: invoices.map { HealthInvoice(id: $0.id, number: $0.number, createdAt: $0.createdAt, isSyncedToQuickBooks: !$0.qboId.isEmpty) },
            templates: templates.map {
                HealthTemplate(
                    id: $0.id, name: $0.name, taskTitles: $0.taskList.map(\.title), createdAt: $0.createdAt,
                    isReferenced: !($0.recurringEngagements ?? []).isEmpty
                )
            },
            clients: clients.map { HealthClient(id: $0.id, name: $0.displayName, email: $0.email) },
            runningTimers: running.map { HealthTimer(id: $0.id, startedAt: $0.startedAt) },
            now: now
        )
    }

    static func renumberInvoices(_ report: DataHealthReport, context: ModelContext) {
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let byID = Dictionary(invoices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for change in report.renumbers { byID[change.id]?.number = change.newNumber }
        try? context.save()
    }

    static func removeDuplicateTemplates(_ report: DataHealthReport, context: ModelContext) {
        let ids = Set(report.duplicateTemplateIDs)
        let templates = (try? context.fetch(FetchDescriptor<WorkflowTemplate>())) ?? []
        for template in templates where ids.contains(template.id) { context.delete(template) }
        try? context.save()
    }

    /// Stops timers that have been "running" for an implausible time, ending them at
    /// `capHours` after they started so they don't bill days of time.
    static func stopStaleTimers(_ report: DataHealthReport, capHours: Double = 1, context: ModelContext) {
        let ids = Set(report.staleTimerIDs)
        let entries = (try? context.fetch(FetchDescriptor<TimeEntry>())) ?? []
        for entry in entries where ids.contains(entry.id) && entry.endedAt == nil {
            entry.endedAt = entry.startedAt.addingTimeInterval(capHours * 3600)
        }
        try? context.save()
    }
}
