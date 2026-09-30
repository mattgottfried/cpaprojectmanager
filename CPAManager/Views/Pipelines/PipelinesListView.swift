import SwiftUI
import SwiftData

/// Manage custom pipelines ("Bookkeeping", "Onboarding"…). The built-in tax-return
/// pipeline is always there and isn't editable.
struct PipelinesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @Query private var projects: [Project]

    var embedded = false
    @State private var editing: Pipeline?
    @State private var showingNew = false

    var body: some View {
        List {
            Section {
                ForEach(StatusFlow.allCases) { flow in
                    let definition = PipelineDefinition.builtIn(flow)
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(definition.name)
                            Text(definition.stages.map(\.name).joined(separator: " → "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: definition.systemImage)
                    }
                }
            } header: {
                Text("Built in")
            } footer: {
                Text("Tax returns use the Tax Return stages. All other work without a custom pipeline uses General.")
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
            context.delete(pipeline)
        }
        try? context.save()
    }
}
