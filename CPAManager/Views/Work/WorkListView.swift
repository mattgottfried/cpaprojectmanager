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
    @State private var selection = ListSelection<UUID>()
    @State private var toast: UndoToastState?
    @State private var showingBulkDate = false
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
                case "tax", "builtin":   return project.pipelineID == nil && project.serviceType == .taxReturn
                case "general":          return project.pipelineID == nil && project.serviceType != .taxReturn
                default:
                    if pipelineFilter.hasPrefix("service:") {
                        return project.pipelineID == nil && project.serviceType.rawValue == String(pipelineFilter.dropFirst(8))
                    }
                    return project.pipelineID?.uuidString == pipelineFilter
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
                            SelectableRow(
                                isSelecting: selection.isSelecting,
                                isSelected: selection.selected.contains(project.id),
                                isCursor: selection.cursor == project.id,
                                toggle: { selection.toggle(project.id) }
                            ) {
                                ProjectRow(project: project)
                            } link: {
                                NavigationLink(value: project) {
                                    ProjectRow(project: project)
                                }
                            }
                            .cardListRow()
                            .contextMenu {
                                Button(role: .destructive) { deleteProjects([project]) } label: {
                                    Label("Delete Project", systemImage: "trash")
                                }
                            }
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
                    .macReadableWidth()
                    .listKeyboard(
                        move: { selection.cursor = ListSelection.moved(from: selection.cursor, in: filtered.map(\.id), by: $0) },
                        open: { if let id = selection.cursor { linkedProject = filtered.first { $0.id == id } } },
                        toggle: { if let id = selection.cursor { selection.toggle(id) } },
                        delete: { deleteProjects(keyboardTargets) }
                    )
                    .safeAreaInset(edge: .bottom) {
                        if selection.isSelecting { bulkBar }
                    }
                    .onChange(of: filtered.map(\.id)) { _, ids in selection.prune(to: ids) }
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
                            ForEach(ServiceType.allCases) { Text($0.label).tag("service:" + $0.rawValue) }
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
                        if !showBoard {
                            Divider()
                            Button {
                                if selection.isSelecting { selection.finish() } else { selection.isSelecting = true }
                            } label: {
                                Label(selection.isSelecting ? "Done Selecting" : "Select Jobs…", systemImage: "checkmark.circle")
                            }
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
            .sheet(isPresented: $showingBulkDate) {
                BulkDateSheet(title: "Set Due Date") { date in
                    toast = context.performUndoable("Updated \(selectedProjects.count) jobs", overwrite: true) {
                        BulkActions.setDueDate(selectedProjects, to: date)
                    }
                    NotificationScheduler.rescheduleAll(context: context)
                }
            }
            .undoToast($toast)
        }
    }

    // MARK: Selecting several jobs

    private var selectedProjects: [Project] { projects.filter { selection.selected.contains($0.id) } }

    /// What the Delete key acts on: the ticked rows, else the row under the cursor.
    private var keyboardTargets: [Project] {
        if !selection.selected.isEmpty { return selectedProjects }
        return projects.filter { $0.id == selection.cursor }
    }

    private var bulkBar: some View {
        BulkBar(count: selection.count, done: { selection.finish() }) {
            Menu {
                Button {
                    toast = context.performUndoable("Advanced \(selectedProjects.count) jobs", overwrite: true) {
                        BulkActions.advance(selectedProjects, pipelines: pipelines, context: context)
                    }
                } label: { Label("Advance stage", systemImage: "arrow.right.circle") }
                Button {
                    toast = context.performUndoable("Completed \(selectedProjects.count) jobs", overwrite: true) {
                        BulkActions.complete(selectedProjects, pipelines: pipelines, context: context)
                    }
                } label: { Label("Mark complete", systemImage: "checkmark.circle") }
                Button { showingBulkDate = true } label: { Label("Set due date…", systemImage: "calendar") }
            } label: { Label("Update", systemImage: "ellipsis.circle") }
            Button(role: .destructive) {
                deleteProjects(selectedProjects)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func deleteProjects(_ doomed: [Project]) {
        guard !doomed.isEmpty else { return }
        let message = doomed.count == 1 ? "Deleted job" : "Deleted \(doomed.count) jobs"
        toast = context.deleteWithUndo(message, includeFiles: true) {
            for project in doomed { context.delete(project) }
        }
        selection.finish()
    }

    private func consumeLink() {
        guard case .project(let id)? = router.pendingLink,
              let project = projects.first(where: { $0.id == id }) else { return }
        router.pendingLink = nil
        linkedProject = project
    }

    private func delete(_ offsets: IndexSet) {
        let list = filtered
        deleteProjects(offsets.map { list[$0] })
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
        else if !project.status.isComplete, let next = project.nextTask { parts.append("next task: \(next.title)") }
        return parts.joined(separator: ", ")
    }

    private func nextStepText(_ task: TaskItem) -> String {
        guard let due = task.dueDate else { return task.title }
        return "\(task.title) · \(Format.relativeDay(due))"
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
                } else if !project.status.isComplete, let next = project.nextTask {
                    Label(nextStepText(next), systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
