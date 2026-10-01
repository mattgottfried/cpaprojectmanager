import SwiftUI
import SwiftData

/// Adds a template's tasks to several jobs at once. Tasks a job already has open are skipped, and
/// each job's new tasks are chained (only the first is dated; the rest get dated as you finish).
struct BulkTemplateSheet: View {
    var preselected: Set<UUID> = []
    var onDone: (String) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]
    @Query(sort: \Project.title) private var projects: [Project]

    @State private var templateID: UUID?
    @State private var selected: Set<UUID> = []
    @State private var search = ""
    @State private var seeded = false

    private var template: WorkflowTemplate? { templates.first { $0.id == templateID } }

    private var openJobs: [Project] {
        projects.filter { project in
            !project.status.isComplete
                && (search.isEmpty
                    || project.title.localizedCaseInsensitiveContains(search)
                    || project.clientName.localizedCaseInsensitiveContains(search))
        }
    }

    private var chosen: [Project] { projects.filter { selected.contains($0.id) } }

    /// How many tasks the chosen jobs would receive, so the button says what it will do.
    private var newTaskCount: Int {
        guard let template else { return 0 }
        let titles = template.taskList.map(\.title)
        return chosen.reduce(0) { total, project in
            total + BulkTemplate.newStepIndices(templateTitles: titles, openTaskTitles: project.taskList.filter { !$0.isDone }.map(\.title)).count
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Template", selection: $templateID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if let template {
                        Text("\(template.taskList.count) task\(template.taskList.count == 1 ? "" : "s"): \(template.taskList.prefix(3).map(\.title).joined(separator: ", "))\(template.taskList.count > 3 ? "…" : "")")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Tasks a job already has open are skipped. Each job's new tasks run in order: only the first gets a due date.")
                }

                Section {
                    TextField("Search jobs", text: $search)
                    HStack {
                        Button("Select all shown") { selected.formUnion(openJobs.map(\.id)) }
                        Spacer()
                        Button("Clear") { selected = [] }.disabled(selected.isEmpty)
                    }
                    .buttonStyle(.borderless)
                    ForEach(openJobs) { project in
                        Button {
                            if selected.contains(project.id) { selected.remove(project.id) } else { selected.insert(project.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(project.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(project.id) ? Theme.brand : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title).foregroundStyle(.primary).lineLimit(1)
                                    Text(project.clientName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Jobs (\(selected.count) selected)")
                }
            }
            .navigationTitle("Add Tasks to Jobs")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(newTaskCount > 0 ? "Add \(newTaskCount)" : "Add") { apply() }
                        .disabled(template == nil || chosen.isEmpty)
                }
            }
            .onAppear {
                guard !seeded else { return }
                seeded = true
                selected = preselected
            }
        }
        .macSheetFrame()
    }

    private func apply() {
        guard let template else { return }
        let result = BulkTemplateService.apply(template, to: chosen, context: context)
        onDone(result.message)
        dismiss()
    }
}
