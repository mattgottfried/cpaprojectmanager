import SwiftUI
import SwiftData

/// The one screen to trust: what's overdue, what's due today, what to do next.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]
    @Query private var projects: [Project]
    @Query private var clients: [Client]
    @Query private var invoices: [Invoice]
    @Query private var docRequests: [DocumentRequest]
    @Query(filter: #Predicate<Invoice> { $0.statusRaw == "draft" }) private var draftInvoices: [Invoice]
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    @Environment(AppRouter.self) private var router
    @Environment(GoogleAuthService.self) private var google
    @AppStorage(SettingsKeys.googleScheduleEnabled) private var showSchedule = false
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage(SettingsKeys.quietThresholdDays) private var quietDays = 14
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.focusEnabled) private var focusEnabled = false
    @AppStorage(SettingsKeys.focusStartHour) private var focusStart = 18
    @AppStorage(SettingsKeys.focusEndHour) private var focusEnd = 22
    @AppStorage(SettingsKeys.focusWeekends) private var focusWeekends = true
    /// `timeIntervalSince1970` of the last finished weekly review; 0 = never.
    @AppStorage(SettingsKeys.lastWeeklyReview) private var lastReviewTime: Double = 0
    @State private var quickText = ""
    @State private var addedCount = 0
    @State private var toast: UndoToastState?
    @State private var showingPaste = false
    @State private var showingSetup = false
    @State private var schedule: [CalendarEvent] = []
    @State private var logClient: Client?
    @State private var paymentInvoice: Invoice?
    @FocusState private var quickFocused: Bool

    /// What a plan entry points at, resolved back from a planner id.
    private struct Entry: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let dueDate: Date?
        let task: TaskItem?
        let project: Project?
        var client: Client? = nil
        var invoice: Invoice? = nil
        var request: DocumentRequest? = nil
        var isRepeating = false

        var kind: TodayRowKind {
            if request != nil { return .document }
            if client != nil { return .client }
            if invoice != nil { return .invoice }
            return task != nil ? .task : .project
        }
    }

    private var entries: [UUID: Entry] {
        var result: [UUID: Entry] = [:]
        for task in tasks where task.project?.status.isComplete != true {
            result[task.id] = Entry(
                id: task.id,
                title: task.title,
                subtitle: task.project?.title ?? task.client?.displayName ?? "",
                dueDate: task.dueDate,
                task: task,
                project: task.project,
                isRepeating: task.repeatRule != .none
            )
        }
        for project in projects where !project.status.isComplete {
            result[project.id] = Entry(
                id: project.id,
                title: project.title,
                subtitle: project.clientName,
                dueDate: project.dueDate,
                task: nil,
                project: project
            )
        }
        for client in clients where client.status != .inactive && client.followUpDate != nil {
            result[client.id] = Entry(
                id: client.id,
                title: "Follow up with \(client.displayName)",
                subtitle: "Last contact: \(ClientActivity.lastContactLabel(client.lastContactedAt))",
                dueDate: client.followUpDate,
                task: nil,
                project: nil,
                client: client
            )
        }
        for invoice in invoices where invoice.status == .sent && invoice.balance > 0 {
            result[invoice.id] = Entry(
                id: invoice.id,
                title: "\(invoice.displayNumber) · \(Format.currency(invoice.balance))",
                subtitle: invoice.client?.displayName ?? "No client",
                dueDate: invoice.dueDate,
                task: nil,
                project: nil,
                invoice: invoice
            )
        }
        for request in docRequests where !request.isReceived && request.dueDate != nil {
            result[request.id] = Entry(
                id: request.id,
                title: "Need: \(request.title)",
                subtitle: request.client?.displayName ?? "",
                dueDate: request.dueDate,
                task: nil,
                project: nil,
                client: request.client,
                request: request
            )
        }
        return result
    }

    private var plan: TodayPlan {
        var items: [PlannerItem] = []
        for task in tasks where task.project?.status.isComplete != true {
            items.append(PlannerItem(
                id: task.id, dueDate: task.dueDate, snoozedUntil: task.snoozedUntil,
                isDone: task.isDone, isNextAction: task.isNextAction
            ))
        }
        for project in projects where !project.status.isComplete {
            items.append(PlannerItem(
                id: project.id, dueDate: project.dueDate, snoozedUntil: nil,
                isDone: false, isNextAction: false
            ))
        }
        for client in clients where client.status != .inactive && client.followUpDate != nil {
            items.append(PlannerItem(
                id: client.id, dueDate: client.followUpDate, snoozedUntil: nil,
                isDone: false, isNextAction: false
            ))
        }
        for invoice in invoices where invoice.status == .sent && invoice.balance > 0 {
            items.append(PlannerItem(
                id: invoice.id, dueDate: invoice.dueDate, snoozedUntil: nil,
                isDone: false, isNextAction: false
            ))
        }
        for request in docRequests where !request.isReceived && request.dueDate != nil {
            items.append(PlannerItem(
                id: request.id, dueDate: request.dueDate, snoozedUntil: nil,
                isDone: false, isNextAction: false
            ))
        }
        return TodayPlanner.plan(items)
    }

    /// Active clients with open work who haven't been in touch for a while and have no
    /// follow-up already scheduled.
    private var quietClients: [Client] {
        let inputs = clients.map { c in
            WeeklyReviewPlanner.QuietInput(
                id: c.id, lastContact: c.lastContactedAt, createdAt: c.createdAt,
                hasOpenWork: !c.openProjects.isEmpty, isActive: c.status == .active,
                followUpDate: c.followUpDate
            )
        }
        let byID = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        return WeeklyReviewPlanner.quietClients(inputs, thresholdDays: max(1, quietDays)).compactMap { byID[$0] }
    }

    var body: some View {
        NavigationStack {
            let currentPlan = plan
            let lookup = entries

            VStack(spacing: 0) {
                quickAddBar
                List {
                    if isOutsideFocusHours {
                        focusBanner
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    if !schedule.isEmpty {
                        Section {
                            ForEach(schedule) { event in scheduleRow(event) }
                        } header: {
                            Label("Schedule", systemImage: "calendar.day.timeline.left")
                                .font(.headline)
                                .foregroundStyle(Theme.color(.info))
                                .textCase(nil)
                        }
                    }

                    if !draftInvoices.isEmpty {
                        NavigationLink {
                            InvoicesListView()
                        } label: {
                            HStack(spacing: 12) {
                                StatusTile(systemImage: "doc.badge.plus", state: .info)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(draftInvoices.count) draft invoice\(draftInvoices.count == 1 ? "" : "s") to review")
                                        .font(.body.weight(.semibold))
                                    Text("Review and send when you're ready").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .rowCard()
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(draftInvoices.count) draft invoices to review")
                            .accessibilityHint("Opens invoices")
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if reviewDue {
                        NavigationLink {
                            WeeklyReviewView(embedded: true)
                        } label: {
                            reviewBanner
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if !inbox.isEmpty {
                        NavigationLink {
                            InboxView(embedded: true)
                        } label: {
                            inboxBanner
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    TodayOccasionsSection(clients: clients)

                    ForEach(TodaySection.allCases) { section in
                        let ids = currentPlan.ids(section)
                        if !ids.isEmpty {
                            Section {
                                ForEach(ids, id: \.self) { id in
                                    if let entry = lookup[id] { row(entry, section: section) }
                                }
                            } header: {
                                sectionHeader(section, count: ids.count)
                            }
                        }
                    }

                    let quiet = quietClients
                    if !quiet.isEmpty {
                        Section {
                            ForEach(quiet.prefix(3)) { client in
                                quietRow(client)
                            }
                        } header: {
                            HStack {
                                Label("Gone quiet", systemImage: "exclamationmark.bubble.fill")
                                    .font(.headline)
                                    .foregroundStyle(Theme.color(.caution))
                                Spacer()
                                Text("\(quiet.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            .textCase(nil)
                        }
                    }

                    if currentPlan.snoozedCount > 0 {
                        Text("\(currentPlan.snoozedCount) snoozed — they'll come back on their day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await pullToRefresh() }
                .overlay {
                    if currentPlan.isEmpty && inbox.isEmpty && schedule.isEmpty { emptyState }
                }
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Today")
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoice: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { router.showingQuickOpen = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingPaste = true } label: {
                            Label("Paste from a note or email…", systemImage: "doc.on.clipboard")
                        }
                        Button { showingSetup = true } label: {
                            Label("Set up text & email capture", systemImage: "bolt.horizontal.fill")
                        }
                    } label: {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    .accessibilityLabel("Capture options")
                }
            }
            .sheet(isPresented: $showingPaste) { PasteCaptureSheet() }
            .sheet(isPresented: $showingSetup) { CaptureSetupView() }
            .sheet(item: $logClient) { client in InteractionFormView(client: client, initialKind: .call) }
            .sheet(item: $paymentInvoice) { invoice in
                RecordPaymentSheet(invoice: invoice) { payment in
                    persist()
                    toast = UndoToastState(message: "Recorded \(Format.currency(payment.amount))", systemImage: "banknote") {
                        invoice.payments?.removeAll { $0.id == payment.id }
                        context.delete(payment)
                        invoice.refreshPaidStatus()
                        persist()
                    }
                }
            }
            .undoToast($toast)
            .sensoryFeedback(.success, trigger: addedCount)
            .onAppear(perform: consumeFocusRequest)
            .onAppear { if case .task(_)? = router.pendingLink { router.pendingLink = nil } }
            .onChange(of: router.pendingFocus) { _, _ in consumeFocusRequest() }
            .task(id: "\(showSchedule)-\(google.isConnected)") { await loadSchedule() }
        }
    }

    // MARK: Google

    private func loadSchedule() async {
        guard showSchedule, google.isConnected else {
            schedule = []
            return
        }
        schedule = await GoogleSync.todaysSchedule(auth: google)
    }

    /// Pull-to-refresh re-checks Gmail and the calendar right now.
    private func pullToRefresh() async {
        if google.isConnected {
            if GoogleSync.gmailEnabled { await GoogleSync.syncGmail(auth: google, context: context, force: true) }
            await loadSchedule()
        }
    }

    @ViewBuilder
    private func scheduleRow(_ event: CalendarEvent) -> some View {
        let card = HStack(spacing: 12) {
            StatusTile(systemImage: event.isAllDay ? "sun.max" : "clock", state: .info, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.body.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    Text(timeLabel(event)).font(.caption.weight(.semibold)).foregroundStyle(Theme.info)
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.title)
        .accessibilityValue(timeLabel(event) + (event.location.isEmpty ? "" : ", \(event.location)"))

        Group {
            if let link = event.link {
                Link(destination: link) { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func timeLabel(_ event: CalendarEvent) -> String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        guard let end = event.end else { return start }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Focus hours & weekly review

    private var focusHours: FocusHours {
        FocusHours(isEnabled: focusEnabled, startHour: focusStart, endHour: focusEnd, weekendsAllDay: focusWeekends)
    }

    private var isOutsideFocusHours: Bool {
        focusEnabled && !focusHours.isWithin(.now)
    }

    private var reviewDue: Bool {
        let last: Date? = lastReviewTime > 0 ? Date(timeIntervalSince1970: lastReviewTime) : nil
        return WeeklyReviewPlanner.isDue(lastReview: last)
    }

    private var focusBanner: some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: "moon.stars.fill", state: .neutral)
            VStack(alignment: .leading, spacing: 2) {
                Text("Off hours").font(.body.weight(.semibold))
                Text("Your side-business window opens at \(FocusHours.hourLabel(focusStart)). Nothing here needs you right now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .rowCard()
        .accessibilityElement(children: .combine)
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: "checkmark.seal.fill", state: .caution)
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly review due").font(.body.weight(.semibold))
                Text("10 minutes to clear the inbox and reset your week")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly review due")
        .accessibilityHint("Opens the weekly review")
    }

    private func consumeFocusRequest() {
        guard router.pendingFocus == .newTask else { return }
        router.pendingFocus = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            quickFocused = true
        }
    }

    // MARK: Pieces

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
            TextField("Add a task — “call Smith Friday”", text: $quickText)
                .focused($quickFocused)
                .submitLabel(.done)
                .onSubmit(addQuickTask)
                .accessibilityLabel("Add a task")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var inboxBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.info)
                .frame(width: 44, height: 44)
                .background(Theme.info.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(inbox.count) to sort").font(.body.weight(.semibold))
                Text("Captured from texts, emails, and notes").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Inbox, \(inbox.count) to sort")
        .accessibilityHint("Opens your inbox")
    }

    private func sectionHeader(_ section: TodaySection, count: Int) -> some View {
        HStack {
            Label(section.title, systemImage: section.systemImage)
                .font(.headline)
                .foregroundStyle(Theme.color(section.color))
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("You're clear", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Nothing overdue or due today. Add a task above, or capture from a note.")
        } actions: {
            Button("Set up text & email capture") { showingSetup = true }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func row(_ entry: Entry, section: TodaySection) -> some View {
        let card = TodayRowCard(
            title: entry.title,
            subtitle: entry.subtitle,
            dueDate: entry.dueDate,
            section: section,
            kind: entry.kind,
            isRepeating: entry.isRepeating
        )
        if let task = entry.task {
            card
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { complete(task) } label: { Label("Done", systemImage: "checkmark") }
                        .tint(Theme.good)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { snooze(task, .tomorrow) } label: { Label("Tomorrow", systemImage: "sunrise.fill") }
                        .tint(Theme.info)
                }
                .contextMenu { taskMenu(task) }
        } else if let request = entry.request {
            Group {
                if let client = request.client {
                    NavigationLink(value: client) { card }.buttonStyle(.plain)
                } else {
                    card
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { receive(request) } label: { Label("Received", systemImage: "checkmark") }
                    .tint(Theme.good)
            }
        } else if let client = entry.client {
            NavigationLink(value: client) { card }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { finishFollowUp(client) } label: { Label("Contacted", systemImage: "checkmark") }
                        .tint(Theme.good)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button { setFollowUp(client, .inAWeek) } label: { Label("Next week", systemImage: "calendar.badge.clock") }
                        .tint(Theme.info)
                }
                .contextMenu { clientMenu(client) }
        } else if let invoice = entry.invoice {
            NavigationLink(value: invoice) { card }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { markPaid(invoice) } label: { Label("Paid", systemImage: "banknote") }
                        .tint(Theme.good)
                }
                .contextMenu { invoiceMenu(invoice) }
        } else if let project = entry.project {
            NavigationLink(value: project) { card }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    private func quietRow(_ client: Client) -> some View {
        NavigationLink(value: client) {
            HStack(spacing: 12) {
                Avatar(initials: client.initials, size: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    Label(ClientActivity.lastContactLabel(client.lastContactedAt), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Theme.caution)
                }
                Spacer(minLength: 0)
            }
            .rowCard()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(client.displayName) has gone quiet")
            .accessibilityValue("Last contact \(ClientActivity.lastContactLabel(client.lastContactedAt))")
            .accessibilityHint("Opens the client")
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { logClient = client } label: { Label("Log contact", systemImage: "phone.fill") }
                .tint(Theme.good)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { setFollowUp(client, .inTwoWeeks) } label: { Label("Remind in 2 weeks", systemImage: "bell") }
                .tint(Theme.info)
        }
        .contextMenu { clientMenu(client) }
    }

    @ViewBuilder
    private func clientMenu(_ client: Client) -> some View {
        Button { logClient = client } label: { Label("Log contact…", systemImage: "phone.fill") }
        if client.followUpDate != nil {
            Button { finishFollowUp(client) } label: { Label("Mark contacted", systemImage: "checkmark.circle") }
        }
        Menu {
            ForEach(FollowUpPreset.allCases) { preset in
                Button { setFollowUp(client, preset) } label: { Label(preset.label, systemImage: "calendar") }
            }
            if client.followUpDate != nil {
                Button(role: .destructive) { clearFollowUp(client) } label: { Label("Clear reminder", systemImage: "xmark") }
            }
        } label: { Label("Remind me to follow up", systemImage: "bell") }
    }

    @ViewBuilder
    private func invoiceMenu(_ invoice: Invoice) -> some View {
        Button { markPaid(invoice) } label: { Label("Mark paid in full", systemImage: "banknote") }
        Button { paymentInvoice = invoice } label: { Label("Record payment…", systemImage: "plus.circle") }
        if let email = invoice.client?.email, !email.isEmpty {
            Button { remind(invoice, email: email) } label: { Label("Email a reminder", systemImage: "envelope.badge") }
        }
    }

    @ViewBuilder
    private func taskMenu(_ task: TaskItem) -> some View {
        Button { complete(task) } label: { Label("Mark done", systemImage: "checkmark.circle") }
        Menu {
            ForEach(SnoozeOption.allCases) { option in
                Button { snooze(task, option) } label: { Label(option.label, systemImage: option.systemImage) }
            }
        } label: { Label("Snooze", systemImage: "moon.zzz") }
        Menu {
            ForEach(SnoozeOption.allCases) { option in
                Button { reschedule(task, option) } label: { Label(option.label, systemImage: option.systemImage) }
            }
        } label: { Label("Reschedule", systemImage: "calendar.badge.clock") }
        Menu {
            ForEach(RepeatRule.allCases) { rule in
                Button { setRepeat(task, rule) } label: { Label(rule.label, systemImage: rule.systemImage) }
            }
        } label: { Label("Repeat", systemImage: "arrow.triangle.2.circlepath") }
    }

    // MARK: Actions (optimistic + undoable)

    private func addQuickTask() {
        let parsed = QuickCapture.parse(quickText)
        guard !parsed.title.isEmpty else { return }
        let task = TaskItem(title: parsed.title, dueDate: parsed.dueDate, isNextAction: parsed.dueDate == nil)
        task.repeatRule = parsed.rule
        context.insert(task)
        persist()
        quickText = ""
        addedCount += 1
    }

    private func complete(_ task: TaskItem) {
        let spawned = TaskCompletion.complete(task, context: context)
        persist()
        let message = spawned == nil ? "Done: \(task.title)" : "Done — next \(Format.relativeDay(spawned?.dueDate ?? .now))"
        toast = UndoToastState(message: message) {
            TaskCompletion.undo(task, spawned: spawned, context: context)
            persist()
        }
    }

    private func setRepeat(_ task: TaskItem, _ rule: RepeatRule) {
        let previous = task.repeatRule
        task.repeatRule = rule
        if rule != .none && task.dueDate == nil {
            task.dueDate = Calendar.current.startOfDay(for: .now)
            task.isNextAction = false
        }
        persist()
        toast = UndoToastState(message: rule == .none ? "Repeat off" : rule.label, systemImage: "arrow.triangle.2.circlepath") {
            task.repeatRule = previous
            persist()
        }
    }

    private func snooze(_ task: TaskItem, _ option: SnoozeOption) {
        let previous = task.snoozedUntil
        task.snoozedUntil = TodayPlanner.snoozeDate(option)
        persist()
        toast = UndoToastState(message: "Snoozed to \(option.label.lowercased())", systemImage: "moon.zzz.fill") {
            task.snoozedUntil = previous
            persist()
        }
    }

    private func reschedule(_ task: TaskItem, _ option: SnoozeOption) {
        let previous = task.dueDate
        task.dueDate = TodayPlanner.snoozeDate(option)
        task.snoozedUntil = nil
        persist()
        toast = UndoToastState(message: "Moved to \(option.label.lowercased())", systemImage: "calendar") {
            task.dueDate = previous
            persist()
        }
    }

    private func receive(_ request: DocumentRequest) {
        request.markReceived()
        persist()
        toast = UndoToastState(message: "Received: \(request.title)", systemImage: "doc.badge.checkmark") {
            request.markOutstanding()
            persist()
        }
    }

    private func finishFollowUp(_ client: Client) {
        let previous = client.followUpDate
        let entry = Interaction(kind: .note, summary: "Followed up", client: client)
        context.insert(entry)
        client.followUpDate = nil
        persist()
        toast = UndoToastState(message: "Followed up with \(client.displayName)", systemImage: "checkmark.circle.fill") {
            context.delete(entry)
            client.followUpDate = previous
            persist()
        }
    }

    private func setFollowUp(_ client: Client, _ preset: FollowUpPreset) {
        let previous = client.followUpDate
        client.followUpDate = preset.date()
        persist()
        toast = UndoToastState(message: "Reminder set: \(preset.label.lowercased())", systemImage: "bell.fill") {
            client.followUpDate = previous
            persist()
        }
    }

    private func clearFollowUp(_ client: Client) {
        let previous = client.followUpDate
        client.followUpDate = nil
        persist()
        toast = UndoToastState(message: "Reminder cleared", systemImage: "bell.slash") {
            client.followUpDate = previous
            persist()
        }
    }

    private func markPaid(_ invoice: Invoice) {
        let payment = invoice.recordPayment(invoice.balance, method: .other, note: "Marked paid")
        persist()
        toast = UndoToastState(message: "\(invoice.displayNumber) paid", systemImage: "banknote") {
            invoice.payments?.removeAll { $0.id == payment.id }
            context.delete(payment)
            invoice.refreshPaidStatus()
            persist()
        }
    }

    private func remind(_ invoice: Invoice, email: String) {
        let body = InvoiceMath.reminderBody(
            clientName: invoice.client?.displayName ?? "there",
            number: invoice.displayNumber,
            balance: invoice.balance,
            dueDate: invoice.dueDate,
            firm: firmName
        )
        if let url = InvoiceMath.reminderURL(to: email, subject: "Reminder: invoice \(invoice.displayNumber)", body: body) {
            openURL(url)
        }
    }

    private func persist() {
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        SnapshotBuilder.rebuild(context: context)
    }
}
