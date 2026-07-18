import SwiftUI
import SwiftData
import UIKit

@main
struct CPAManagerApp: App {
    let container: ModelContainer
    @State private var timer = TimerController()
    @State private var qboAuth = QBOAuthService()
    @State private var syncStatus: SyncStatus

    init() {
        let schema = Schema([
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
        ])

        // Primary configuration syncs through the user's private iCloud (CloudKit).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let status = SyncStatus()

        do {
            container = try ModelContainer(for: schema, configurations: cloudConfig)
            status.recordContainerResult(isCloudKitActive: true, error: nil)
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
                container = try ModelContainer(for: schema, configurations: localConfig)
                status.recordContainerResult(isCloudKitActive: false, error: error)
            } catch {
                fatalError("Unable to create ModelContainer: \(error)")
            }
        }

        _syncStatus = State(initialValue: status)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(qboAuth)
                .environment(syncStatus)
                .tint(Theme.brand)
                .task {
                    syncStatus.refreshAccountStatus()
                    syncStatus.startObservingCloudKitEvents()
                    // Lets CloudKit's remote-change notifications reach this
                    // device in the background rather than only on next launch.
                    UIApplication.shared.registerForRemoteNotifications()
                }
        }
        .modelContainer(container)
    }
}
