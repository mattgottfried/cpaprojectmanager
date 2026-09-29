import SwiftUI
import SwiftData

/// Adaptive shell: a sidebar on iPad and Mac (regular width), tabs on iPhone. Also
/// bootstraps the app (seed, recurrence, snapshot, notifications).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    var body: some View {
        Group {
            if sizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .task { bootstrap() }
        .onOpenURL { router.handle(url: $0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    // MARK: iPhone — tabs

    private enum CompactTab: Hashable { case today, inbox, clients, work, more }

    private var tabBinding: Binding<CompactTab> {
        Binding(
            get: {
                switch router.section {
                case .today:   return .today
                case .inbox:   return .inbox
                case .clients: return .clients
                case .work:    return .work
                default:       return .more
                }
            },
            set: { tab in
                switch tab {
                case .today:   router.go(to: .today)
                case .inbox:   router.go(to: .inbox)
                case .clients: router.go(to: .clients)
                case .work:    router.go(to: .work)
                case .more:    router.go(to: .settings)
                }
            }
        )
    }

    private var tabLayout: some View {
        TabView(selection: tabBinding) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(CompactTab.today)

            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .badge(inbox.count)
                .tag(CompactTab.inbox)

            ClientsListView()
                .tabItem { Label("Clients", systemImage: "person.2.fill") }
                .tag(CompactTab.clients)

            WorkListView()
                .tabItem { Label("Work", systemImage: "checklist") }
                .tag(CompactTab.work)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(CompactTab.more)
        }
    }

    // MARK: iPad / Mac — sidebar

    private var sidebarSelection: Binding<AppSection?> {
        Binding(
            get: { router.section },
            set: { if let section = $0 { router.section = section } }
        )
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    ForEach(AppSection.daily) { section in
                        sidebarRow(section)
                    }
                }
                Section("Practice") {
                    ForEach(AppSection.practice) { section in
                        sidebarRow(section)
                    }
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .navigationTitle("CPA Manager")
        } detail: {
            detail(for: router.section)
                .id(router.section)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ section: AppSection) -> some View {
        if section == .inbox {
            Label(section.title, systemImage: section.systemImage)
                .badge(inbox.count)
                .tag(section)
        } else {
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .today:     TodayView()
        case .inbox:     InboxView()
        case .clients:   ClientsListView()
        case .work:      WorkListView()
        case .deadlines: DeadlinesView()
        case .review:    WeeklyReviewView()
        case .overview:  DashboardView()
        case .time:      NavigationStack { TimeLogView() }
        case .invoices:  NavigationStack { InvoicesListView() }
        case .reports:   NavigationStack { ReportsView() }
        case .templates: NavigationStack { TemplatesListView() }
        case .recurring: NavigationStack { RecurringListView() }
        case .settings:  NavigationStack { SettingsView() }
        }
    }

    private func bootstrap() {
        SeedData.seedIfNeeded(context: context)
        WidgetActions.applyPending(context: context, reminderHour: reminderHour)
        RecurrenceService.run(context: context)
        timer.restore(context: context)
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        Task { _ = await NotificationScheduler.requestAuthorization() }
    }

    private func refresh() {
        WidgetActions.applyPending(context: context, reminderHour: reminderHour)
        RecurrenceService.run(context: context)
        SnapshotBuilder.rebuild(context: context)
    }
}
