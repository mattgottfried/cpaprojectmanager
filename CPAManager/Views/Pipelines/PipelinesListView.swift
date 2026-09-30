import SwiftUI
import SwiftData

/// Manage custom pipelines ("Onboarding", "IRS Notice Response"…) and choose which pipeline
/// each service uses. The built-in per-service pipelines are always there.
struct PipelinesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @Query private var projects: [Project]

    var embedded = false
    @State private var editing: Pipeline?
    @State private var showingNew = false

    var body: some View {
        GroupedList {
            Section {
                ForEach(ServiceType.allCases) { service in
                    ServicePipelineRow(service: service, pipelines: pipelines) { pipeline in
                        editing = pipeline
                    }
                }
            } header: {
                Text("Pipeline for each service")
            } footer: {
                Text("Every service has its own built-in pipeline. Tax returns use Not Started → In Progress → Awaiting Signature → Ready to File → Filed → Complete; other services use Not Started → In Progress → Completed. On Hold / Waiting on Client is never entered automatically — you choose it. Tap Set up stage tasks to give each stage of a service's built-in pipeline its own tasks (created when a job enters that stage) while keeping the built-in statuses. Customize stages instead copies the stages into your own pipeline you can rename and reorder; those keep only the broad status: Not started, In progress, Waiting or Done.")
            }

            Section("Your pipelines") {
                ForEach(pipelines) { pipeline in
                    Button { editing = pipeline } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pipeline.name).foregroundStyle(.primary)
                                    Text(stageSummary(pipeline))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            } icon: {
                                Image(systemName: pipeline.systemImage)
                            }
                            Spacer()
                            Text("\(jobCount(pipeline))")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .deleteMenu(of: pipeline, in: pipelines, title: "Delete Pipeline", perform: delete)
                }
                .onDelete(perform: delete)

                if pipelines.isEmpty {
                    Text("No custom pipelines yet. Add one, or start from a ready-made set of stages.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Pipelines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Label("New Pipeline", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) { PipelineEditorView(pipeline: nil) }
        .sheet(item: $editing) { PipelineEditorView(pipeline: $0) }
    }

    private func stageSummary(_ pipeline: Pipeline) -> String {
        pipeline.stages.map(\.name).joined(separator: " → ")
    }

    private func jobCount(_ pipeline: Pipeline) -> Int {
        projects.filter { $0.pipelineID == pipeline.id && !$0.status.isComplete }.count
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let pipeline = pipelines[index]
            // Jobs fall back to the built-in pipeline; their coarse status is kept.
            for project in projects where project.pipelineID == pipeline.id {
                project.pipelineID = nil
                project.stageKey = ""
            }
            for template in (try? context.fetch(FetchDescriptor<WorkflowTemplate>())) ?? [] where template.pipelineID == pipeline.id {
                template.pipelineID = nil
                template.startStageKey = ""
            }
            // Services that defaulted to it go back to their built-in pipeline.
            for service in ServiceType.allCases where PipelineDefaults.pipelineID(for: service) == pipeline.id {
                UserDefaults.standard.removeObject(forKey: PipelineDefaults.key(for: service))
            }
            context.delete(pipeline)
        }
        try? context.save()
    }
}

/// One service's pipeline: the built-in stages, or a custom pipeline you've chosen for it.
private struct ServicePipelineRow: View {
    @Environment(\.modelContext) private var context
    let service: ServiceType
    let pipelines: [Pipeline]
    let onCustomize: (Pipeline) -> Void
    @AppStorage private var chosen: String
    @Query private var stageSetups: [BuiltInStageSetup]
    @State private var showingStageTasks = false

    init(service: ServiceType, pipelines: [Pipeline], onCustomize: @escaping (Pipeline) -> Void) {
        self.service = service
        self.pipelines = pipelines
        self.onCustomize = onCustomize
        _chosen = AppStorage(wrappedValue: "", PipelineDefaults.key(for: service))
    }

    private var builtIn: PipelineDefinition { PipelineDefinition.builtIn(for: service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(selection: $chosen) {
                Text("Built-in").tag("")
                ForEach(pipelines) { Text($0.name).tag($0.id.uuidString) }
            } label: {
                Label(service.label, systemImage: service.systemImage)
            }
            Text(stageSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if chosen.isEmpty {
                HStack(spacing: 14) {
                    Button("Set up stage tasks…") { showingStageTasks = true }
                    Button("Customize stages…") { customize() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                if configuredStageCount > 0 {
                    Text("\(configuredStageCount) stage\(configuredStageCount == 1 ? " has" : "s have") tasks set up.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingStageTasks) { BuiltInPipelineEditorView(service: service) }
    }

    /// Stages of this service's built-in pipeline that have tasks or a due-date reset.
    private var configuredStageCount: Int {
        let resolved = BuiltInSetup.resolve(stageSetups.map {
            BuiltInSetupInput(serviceTypeRaw: $0.serviceTypeRaw, stageKey: $0.stageKey, automation: $0.automation, updatedAt: $0.updatedAt)
        })
        return builtIn.stages.filter { !BuiltInSetup.automation(serviceTypeRaw: service.rawValue, stageKey: $0.id, in: resolved).isEmpty }.count
    }

    /// Copies the built-in stages into a real pipeline, makes it this service's default,
    /// and opens it for editing.
    private func customize() {
        var definition = builtIn
        definition.stages = definition.stages.map { stage in
            var copy = stage
            copy.id = UUID().uuidString
            return copy
        }
        let pipeline = Pipeline(definition: definition, sortIndex: pipelines.count)
        context.insert(pipeline)
        try? context.save()
        chosen = pipeline.id.uuidString
        onCustomize(pipeline)
    }

    private var stageSummary: String {
        if let custom = pipelines.first(where: { $0.id.uuidString == chosen }) {
            return custom.stages.map(\.name).joined(separator: " → ")
        }
        return builtIn.stages.map(\.name).joined(separator: " → ")
    }
}
