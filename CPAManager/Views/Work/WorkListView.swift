import SwiftUI
import SwiftData

struct WorkListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var search = ""
    @State private var filter: WorkFilter = .open
    @State private var showingAdd = false
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
                            .swipeActions(edge: .leading) {
                                if let next = project.nextStatusPreview {
                                    Button {
                                        project.advance()
                                        persistChange()
                                    } label: {
                                        Label("Advance to \(next.label)", systemImage: "arrow.right.circle.fill")
                                    }
                                    .tint(Theme.brand)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Work")
            .searchable(text: $search, prompt: "Search work")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Filter", selection: $filter) {
                        ForEach(WorkFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .disabled(showBoard)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showBoard.toggle()
                    } label: {
                        Image(systemName: showBoard ? "list.bullet" : "rectangle.split.3x1")
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
            .sheet(isPresented: $showingAdd) { ProjectFormView() }
            .sheet(isPresented: $showingNewTaxReturn) { NewTaxReturnView() }
        }
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
    let project: Project
    var showClient: Bool = true

    var body: some View {
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
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if !project.nextAction.isEmpty {
                    Label(project.nextAction, systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(status: project.status)
                PriorityBadge(priority: project.priority)
            }
        }
        .padding(.vertical, 4)
    }
}
