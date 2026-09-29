import SwiftUI
import SwiftData

/// A guided once-a-week reset: clear the inbox, sort overdue work, glance at what's
/// next, and check in on clients you've lost touch with. Finishing it records the
/// date so Today stops nagging for another week.
struct WeeklyReviewView: View {
    /// True when pushed from another stack so it doesn't nest a second NavigationStack.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @Query private var projects: [Project]
    @Query private var clients: [Client]
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage(SettingsKeys.lastWeeklyReview) private var lastReviewTime: Double = 0
    @AppStorage(SettingsKeys.quietThresholdDays) private var quietDays = 14
    @State private var toast: UndoToastState?
    @State private var finished = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    // MARK: Data

    private var openTasks: [TaskItem] {
        tasks.filter { !$0.isDone && $0.project?.status.isComplete != true }
    }

    private var overdue: [TaskItem] {
        let today = Calendar.current.startOfDay(for: .now)
        return openTasks
            .filter { ($0.dueDate.map { Calendar.current.startOfDay(for: $0) < today }) ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var nextUp: [TaskItem] { openTasks.filter { $0.dueDate == nil && $0.isNextAction } }

    private var overdueProjects: [Project] {
        let today = Calendar.current.startOfDay(for: .now)
        return projects.filter {
            !$0.status.isComplete && (($0.dueDate.map { Calendar.current.startOfDay(for: $0) < today }) ?? false)
        }
    }

    private var upcoming: [TaskItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 8, to: today) else { return [] }
        return openTasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                let day = cal.startOfDay(for: due)
                return day >= today && day < end
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Follow-ups that are due now or within the next week, soonest first.
    private var upcomingFollowUps: [Client] {
        let cal = Calendar.current
        guard let horizon = cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: .now)) else { return [] }
        return clients
            .filter { $0.status != .inactive && ($0.followUpDate.map { $0 < horizon } ?? false) }
            .sorted { ($0.followUpDate ?? .distantFuture) < ($1.followUpDate ?? .distantFuture) }
    }

