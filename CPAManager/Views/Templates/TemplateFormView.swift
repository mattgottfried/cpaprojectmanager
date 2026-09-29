import SwiftUI
import SwiftData

struct TemplateFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var template: WorkflowTemplate?

    @State private var name = ""
    @State private var detail = ""
    @State private var serviceType: ServiceType = .taxReturn
    @State private var durationDays = 30
    @State private var steps: [DraftStep] = []
    @State private var loaded = false

    private struct DraftStep: Identifiable {
        let id = UUID()
        var title: String
        var dayOffset: Int
    }

    private var isEditing: Bool { template != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                    Picker("Service", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Turnaround: \(durationDays) days", value: $durationDays, in: 1...365)
                }

                Section("Description") {
                    TextField("Optional", text: $detail, axis: .vertical).lineLimit(2...5)
                }

                Section("Steps") {
                    ForEach($steps) { $step in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Step", text: $step.title)
                            Stepper("Due day +\(step.dayOffset)", value: $step.dayOffset, in: 0...365)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        steps.append(DraftStep(title: "", dayOffset: nextOffset()))
                    } label: {
                        Label("Add step", systemImage: "plus")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
                ToolbarItem(placement: .leading) { EditButton() }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func nextOffset() -> Int {
        (steps.map(\.dayOffset).max() ?? 0) + 1
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let template else { return }
        name = template.name
        detail = template.detail
        serviceType = template.serviceType
        durationDays = template.defaultDurationDays
        steps = template.taskList.map { DraftStep(title: $0.title, dayOffset: $0.dayOffset) }
    }

    private func save() {
        let cleanedSteps = steps
            .map { DraftStep(title: $0.title.trimmingCharacters(in: .whitespaces), dayOffset: $0.dayOffset) }
            .filter { !$0.title.isEmpty }

        let target: WorkflowTemplate
        if let template {
            target = template
            target.name = name
            target.detail = detail
            target.serviceType = serviceType
            target.defaultDurationDays = durationDays
            // Rebuild the step list from the draft.
            for existing in target.taskList { context.delete(existing) }
        } else {
            target = WorkflowTemplate(
                name: name,
                detail: detail,
                serviceType: serviceType,
                defaultDurationDays: durationDays
            )
            context.insert(target)
        }

        for (index, step) in cleanedSteps.enumerated() {
            let task = TemplateTask(title: step.title, sortIndex: index, dayOffset: step.dayOffset, template: target)
            context.insert(task)
        }

        try? context.save()
        dismiss()
    }
}
