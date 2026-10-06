import SwiftUI
import SwiftData
import CoreSpotlight

/// Adaptive shell: a sidebar on iPad and Mac (regular width), tabs on iPhone. Also
/// bootstraps the app (seed, recurrence, snapshot, notifications).
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Environment(AppRouter.self) private var router
    @Environment(QBOAuthService.self) private var qboAuth
    @Environment(GoogleAuthService.self) private var googleAuth
    @Environment(CloudSync.self) private var cloud
    @Environment(\.scenePhase) private var scenePhase
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage(SettingsKeys.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.lastWeeklyReview) private var lastReviewTime: Double = 0
    @State private var showingOnboarding = false
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    /// Sidebar on iPad and Mac, tabs on iPhone. macOS has no size classes, so it's
    /// always the sidebar there.
    private var usesSidebar: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        Group {
            if usesSidebar {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .task { bootstrap() }
        .task { decideOnboarding() }
        .sheet(isPresented: $showingOnboarding) { OnboardingView() }
        .sheet(item: Bindable(router).creating) { kind in
            switch kind {
            case .taxReturn: NewTaxReturnView()
            case .client:    ClientFormView()
            case .project:   ProjectFormView()
            }
        }
        .onOpenURL { router.handle(url: $0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let link = DeepLink(identifier: identifier) {
                router.open(link)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NotificationActionHandler.openRequested)) { _ in
            applyHandoffs()
        }
        .onChange(of: router.refreshTick) { _, _ in forceSync() }
        .sheet(isPresented: Binding(get: { router.showingQuickOpen }, set: { router.showingQuickOpen = $0 })) {
            QuickOpenView()
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsSync.didApplyRemote)) { _ in
            // Another device changed a setting (e.g. reminder time) — re-time reminders.
            let hour = UserDefaults.standard.object(forKey: SettingsKeys.reminderHour) as? Int ?? 8
            NotificationScheduler.rescheduleAll(context: context, morningHour: hour)
        }
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
            TodayHubView()
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
        // The big New button, on every tab, above the tab bar.
        .overlay(alignment: .bottomTrailing) {
            GlobalNewMenu(style: .floating)
                .padding(.trailing, 16)
                .padding(.bottom, 62)
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
                Section("Tools") {
                    ForEach(AppSection.tools) { section in
                        sidebarRow(section)
                    }
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                GlobalNewMenu(style: .sidebar)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .navigationTitle("CPA Manager")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
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
        case .today:     TodayHubView()
        case .inbox:     InboxView()
        case .clients:   ClientsListView()
        case .leads:     LeadsView()
        case .work:      WorkListView()
        case .deadlines: DeadlinesView()
        case .review:    WeeklyReviewView()
        case .overview:  DashboardView()
        case .time:      NavigationStack { TimeLogView() }
        case .invoices:  NavigationStack { InvoicesListView() }
        case .recurringInvoices: NavigationStack { RecurringInvoicesView() }
        case .expenses:  NavigationStack { ExpensesView() }
        case .activity:  ActivityFeedView()
        case .reports:   NavigationStack { ReportsView() }
        case .templates: NavigationStack { TemplatesListView() }
        case .recurring: NavigationStack { RecurringListView() }
        case .extensions: NavigationStack { ExtensionTrackerView() }
        case .quotes:    NavigationStack { QuotesListView() }
        case .feeSchedule: NavigationStack { FeeScheduleView() }
        case .pipelines: NavigationStack { PipelinesListView(embedded: true) }
        case .letters:   NavigationStack { TemplateLibraryView() }
        case .importData: NavigationStack { ImportView() }
        case .dataHealth: NavigationStack { DataHealthView() }
        case .syncHealth: NavigationStack { SyncHealthView() }
        case .backups:   NavigationStack { AutoBackupsView() }
        case .help:      NavigationStack { HelpView() }
        case .settings:  NavigationStack { SettingsView() }
        }
    }

    /// Only brand-new installs see the walkthrough; existing users are marked as done.
    private func decideOnboarding() {
        let invoices = (try? context.fetchCount(FetchDescriptor<Invoice>())) ?? 0
        let entries = (try? context.fetchCount(FetchDescriptor<TimeEntry>())) ?? 0
        let show = OnboardingPolicy.shouldShow(
            hasOnboarded: hasOnboarded, firmName: firmName,
            invoiceCount: invoices, timeEntryCount: entries, lastReviewTime: lastReviewTime
        )
        if show {
            showingOnboarding = true
        } else if !hasOnboarded {
            hasOnboarded = true
        }
    }

    private func bootstrap() {
        SettingsSync.shared.start()
        SpotlightIndexer.reindex(context: context)
        SeedData.seedIfNeeded(context: context)
        StatusMigration.run(context: context)
        applyHandoffs()
        RecurrenceService.run(context: context)
        RecurringInvoiceService.run(context: context)
        StageRules.reconcileAll(context: context)
        timer.restore(context: context)
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        AutoBackupService.runIfDue(context: context)
        Task { _ = await NotificationScheduler.requestAuthorization() }
        syncIntegrations()
    }

    /// Network syncs that run whenever the app comes to the foreground. Each is
    /// throttled internally, silent on failure, and does nothing unless connected.
    private func syncIntegrations() {
        Task {
            await QBOSyncService.refreshOutstanding(auth: qboAuth, context: context)
            if GoogleSync.gmailEnabled {
                await GoogleSync.syncGmail(auth: googleAuth, context: context)
            }
            if GoogleSync.pushEnabled {
                await GoogleSync.pushDueDates(auth: googleAuth, context: context)
            }
        }
    }

    /// Work handed over while the app was closed: share-sheet captures, widget taps,
    /// and "open to capture" requests from Control Center.
    private func applyHandoffs() {
        CaptureQueue.drain(context: context)
        WidgetActions.applyPending(context: context, reminderHour: reminderHour)
        switch PendingCaptures.consumeOpenRequest() {
        case "task"?:  router.go(to: .today, focus: .newTask)
        case "inbox"?: router.go(to: .inbox, focus: .inboxCapture)
        case let identifier?:
            if let link = DeepLink(identifier: identifier) { router.open(link) }
        case nil:      break
        }
    }

    /// ⌘R — sync everything now, ignoring the usual throttles.
    private func forceSync() {
        Task {
            await QBOSyncService.refreshOutstanding(auth: qboAuth, context: context, force: true)
            if GoogleSync.gmailEnabled { await GoogleSync.syncGmail(auth: googleAuth, context: context, force: true) }
            if GoogleSync.pushEnabled { await GoogleSync.pushDueDates(auth: googleAuth, context: context, force: true) }
            SpotlightIndexer.reindex(context: context, force: true)
        }
    }

    private func refresh() {
        SpotlightIndexer.reindex(context: context)
        qboAuth.refreshConnectionState()
        googleAuth.refreshConnectionState()
        syncIntegrations()
        applyHandoffs()
        RecurrenceService.run(context: context)
        RecurringInvoiceService.run(context: context)
        StageRules.reconcileAll(context: context)
        StageRules.sweep(context: context)
        StageRules.fireReminders(context: context)
        SnapshotBuilder.rebuild(context: context)
        AutoBackupService.runIfDue(context: context)
        cloud.syncNow()
    }
}
