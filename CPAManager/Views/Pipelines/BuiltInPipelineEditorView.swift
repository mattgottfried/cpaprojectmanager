import SwiftUI
import SwiftData

/// The task list a stage creates when a job enters it: an optional job due-date reset, then
/// the tasks. Shared by custom pipelines and the built-in ones.
struct StageAutomationEditor: View {
    @Binding var automation: StageAutomation

    var body: some View {
        Toggle("Automove: go to the next stage when all these tasks are done", isOn: $automation.autoMove)
        Toggle("Time limit for this stage", isOn: Binding(
            get: { automation.timeLimitDays != nil },
            set: { automation.timeLimitDays = $0 ? 7 : nil }
        ))
        if let limit = automation.timeLimitDays {
            Stepper("Over the limit after \(limit) day\(limit == 1 ? "" : "s")", value: Binding(
                get: { limit },
                set: { automation.timeLimitDays = $0 }
            ), in: 1...365)
        }
        DisclosureGroup("Move on only when… (\(automation.conditions.count))") {
            ForEach(StageCondition.allCases) { condition in
                Toggle(condition.label, isOn: Binding(
                    get: { automation.conditions.contains(condition) },
                    set: { on in
                        if on, !automation.conditions.contains(condition) { automation.conditions.append(condition) }
                        if !on { automation.conditions.removeAll { $0 == condition } }
                    }
                ))
            }
            if !automation.conditions.isEmpty && !automation.autoMove {
                Text("These apply when Automove is on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Toggle("Reset job due date on entry", isOn: Binding(
            get: { automation.setDueInDays != nil },
            set: { automation.setDueInDays = $0 ? 14 : nil }
        ))
        if let days = automation.setDueInDays {
            Stepper("Due in \(days) days", value: Binding(
                get: { days },
                set: { automation.setDueInDays = $0 }
            ), in: 0...365)
        }
        ForEach($automation.tasks) { $task in
            VStack(alignment: .leading, spacing: 4) {
                TextField("Task to create", text: $task.title)
                Stepper("Due \(task.dueInDays) days after it's ready", value: $task.dueInDays, in: 0...365)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDelete { automation.tasks.remove(atOffsets: $0) }
        .onMove { automation.tasks.move(fromOffsets: $0, toOffset: $1) }
        Button {
            automation.tasks.append(StageTask(title: "", dueInDays: 1))
        } label: {
            Label("Add task", systemImage: "plus.circle")
        }
    }
}

/// Sets up the tasks each stage of a service's built-in pipeline creates — "Awaiting
/// Signature" gets its own tasks, "Ready to File" its own, and so on — without giving up the
/// built-in statuses.
struct BuiltInPipelineEditorView: View {
    let service: ServiceType

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [String: StageAutomation] = [:]
    @State private var expanded: String?
    @State private var loaded = false

    private var stages: [PipelineStage] { PipelineDefinition.builtIn(for: service).stages }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(stages) { stage in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expanded == stage.id },
                            set: { expanded = $0 ? stage.id : nil }
                        )) {
                            StageAutomationEditor(automation: binding(for: stage.id))
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(stage.color.color).frame(width: 10, height: 10)
                                Text(stage.name)
                                Spacer(minLength: 8)
                                Text(BuiltInSetup.summary(drafts[stage.id] ?? StageAutomation()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Tasks for each stage")
                } footer: {
                    Text("When a job of this service enters a stage — Advance, the status picker or dragging on the board — these tasks are created. Only the first gets a due date; each next one is dated when the one before it is completed. New jobs also get the first stage's tasks. On Hold / Waiting is never entered automatically, but can have tasks of its own.")
                }
            }
            .navigationTitle("\(service.label) stages")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: load)
        }
        .macSheetFrame()
    }

    private func binding(for stageKey: String) -> Binding<StageAutomation> {
        Binding(get: { drafts[stageKey] ?? StageAutomation() }, set: { drafts[stageKey] = $0 })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let resolved = BuiltInSetupService.resolved(context)
        for stage in stages {
            drafts[stage.id] = BuiltInSetup.automation(serviceTypeRaw: service.rawValue, stageKey: stage.id, in: resolved)
        }
    }

    private func save() {
        for stage in stages {
            BuiltInSetupService.save(drafts[stage.id] ?? StageAutomation(), service: service, stageKey: stage.id, context: context)
        }
        try? context.save()
        dismiss()
    }
}
