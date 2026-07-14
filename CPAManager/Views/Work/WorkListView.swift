import SwiftUI
import SwiftData

struct WorkListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]
    @State private var search = ""
    @State private var filter: WorkFilter = .open
    @State private var showingAdd = false

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
                } else {
                    List {
                        ForEach(filtered) { project in
                            NavigationLink(value: project) {
                                ProjectRow(project: project)
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $showingAdd) { ProjectFormView() }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
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
