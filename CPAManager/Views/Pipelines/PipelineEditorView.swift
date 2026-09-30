import SwiftUI
import SwiftData

struct PipelineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]

    var pipeline: Pipeline?

    @State private var name = ""
    @State private var systemImage = "rectangle.split.3x1"
    @State private var stages: [PipelineStage] = []
    @State private var loaded = false
    @State private var editingStageID: String?

    private static let icons = [
        "rectangle.split.3x1", "books.vertical.fill", "person.badge.plus", "banknote.fill",
        "envelope.badge.shield.half.filled", "doc.text.fill", "building.2.fill", "chart.bar.fill",
    ]

    private var definition: PipelineDefinition {
        PipelineDefinition(name: name, systemImage: systemImage, stages: stages)
    }
    private var errors: [String] { definition.validationErrors() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pipeline name (e.g. Bookkeeping)", text: $name)
                    Picker("Icon", selection: $systemImage) {
                        ForEach(Self.icons, id: \.self) { Label("", systemImage: $0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                if pipeline == nil {
                    Section("Start from") {
                        ForEach(PipelineStarters.all, id: \.name) { starter in
                            Button {
                                name = starter.name
                                systemImage = starter.systemImage
                                stages = starter.stages
                            } label: {
                                Label(starter.name, systemImage: starter.systemImage)
                            }
                        }
                    }
                }

                Section {
                    ForEach($stages) { $stage in
                        DisclosureGroup(isExpanded: expansion(for: stage.id)) {
                            Picker("Behaves like", selection: $stage.kind) {
                                ForEach(StageKind.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                            }
                            Picker("Color", selection: $stage.color) {
                                ForEach(StageColor.allCases) { Text($0.label).tag($0) }
                            }
                            automationEditor($stage.automation)
                        } label: {
                            HStack {
                                Circle().fill(stage.color.color).frame(width: 10, height: 10)
                                TextField("Stage name", text: $stage.name)
                                if !stage.automation.isEmpty {
                                    Image(systemName: "bolt.fill").font(.caption).foregroundStyle(Theme.brand)
                                }
                            }
                        }
                    }
                    .onDelete { stages.remove(atOffsets: $0) }
                    .onMove { stages.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        let stage = PipelineStage(name: "", kind: .working)
                        stages.append(stage)
                        editingStageID = stage.id
                    } label: {
                        Label("Add stage", systemImage: "plus")
                    }
                } header: {
                    Text("Stages")
                } footer: {
                    Text("Drag to reorder. \"Behaves like\" keeps reports, overdue checks and the widget working. Waiting stages are never entered by Advance — you choose them yourself. The bolt marks stages that add tasks or reset the due date when a job enters them.")
                }

                if !errors.isEmpty && loaded && (!name.isEmpty || !stages.isEmpty) {
                    Section {
                        ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.alert).font(.footnote) }
                    }
                }
            }
            .navigationTitle(pipeline == nil ? "New Pipeline" : "Edit Pipeline")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!errors.isEmpty) }
                #if os(iOS)
                ToolbarItem(placement: .leading) { EditButton() }
                #endif
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(get: { editingStageID == id }, set: { editingStageID = $0 ? id : nil })
    }

    @ViewBuilder
    private func automationEditor(_ automation: Binding<StageAutomation>) -> some View {
        Toggle("Reset due date on entry", isOn: Binding(
            get: { automation.wrappedValue.setDueInDays != nil },
            set: { automation.wrappedValue.setDueInDays = $0 ? 14 : nil }
        ))
        if let days = automation.wrappedValue.setDueInDays {
            Stepper("Due in \(days) days", value: Binding(
                get: { days },
                set: { automation.wrappedValue.setDueInDays = $0 }
            ), in: 0...365)
        }
        ForEach(automation.tasks) { $task in
            VStack(alignment: .leading, spacing: 4) {
                TextField("Task to create", text: $task.title)
                Stepper("Due \(task.dueInDays) days after entering", value: $task.dueInDays, in: 0...365)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDelete { automation.wrappedValue.tasks.remove(atOffsets: $0) }
        Button {
            automation.wrappedValue.tasks.append(StageTask(title: "", dueInDays: 1))
        } label: {
            Label("Add task on entry", systemImage: "plus.circle")
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let pipeline else { return }
        name = pipeline.name
        systemImage = pipeline.systemImage
        stages = pipeline.stages
    }

    private func save() {
        var cleaned = definition
        cleaned.name = name.trimmingCharacters(in: .whitespaces)
        cleaned.stages = stages.map {
            var stage = $0
            stage.name = stage.name.trimmingCharacters(in: .whitespaces)
            stage.automation.tasks.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            return stage
        }
        if let pipeline {
            pipeline.definition = cleaned
        } else {
            let next = (pipelines.map(\.sortIndex).max() ?? -1) + 1
            context.insert(Pipeline(definition: cleaned, sortIndex: next))
        }
        try? context.save()
        dismiss()
    }
}
