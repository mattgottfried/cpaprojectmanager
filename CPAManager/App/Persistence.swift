import Foundation
import SwiftData

/// One shared `ModelContainer` for the whole process. App Intents (Siri, Shortcuts,
/// the share sheet) run inside the app process and must write to the *same* store
/// the UI reads — a second container would fight over CloudKit mirroring.
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
        SavedClientFilter.self,
    ])

    struct Bootstrap {
        let container: ModelContainer
        let syncStatus: SyncStatus
    }

    static let shared: Bootstrap = make()

    private static func make() -> Bootstrap {
        // Primary configuration syncs through the user's private iCloud (CloudKit).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let status = SyncStatus()

        do {
            let container = try ModelContainer(for: schema, configurations: cloudConfig)
            status.recordContainerResult(isCloudKitActive: true, error: nil)
            return Bootstrap(container: container, syncStatus: status)
        } catch {
            // If CloudKit isn't set up yet (e.g. no iCloud account / capability),
            // fall back to a local store so the app still runs. Recorded on
            // `status` (surfaced in Settings) instead of silently discarded, since
            // this failure otherwise looks identical to "sync just isn't working."
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                let container = try ModelContainer(for: schema, configurations: localConfig)
                status.recordContainerResult(isCloudKitActive: false, error: error)
                return Bootstrap(container: container, syncStatus: status)
            } catch {
                fatalError("Unable to create ModelContainer: \(error)")
            }
        }
    }
}
