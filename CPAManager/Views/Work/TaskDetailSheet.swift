import SwiftUI
import SwiftData

/// Edit a task's details: notes, due date, subtasks (checklist), what it's waiting on,
/// and which other task must finish first.
struct TaskDetailSheet: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTasks: [TaskItem]

    @State private var newItem = ""
    @State private var editingText = false

    private var openTasks: [TaskItem] { allTasks.filter { !$0.isDone } }

    /// Other open tasks in the same project (or loose tasks for the same client) that can
    /// be a blocker without creating a loop.
    private var blockerChoices: [TaskItem] {
        let siblings = openTasks.filter { other in
            if let project = task.project { return other.project?.id == project.id }
            return other.project == nil
        }
        var map: [UUID: UUID] = [:]
        for t in allTasks { if let b = t.blockedByID { map[t.id] = b } }
        let allowed = Set(TaskDependencies.candidateBlockers(taskID: task.id, openTaskIDs: siblings.map(\.id), blockedBy: map))
        return siblings.filter { allowed.contains($0.id) }.sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $task.title)
                    TextField("Notes", text: $task.notes, axis: .vertical).lineLimit(1...5)
                    Toggle("Due date", isOn: hasDue)
                    if task.dueDate != nil {
                        DatePicker("Due", selection: dueBinding, displayedComponents: .date)
                    }
                }

                Section {
                    if !task.checklist.isEmpty {
                        MarkdownNotesView(text: $task.checklist)
                    }
                    HStack {
                        TextField("Add a subtask", text: $newItem).onSubmit(addItem)
                        Button(action: addItem) { Image(systemName: "plus.circle.fill") }
                            .buttonStyle(.borderless)
                            .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityLabel("Add subtask")
                    }
                    DisclosureGroup("Edit as text", isExpanded: $editingText) {
                        TextEditor(text: $task.checklist).frame(minHeight: 110).font(.callout)
                    }
                } header: {
                    HStack {
                        Text("Subtasks")
                        if let summary = TaskChecklist.summary(task.checklist) {
                            Spacer()
                            Text(summary)
                        }
                    }
                }

                Section {
                    TextField("Waiting on… (e.g. client's W-2)", text: $task.waitingOn)
                    Picker("Can't start until", selection: blockerBinding) {
                        Text("Nothing").tag(UUID?.none)
                        ForEach(blockerChoices) { Text($0.title).tag(Optional($0.id)) }
                    }
                } header: {
                    Text("Waiting")
                } footer: {
                    Text("A task that can't start yet stays off Today until the one it waits on is done.")
                }
            }
            .navigationTitle("Task")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { finish() } }
            }
        }
    }

    private var hasDue: Binding<Bool> {
        Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (task.dueDate ?? .now) : nil })
    }
    private var dueBinding: Binding<Date> {
        Binding(get: { task.dueDate ?? .now }, set: { task.dueDate = $0 })
    }
    private var blockerBinding: Binding<UUID?> {
        Binding(get: { task.blockedByID }, set: { task.blockedByID = $0 })
    }

    private func addItem() {
        task.checklist = TaskChecklist.adding(newItem, to: task.checklist)
        newItem = ""
    }

    private func finish() {
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        dismiss()
    }
}
