import SwiftUI
import SwiftData

/// The one screen to trust: what's overdue, what's due today, what to do next.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]
    @Query private var projects: [Project]
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @State private var quickText = ""
    @State private var addedCount = 0
    @State private var toast: UndoToastState?
    @State private var showingPaste = false
    @State private var showingSetup = false
    @FocusState private var quickFocused: Bool

    /// What a plan entry points at, resolved back from a planner id.
    private struct Entry: Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let dueDate: Date?
        let task: TaskItem?
        let project: Project?
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
                project: task.project
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
        return TodayPlanner.plan(items)
    }

    var body: some View {
        NavigationStack {
            let currentPlan = plan
            let lookup = entries

            VStack(spacing: 0) {
                quickAddBar
                List {
                    if !inbox.isEmpty {
                        NavigationLink {
                            InboxView(embedded: true)
                        } label: {
                            inboxBanner
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

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
                .overlay {
                    if currentPlan.isEmpty && inbox.isEmpty { emptyState }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .toolbar {
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
            .undoToast($toast)
            .sensoryFeedback(.success, trigger: addedCount)
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            isProject: entry.task == nil
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
        } else if let project = entry.project {
            NavigationLink(value: project) { card }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
    }

    // MARK: Actions (optimistic + undoable)

    private func addQuickTask() {
        let parsed = QuickAddParser.parse(quickText)
        guard !parsed.title.isEmpty else { return }
        let task = TaskItem(title: parsed.title, dueDate: parsed.dueDate, isNextAction: parsed.dueDate == nil)
        context.insert(task)
        persist()
        quickText = ""
        addedCount += 1
    }

    private func complete(_ task: TaskItem) {
        task.toggle()
        persist()
        toast = UndoToastState(message: "Done: \(task.title)") {
            task.toggle()
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

    private func persist() {
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        SnapshotBuilder.rebuild(context: context)
    }
}
