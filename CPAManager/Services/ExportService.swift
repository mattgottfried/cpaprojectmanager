import Foundation
import SwiftData

/// Builds CSV files (clients, invoices, payments, time, expenses, tasks, document
/// requests) from the store. Escaping/sanitizing lives in `CSVWriter`.
enum ExportService {
    enum Dataset: String, CaseIterable, Identifiable {
        case clients, invoices, payments, time, expenses, tasks, documentRequests

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clients:          return "Clients"
            case .invoices:         return "Invoices"
            case .payments:         return "Payments"
            case .time:             return "Time entries"
            case .expenses:         return "Expenses"
            case .tasks:            return "Tasks"
            case .documentRequests: return "Document requests"
            }
        }

        var systemImage: String {
            switch self {
            case .clients:          return "person.2.fill"
            case .invoices:         return "doc.text.fill"
            case .payments:         return "banknote.fill"
            case .time:             return "clock.fill"
            case .expenses:         return "creditcard.fill"
            case .tasks:            return "checklist"
            case .documentRequests: return "doc.badge.clock"
            }
        }
    }

    @MainActor
    static func csv(_ dataset: Dataset, context: ModelContext) -> String {
        switch dataset {
        case .clients:          return clients(context)
        case .invoices:         return invoices(context)
        case .payments:         return payments(context)
        case .time:             return time(context)
        case .expenses:         return expenses(context)
        case .tasks:            return tasks(context)
        case .documentRequests: return documentRequests(context)
        }
    }

    /// Writes one dataset to a temporary `.csv` and returns its URL.
    @MainActor
    static func file(_ dataset: Dataset, context: ModelContext, now: Date = .now) -> URL? {
        let name = "CPA \(dataset.title) \(CSVWriter.date(now)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // A UTF-8 BOM makes Excel open accents and symbols correctly.
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(csv(dataset, context: context).utf8)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Builders

    @MainActor
    private static func clients(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<Client>(sortBy: [SortDescriptor(\Client.name)]))) ?? []).map { c -> [String] in
            [
                c.name, c.company, c.entityType.label, c.status.label, c.email, c.phone,
                c.tags.joined(separator: "; "),
                c.leadStage.map { $0.label } ?? "",
                c.leadValue > 0 ? CSVWriter.money(c.leadValue) : "",
                CSVWriter.date(c.followUpDate), CSVWriter.date(c.lastContactedAt),
                String(c.openProjects.count), CSVWriter.date(c.createdAt), c.notes,
            ]
        }
        return CSVWriter.encode(
            headers: ["Name", "Company", "Entity type", "Status", "Email", "Phone", "Tags", "Lead stage", "Est. annual fees", "Follow-up date", "Last contact", "Open projects", "Created", "Notes"],
            rows: rows
        )
    }

    @MainActor
    private static func invoices(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<Invoice>(sortBy: [SortDescriptor(\Invoice.number)]))) ?? []).map { i -> [String] in
            [
                i.displayNumber, i.client?.displayName ?? "", CSVWriter.date(i.issueDate), CSVWriter.date(i.dueDate),
                i.status.label, CSVWriter.money(i.total), CSVWriter.money(i.amountPaid), CSVWriter.money(i.balance),
                i.isOverdue ? "Yes" : "No", i.qboId, i.notes,
            ]
        }
        return CSVWriter.encode(
            headers: ["Invoice #", "Client", "Issued", "Due", "Status", "Total", "Paid", "Balance", "Overdue", "QuickBooks ID", "Notes"],
            rows: rows
        )
    }

    @MainActor
    private static func payments(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<Payment>(sortBy: [SortDescriptor(\Payment.date)]))) ?? []).map { p -> [String] in
            [
                p.invoice?.displayNumber ?? "", p.invoice?.client?.displayName ?? "", CSVWriter.date(p.date),
                CSVWriter.money(p.amount), p.method.label, p.note,
            ]
        }
        return CSVWriter.encode(headers: ["Invoice #", "Client", "Date", "Amount", "Method", "Note"], rows: rows)
    }

    @MainActor
    private static func time(_ context: ModelContext) -> String {
        let entries = (try? context.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\TimeEntry.startedAt)]))) ?? []
        let rows = entries.filter { !$0.isRunning }.map { t -> [String] in
            [
                CSVWriter.date(t.startedAt), t.clientName, t.projectTitle,
                String(format: "%.2f", t.durationSeconds / 3600),
                t.isBillable ? "Yes" : "No", CSVWriter.money(t.hourlyRate), CSVWriter.money(t.billableAmount),
                t.isBilled ? "Billed" : (t.isUnbilled ? "Unbilled" : ""), t.notes,
            ]
        }
        return CSVWriter.encode(
            headers: ["Date", "Client", "Project", "Hours", "Billable", "Rate", "Amount", "Invoiced", "Notes"],
            rows: rows
        )
    }

    @MainActor
    private static func expenses(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\Expense.date)]))) ?? []).map { e -> [String] in
            [
                CSVWriter.date(e.date), e.vendor, e.category.label, CSVWriter.money(e.amount),
                String(e.deductiblePercent), CSVWriter.money(e.deductibleAmount),
                e.client?.displayName ?? "", e.hasReceipt ? "Yes" : "No", e.note,
            ]
        }
        return CSVWriter.encode(
            headers: ["Date", "Vendor", "Category", "Amount", "Deductible %", "Deductible amount", "Client (reimbursable)", "Receipt", "Note"],
            rows: rows
        )
    }

    @MainActor
    private static func tasks(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\TaskItem.createdAt)]))) ?? []).map { t -> [String] in
            [
                t.title, CSVWriter.date(t.dueDate), t.isDone ? "Yes" : "No", CSVWriter.date(t.completedAt),
                t.client?.displayName ?? t.project?.client?.displayName ?? "", t.project?.title ?? "",
                t.repeatRule == .none ? "" : t.repeatRule.label, t.notes,
            ]
        }
        return CSVWriter.encode(
            headers: ["Task", "Due", "Done", "Completed", "Client", "Project", "Repeats", "Notes"],
            rows: rows
        )
    }

    @MainActor
    private static func documentRequests(_ context: ModelContext) -> String {
        let rows = ((try? context.fetch(FetchDescriptor<DocumentRequest>(sortBy: [SortDescriptor(\DocumentRequest.requestedAt)]))) ?? []).map { r -> [String] in
            [
                r.client?.displayName ?? "", r.title, CSVWriter.date(r.requestedAt), CSVWriter.date(r.dueDate),
                r.isReceived ? CSVWriter.date(r.receivedAt) : "Outstanding",
            ]
        }
        return CSVWriter.encode(headers: ["Client", "Document", "Requested", "Needed by", "Received"], rows: rows)
    }
}