    private var quietClients: [Client] {
        let inputs = clients.map { c in
            WeeklyReviewPlanner.QuietInput(
                id: c.id, lastContact: c.lastContactedAt, createdAt: c.createdAt,
                hasOpenWork: !c.openProjects.isEmpty, isActive: c.status == .active,
                followUpDate: c.followUpDate
            )
        }
        let ids = WeeklyReviewPlanner.quietClients(inputs, thresholdDays: max(1, quietDays))
        let byID = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    // MARK: View

    private var content: some View {
        List {
            Section {
                Text("Ten minutes. Work top to bottom, then tap Finish.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            step("1. Clear the inbox", "tray.fill", .info, done: inbox.isEmpty) {
                if inbox.isEmpty {
                    doneRow("Inbox is empty")
                } else {
                    NavigationLink {
                        InboxView(embedded: true)
                    } label: {
                        Label("\(inbox.count) item\(inbox.count == 1 ? "" : "s") to sort", systemImage: "arrow.right.circle.fill")
                    }
                }
            }

            step("2. Deal with overdue", "exclamationmark.triangle.fill", .bad, done: overdue.isEmpty && overdueProjects.isEmpty) {
                if overdue.isEmpty && overdueProjects.isEmpty {
                    doneRow("Nothing overdue")
                }
                ForEach(overdueProjects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        reviewRow(title: project.title, subtitle: project.clientName, due: project.dueDate, isProject: true)
                    }
                }
                ForEach(overdue) { task in
                    reviewRow(title: task.title, subtitle: task.project?.title ?? task.client?.displayName ?? "", due: task.dueDate, isProject: false)
                        .swipeActions(edge: .leading) {
                            Button { complete(task) } label: { Label("Done", systemImage: "checkmark") }.tint(Theme.good)
                        }
                        .contextMenu { taskMenu(task) }
                }
            }

            step("3. Next up — still right?", "arrow.right.circle.fill", .info, done: nextUp.isEmpty) {
                if nextUp.isEmpty {
                    doneRow("No undated to-dos")
                }
                ForEach(nextUp) { task in
                    reviewRow(title: task.title, subtitle: task.client?.displayName ?? "", due: nil, isProject: false)
                        .swipeActions(edge: .leading) {
                            Button { complete(task) } label: { Label("Done", systemImage: "checkmark") }.tint(Theme.good)
                        }
                        .contextMenu { taskMenu(task) }
                }
            }

            step("4. Look at the week ahead", "calendar", .neutral, done: false) {
                if upcoming.isEmpty {
                    doneRow("Nothing due in the next 7 days")
                }
                ForEach(upcoming) { task in
                    reviewRow(title: task.title, subtitle: task.project?.title ?? task.client?.displayName ?? "", due: task.dueDate, isProject: false)
                        .contextMenu { taskMenu(task) }
                }
            }

            step("5. Check in with clients", "exclamationmark.bubble.fill", .caution, done: quietClients.isEmpty && upcomingFollowUps.isEmpty) {
                if quietClients.isEmpty && upcomingFollowUps.isEmpty {
                    doneRow("You're in touch with everyone who has open work")
                }
                ForEach(upcomingFollowUps) { client in
                    NavigationLink {
                        ClientDetailView(client: client)
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(initials: client.initials, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Follow up with \(client.displayName)").font(.subheadline.weight(.semibold))
                                if let due = client.followUpDate { DueDatePill(date: due) }
                            }
                        }
                    }
                }
                ForEach(quietClients) { client in
                    NavigationLink {
                        ClientDetailView(client: client)
                    } label: {
                        HStack(spacing: 12) {
                            Avatar(initials: client.initials, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.displayName).font(.subheadline.weight(.semibold))
                                Text(ClientActivity.lastContactLabel(client.lastContactedAt))
                                    .font(.caption).foregroundStyle(Theme.caution)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    finish()
                } label: {
                    Label(finished ? "Review complete" : "Finish weekly review", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(finished ? Theme.good : Theme.brand)
                .disabled(finished)
            } footer: {
                if lastReviewTime > 0 {
                    Text("Last completed \(Date(timeIntervalSince1970: lastReviewTime).formatted(date: .abbreviated, time: .omitted)).")
                }
            }
        }
        .navigationTitle("Weekly Review")
        .undoToast($toast)
        .sensoryFeedback(.success, trigger: finished)
    }

    private func step<Content: View>(
        _ title: String, _ image: String, _ state: SemanticState, done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            HStack {
                Label(title, systemImage: image)
                    .font(.headline)
                    .foregroundStyle(Theme.color(state))
                Spacer()
                if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good).accessibilityLabel("Done") }
            }
            .textCase(nil)
        }
    }

    private func doneRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func reviewRow(title: String, subtitle: String, due: Date?, isProject: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 8) {
                if !subtitle.isEmpty {
                    Label(subtitle, systemImage: isProject ? "folder.fill" : "person.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let due { DueDatePill(date: due) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func taskMenu(_ task: TaskItem) -> some View {
        Button { complete(task) } label: { Label("Mark done", systemImage: "checkmark.circle") }
        Menu {
            ForEach(SnoozeOption.allCases) { option in
                Button { reschedule(task, option) } label: { Label(option.label, systemImage: option.systemImage) }
            }
        } label: { Label("Reschedule", systemImage: "calendar.badge.clock") }
    }

    // MARK: Actions

    private func complete(_ task: TaskItem) {
        let spawned = TaskCompletion.complete(task, context: context)
        persist()
        toast = UndoToastState(message: "Done: \(task.title)") {
            TaskCompletion.undo(task, spawned: spawned, context: context)
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

    private func finish() {
        lastReviewTime = Date.now.timeIntervalSince1970
        finished = true
    }

    private func persist() {
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        SnapshotBuilder.rebuild(context: context)
    }
}
