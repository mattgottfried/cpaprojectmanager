import SwiftUI
import SwiftData

/// Decide what an inbox item becomes: a task (optionally dated / for a client), a
/// task inside a project, or nothing.
struct InboxTriageSheet: View {
    let item: InboxItem
    /// Reports an undoable outcome up to the presenter's toast.
    let onOutcome: (_ message: String, _ undo: @escaping () -> Void) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Project.title) private var projects: [Project]

    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var client: Client?
    @State private var project: Project?

    private var openProjects: [Project] { projects.filter { !$0.status.isComplete } }

    var body: some View {
        NavigationStack {
            Form {
                Section("What needs doing?") {
                    TextField("Task", text: $title, axis: .vertical)
                        .lineLimit(1...5)
                    Label(item.source.label, systemImage: item.source.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("When") {
                    Toggle("Due date", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: .date)
                    } else {
                        Text("No date — it goes in Next up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("File under") {
                    Picker("Client", selection: $client) {
                        Text("None").tag(Client?.none)
                        ForEach(clients) { c in
                            Text(c.displayName).tag(Client?.some(c))
                        }
                    }
                    Picker("Project", selection: $project) {
                        Text("None (standalone task)").tag(Project?.none)
                        ForEach(openProjects) { p in
                            Text("\(p.title) — \(p.clientName)").tag(Project?.some(p))
                        }
                    }
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Label("Add task", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let client {
                        Button {
                            logToClient(client)
                        } label: {
                            Label("Log on \(client.displayName)'s activity", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                    }

                    Button(role: .destructive) {
                        discard()
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Sort item")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        let parsed = QuickAddParser.parse(item.text)
        title = parsed.title.isEmpty ? item.text : parsed.title
        if let date = parsed.dueDate {
            hasDue = true
            due = date
        }
        client = item.client
    }

    private func save() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.text = text
        let dueDate = hasDue ? Calendar.current.startOfDay(for: due) : nil
        let task: TaskItem
        if let project {
            task = InboxService.attach(item, to: project, dueDate: dueDate, context: context)
        } else {
            task = InboxService.makeTask(from: item, dueDate: dueDate, client: client, context: context)
        }
        // `makeTask`/`attach` re-parse the text; make sure the edited title wins.
        task.title = text
        task.dueDate = dueDate
        if project == nil { task.isNextAction = dueDate == nil }
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        let label = text
        dismiss()
        onOutcome("Task added: \(label)") {
            context.delete(task)
            item.reopen()
            try? context.save()
        }
    }

    private func logToClient(_ client: Client) {
        item.text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = InboxService.log(item, to: client, context: context)
        dismiss()
        onOutcome("Logged on \(client.displayName)") {
            context.delete(entry)
            item.reopen()
            try? context.save()
        }
    }

    private func discard() {
        item.markProcessed()
        try? context.save()
        dismiss()
        onOutcome("Dismissed") {
            item.reopen()
            try? context.save()
        }
    }
}

private extension View {
    /// `.navigationBarTitleDisplayMode` is unavailable on macOS; Mac Catalyst has it,
    /// but a native macOS target will not — keep the platform check in one place.
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
