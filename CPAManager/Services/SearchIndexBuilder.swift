import Foundation
import SwiftData

/// Turns records into `SearchDoc`s — one place, used by the ⌘K palette and Spotlight.
enum SearchIndexBuilder {
    static func docs(
        clients: [Client], projects: [Project], tasks: [TaskItem], invoices: [Invoice],
        inbox: [InboxItem], expenses: [Expense], interactions: [Interaction]
    ) -> [SearchDoc] {
        var result: [SearchDoc] = []
        for c in clients {
            result.append(SearchDoc(
                id: DeepLink.client(c.id).identifier, kind: .client, title: c.displayName,
                subtitle: "\(c.entityType.label) · \(c.status.label)",
                keywords: [c.email, c.phone, c.company, c.tagsRaw, c.notes].joined(separator: " ")
            ))
        }
        for p in projects {
            result.append(SearchDoc(
                id: DeepLink.project(p.id).identifier, kind: .project, title: p.title,
                subtitle: "\(p.clientName) · \(p.status.label)", keywords: [p.detail, p.nextAction].joined(separator: " ")
            ))
        }
        for t in tasks where !t.isDone {
            result.append(SearchDoc(
                id: DeepLink.task(t.id).identifier, kind: .task, title: t.title,
                subtitle: t.project?.title ?? t.client?.displayName ?? "", keywords: t.notes,
                target: t.project.map { DeepLink.project($0.id).identifier } ?? t.client.map { DeepLink.client($0.id).identifier }
            ))
        }
        for i in invoices {
            result.append(SearchDoc(
                id: DeepLink.invoice(i.id).identifier, kind: .invoice,
                title: "\(i.displayNumber) · \(i.client?.displayName ?? "No client")",
                subtitle: "\(i.status.label) · \(Format.currency(i.total))", keywords: i.notes
            ))
        }
        for item in inbox {
            result.append(SearchDoc(id: "inbox:\(item.id.uuidString)", kind: .inbox, title: item.text, subtitle: item.source.label))
        }
        for e in expenses {
            result.append(SearchDoc(
                id: "expense:\(e.id.uuidString)", kind: .expense,
                title: e.vendor.isEmpty ? e.category.label : e.vendor,
                subtitle: "\(Format.currency(e.amount)) · \(e.category.label)", keywords: e.note
            ))
        }
        for n in interactions {
            guard let client = n.client else { continue }
            result.append(SearchDoc(
                id: "note:\(n.id.uuidString)", kind: .note, title: String(n.summary.prefix(90)),
                subtitle: "\(client.displayName) · \(n.kind.label)", target: DeepLink.client(client.id).identifier
            ))
        }
        return result
    }

    @MainActor
    static func docs(context: ModelContext) -> [SearchDoc] {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let inbox = all(InboxItem.self).filter { !$0.isProcessed }
        return docs(
            clients: all(Client.self), projects: all(Project.self), tasks: all(TaskItem.self),
            invoices: all(Invoice.self), inbox: inbox, expenses: all(Expense.self), interactions: all(Interaction.self)
        )
    }
}
