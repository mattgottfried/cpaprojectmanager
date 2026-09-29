import Foundation
import SwiftData

/// Drafts invoices from `RecurringInvoice` templates. Only ever creates **drafts** —
/// nothing is sent or synced to QuickBooks without you reviewing it first.
enum RecurringInvoiceService {
    @MainActor
    @discardableResult
    static func run(context: ModelContext, now: Date = .now) -> Int {
        let templates = (try? context.fetch(FetchDescriptor<RecurringInvoice>())) ?? []
        let existing = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let calendar = Calendar.current
        var nextNumber = (existing.map(\.number).max() ?? 1000) + 1
        var created = 0

        for template in templates where template.isActive {
            guard let client = template.client else { continue }
            let plan = RecurringInvoicePlanner.plan(nextIssue: template.nextIssueDate, frequency: template.frequency, now: now)
            let marker = "Auto-drafted from “\(template.name)”"

            for issue in plan.issueDates {
                // Two devices could both notice the same due date before iCloud syncs; the
                // marker + client + day makes drafting idempotent.
                let duplicate = existing.contains {
                    $0.client?.id == client.id
                        && calendar.isDate($0.issueDate, inSameDayAs: issue)
                        && $0.notes.hasPrefix(marker)
                }
                if duplicate { continue }

                let invoice = Invoice(
                    number: nextNumber,
                    issueDate: issue,
                    dueDate: RecurringInvoicePlanner.dueDate(issue: issue, termsDays: template.termsDays),
                    status: .draft,
                    notes: template.notes.isEmpty ? marker : "\(marker)\n\(template.notes)",
                    client: client
                )
                context.insert(invoice)
                for (index, line) in template.lines.enumerated() {
                    context.insert(InvoiceLine(detail: line.detail, quantity: line.quantity, rate: line.rate, sortIndex: index, invoice: invoice))
                }
                nextNumber += 1
                created += 1
            }

            if template.nextIssueDate != plan.nextIssueDate {
                template.nextIssueDate = plan.nextIssueDate
                if !plan.issueDates.isEmpty { template.lastGeneratedAt = now }
            }
        }
        if created > 0 || !templates.isEmpty { try? context.save() }
        return created
    }
}

/// Turns computed tax deadlines into tasks on the Today/Deadlines screens.
enum TaxDeadlineService {
    /// Creates a dated task per deadline, skipping any that already exist (same client,
    /// title and day), so it's safe to run again after an extension is filed.
    @MainActor
    @discardableResult
    static func createTasks(
        for clients: [Client],
        taxYear: Int,
        includeEstimates: Bool,
        context: ModelContext
    ) -> Int {
        let calendar = Calendar.current
        let existing = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var created = 0

        for client in clients where client.status != .inactive {
            let deadlines = TaxCalendar.deadlines(
                for: client.entityType, taxYear: taxYear,
                extended: client.extensionYears.contains(taxYear),
                includeEstimates: includeEstimates
            )
            for deadline in deadlines {
                let title = "\(client.displayName): \(deadline.title)"
                let already = existing.contains {
                    $0.title == title && $0.dueDate.map { calendar.isDate($0, inSameDayAs: deadline.date) } == true
                }
                if already { continue }
                let task = TaskItem(title: title, dueDate: deadline.date)
                task.client = client
                context.insert(task)
                created += 1
            }
        }
        if created > 0 { try? context.save() }
        return created
    }
}
