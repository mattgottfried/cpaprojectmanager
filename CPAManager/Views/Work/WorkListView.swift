import SwiftUI
import SwiftData

struct WorkListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @AppStorage("workPipelineFilter") private var pipelineFilter = ""   // "" = all, "builtin", or a pipeline UUID
    @State private var search = ""
    @State private var filter: WorkFilter = .open
    @State private var showingAdd = false
    @State private var linkedProject: Project?
    @Environment(AppRouter.self) private var router
    @State private var showingNewTaxReturn = false
    @AppStorage("workShowsBoard") private var showBoard = false

    enum WorkFilter: String, CaseIterable, Identifiable {
        case open = "Open"
        case all = "All"
        case complete = "Complete"
        var id: String { rawValue }
    }

    private var filtered: [Project] {
        projects
            .filter { project in
                switch filter {
                case .open:     return !project.status.isComplete
                case .all:      return true
                case .complete: return project.status.isComplete
                }
            }
            .filter { project in
                switch pipelineFilter {
                case "":                 return true
                case "tax", "builtin":   return project.pipelineID == nil && project.statusFlow == .taxReturn
                case "general":          return project.pipelineID == nil && project.statusFlow == .general
                default:                 return project.pipelineID?.uuidString == pipelineFilter
                }
            }
            .filter { project in
                search.isEmpty
                    || project.title.localizedCaseInsensitiveContains(search)
                    || project.clientName.localizedCaseInsensitiveContains(search)
            }
            .sorted {
                if $0.status.order != $1.status.order { return $0.status.order < $1.status.order }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    EmptyStateView(
                        title: "No Work Yet",
                        message: "Create a project, or start one from a template.",
                        systemImage: "checklist"
                    )
                } else if showBoard {
                    BoardView()
                } else {
                    List {
                        ForEach(filtered) { project in
                            NavigationLink(value: project) {
                                ProjectRow(project: project)
                            }
                            .cardListRow()
                            .swipeActions(edge: .leading) {
                                if let next = PipelineEngine.nextStageName(for: project, in: pipelines) {
                                    Button {
                                        PipelineEngine.advanceAny(project, pipelines: pipelines, context: context)
                                        persistChange()
                                    } label: {
                                        Label("Advance to \(next)", systemImage: "arrow.right.circle.fill")
                                    }
                                    .tint(Theme.brand)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.appGroupedBackground)
                }
            }
            .navigationTitle("Work")
            .searchable(text: $search, prompt: "Search work")
            .toolbar {
                ToolbarItem(placement: .leading) {
                    Picker("Filter", selection: $filter) {
                        ForEach(WorkFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .disabled(showBoard)
                }
                if !showBoard {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Pipeline", selection: $pipelineFilter) {
                            Text("All pipelines").tag("")
                            Text(StatusFlow.taxReturn.pipelineName).tag("tax")
                            Text(StatusFlow.general.pipelineName).tag("general")
                            ForEach(pipelines) { Text($0.name).tag($0.id.uuidString) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showBoard.toggle()
                    } label: {
                        Image(systemName: showBoard ? "list.bullet" : "rectangle.split.3x1")
                            .accessibilityLabel(showBoard ? "Show list" : "Show board")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingNewTaxReturn = true } label: {
                            Label("New Tax Return", systemImage: "doc.text.fill")
                        }
                        Button { showingAdd = true } label: {
                            Label("New Project", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .navigationDestination(item: $linkedProject) { ProjectDetailView(project: $0) }
            .onAppear(perform: consumeLink)
            .onChange(of: router.pendingLink) { _, _ in consumeLink() }
            .sheet(isPresented: $showingAdd) { ProjectFormView() }
            .sheet(isPresented: $showingNewTaxReturn) { NewTaxReturnView() }
        }
    }

    private func consumeLink() {
        guard case .project(let id)? = router.pendingLink,
              let project = projects.first(where: { $0.id == id }) else { return }
        router.pendingLink = nil
        linkedProject = project
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
    }

    private func persistChange() {
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
    }
}

struct ProjectRow: View {
    @Query private var pipelines: [Pipeline]
    let project: Project
    var showClient: Bool = true
    /// Render as a free-standing card (Work list). Off inside grouped forms/lists.
    var card: Bool = true

    var body: some View {
        if card {
            rowContent
                .rowCard(dimmed: project.status.isComplete)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(project.title)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Opens the project")
        } else {
            rowContent
        }
    }

    private var accessibilityValue: String {
        var parts = [PipelineEngine.info(for: project, in: pipelines).name]
        if showClient { parts.append(project.clientName) }
        if let due = project.dueDate { parts.append("due \(Format.relativeDay(due))") }
        if project.totalTaskCount > 0 { parts.append("\(project.completedTaskCount) of \(project.totalTaskCount) tasks done") }
        if project.isOnHold, let reason = project.holdReason { parts.append("on hold: \(reason.label)") }
        else if !project.nextAction.isEmpty { parts.append("next: \(project.nextAction)") }
        return parts.joined(separator: ", ")
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ServiceTypeIcon(serviceType: project.serviceType)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if showClient {
                        Text(project.clientName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if project.totalTaskCount > 0 {
                        Text("\(project.completedTaskCount)/\(project.totalTaskCount) tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let due = project.dueDate {
                    DueDatePill(date: due, isComplete: project.status.isComplete)
                }
                if project.isOnHold, let reason = project.holdReason {
                    Label(reason.label, systemImage: "pause.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.bad)
                        .lineLimit(1)
                } else if !project.nextAction.isEmpty {
                    Label(project.nextAction, systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.alert)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StageBadge(info: PipelineEngine.info(for: project, in: pipelines))
                PriorityBadge(priority: project.priority)
            }
        }
    }
}
