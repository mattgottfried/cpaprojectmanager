import SwiftUI
import SwiftData

/// Kanban-style board of open work for one pipeline (the built-in tax-return pipeline or
/// a custom one). Cards can be dragged between columns to change a project's stage. On
/// the built-in pipeline dragging only sets the status (unlike the one-tap "Advance"
/// action, it does not also push the due date out); custom stages run their own entry
/// automation (tasks, due date) as configured.
struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @AppStorage("boardPipelineID") private var selectedPipeline = ""   // "" = built-in

    /// "" = Tax Return (built in), "general" = General (built in), otherwise a custom pipeline's id.
    private var pipeline: Pipeline? {
        pipelines.first { $0.id.uuidString == selectedPipeline }
    }

    private var builtInFlow: StatusFlow { selectedPipeline == "general" ? .general : .taxReturn }

    private var definition: PipelineDefinition {
        pipeline?.definition ?? PipelineDefinition.builtIn(builtInFlow)
    }

    private var columns: [PipelineStage] { definition.boardStages }

    /// Jobs on this board. A job whose stage was deleted lands in the first column.
    private func projects(for stage: PipelineStage) -> [Project] {
        let pipelineID = pipeline?.id
        let firstKey = columns.first?.id
        return projects
            .filter { $0.pipelineID == pipelineID && !$0.status.isComplete }
            .filter { pipelineID != nil || $0.statusFlow == builtInFlow }
            .filter { project in
                let key = pipelineID == nil ? project.statusFlow.normalize(project.status).rawValue : project.stageKey
                if definition.stage(withKey: key) != nil { return key == stage.id }
                return stage.id == firstKey
            }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Pipeline", selection: $selectedPipeline) {
                Text(StatusFlow.taxReturn.pipelineName).tag("")
                Text(StatusFlow.general.pipelineName).tag("general")
                ForEach(pipelines) { Text($0.name).tag($0.id.uuidString) }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(columns) { stage in
                        columnView(stage)
                    }
                }
                .padding()
            }
        }
        .background(Color.appGroupedBackground)
    }

    private func columnView(_ stage: PipelineStage) -> some View {
        let items = projects(for: stage)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(stage.name, systemImage: stage.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stage.color.color)
                    .lineLimit(1)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { project in
                        NavigationLink(value: project) {
                            BoardCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .draggable(project.id.uuidString)
                    }
                    if items.isEmpty {
                        Text("No items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                }
            }
        }
        .frame(width: 260)
        .padding(8)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let id = UUID(uuidString: idString),
                  let project = projects.first(where: { $0.id == id }),
                  project.pipelineID == pipeline?.id else { return false }
            if pipeline == nil {
                guard project.statusFlow == builtInFlow else { return false }
                if let status = ProjectStatus(rawValue: stage.id) { project.status = status }
            } else if project.stageKey != stage.id {
                PipelineEngine.enter(project, stage: stage, context: context)
            }
            persist()
            return true
        }
    }

    private func persist() {
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
    }
}

struct BoardCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(project.clientName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let due = project.dueDate {
                DueDatePill(date: due, isComplete: project.status.isComplete)
            }
            if project.totalTaskCount > 0 {
                ProgressView(value: project.progress)
                    .tint(Theme.brand)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appTertiaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
