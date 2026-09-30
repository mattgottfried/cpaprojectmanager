import SwiftUI
import SwiftData

/// Decide what an inbox item becomes: a task (optionally dated / for a client), a
/// task inside a project, or nothing.
struct InboxTriageSheet: View {
    let item: InboxItem
    /// Reports an undoable outcome up to the presenter's toast.
    let onOutcome: (_ message: String, _ undo: (() -> Void)?) -> Void

    @Environment(GoogleAuthService.self) private var google
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
    @State private var repeatRule: RepeatRule = .none

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
                    if let url = URL(string: item.link), !item.link.isEmpty {
                        Link(destination: url) {
                            Label("Open original", systemImage: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                }

                Section("When") {
                    Toggle("Due date", isOn: $hasDue.animation())
                    Picker("Repeat", selection: $repeatRule) {
                        ForEach(RepeatRule.allCases) { rule in
                            Label(rule.label, systemImage: rule.systemImage).tag(rule)
                        }
                    }
                    if hasDue || repeatRule != .none {
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

                    if !item.attachmentName.isEmpty {
                        Button {
                            fileAttachment()
                        } label: {
                            Label(
                                (client != nil || project != nil) ? "File attachment on \(project?.title ?? client?.displayName ?? "")" : "Pick a client or project to file the attachment",
                                systemImage: "paperclip"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(client == nil && project == nil)
                    }

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
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: prefill)
        }
        .macSheetFrame()
    }

    private func prefill() {
        let parsed = QuickCapture.parse(item.text)
        title = parsed.title.isEmpty ? item.text : parsed.title
        repeatRule = parsed.rule
        if let date = parsed.dueDate {
            hasDue = true
            due = date
        }
        client = item.client
    }

    private func save() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.text = text
        let dueDate = (hasDue || repeatRule != .none) ? Calendar.current.startOfDay(for: due) : nil
        let task: TaskItem
        if let project {
            task = InboxService.attach(item, to: project, dueDate: dueDate, context: context)
        } else {
            task = InboxService.makeTask(from: item, dueDate: dueDate, client: client, context: context)
        }
        // `makeTask`/`attach` re-parse the text; make sure the edited title wins.
        task.title = text
        task.dueDate = dueDate
        task.repeatRule = repeatRule
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

    private func fileAttachment() {
        guard let document = CaptureQueue.fileAttachment(of: item, client: client, project: project, context: context) else { return }
        dismiss()
        onOutcome("Filed \(document.displayName)", nil)
        // Drive is the holding place: send it on in the background (it stays in the app if Drive can't take it).
        let auth = google
        let store = context
        Task { await DriveFiling.move(document, auth: auth, context: store) }
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
