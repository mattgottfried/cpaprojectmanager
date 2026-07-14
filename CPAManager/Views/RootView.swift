import SwiftUI
import SwiftData

/// Tab shell + app bootstrapping (seed, recurrence, snapshot, notifications).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ClientsListView()
                .tabItem { Label("Clients", systemImage: "person.2.fill") }

            WorkListView()
                .tabItem { Label("Work", systemImage: "checklist") }

            DeadlinesView()
                .tabItem { Label("Deadlines", systemImage: "calendar") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
        }
        .task { bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func bootstrap() {
        SeedData.seedIfNeeded(context: context)
        RecurrenceService.run(context: context)
        timer.restore(context: context)
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        Task { _ = await NotificationScheduler.requestAuthorization() }
    }

    private func refresh() {
        RecurrenceService.run(context: context)
        SnapshotBuilder.rebuild(context: context)
    }
}
