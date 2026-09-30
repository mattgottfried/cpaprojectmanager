import Foundation
import SwiftData

/// One shared `ModelContainer` for the whole process. App Intents (Siri, Shortcuts,
/// the share sheet) run inside the app process and must write to the *same* store
/// the UI reads — a second container would see stale data.
enum Persistence {
    static let schema = Schema([
        Client.self,
        Project.self,
        TaskItem.self,
        WorkflowTemplate.self,
        TemplateTask.self,
        RecurringEngagement.self,
        TimeEntry.self,
        Document.self,
        Invoice.self,
        InvoiceLine.self,
        InboxItem.self,
        Interaction.self,
        Payment.self,
        DocumentRequest.self,
        RecurringInvoice.self,
        Expense.self,
        Pipeline.self,
        LetterTemplate.self,
        EmailTemplate.self,
        FeeItem.self,
        Quote.self,
        SavedClientFilter.self,
    ])

    struct Bootstrap {
        let container: ModelContainer
    }

    static let shared: Bootstrap = make()

    /// The store is purely local (no CloudKit mirroring). Sync between devices is done by
    /// `SyncEngine` (Cloud Firestore) on top of this store — see Services/Sync.
    private static func make() -> Bootstrap {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return Bootstrap(container: try ModelContainer(for: schema, configurations: config))
        } catch {
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }
}
