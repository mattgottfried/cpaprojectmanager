import SwiftUI
import SwiftData

@main
struct CPAManagerApp: App {
    let container: ModelContainer
    @State private var timer = TimerController()

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
        ])

        // Primary configuration syncs through the user's private iCloud (CloudKit).
        let cloudConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(for: schema, configurations: cloudConfig)
        } catch {
            // If CloudKit isn't set up yet (e.g. no iCloud account / capability),
            // fall back to a local store so the app still runs.
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                container = try ModelContainer(for: schema, configurations: localConfig)
            } catch {
                fatalError("Unable to create ModelContainer: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .tint(Theme.brand)
        }
        .modelContainer(container)
    }
}
