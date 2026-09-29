import SwiftUI
import SwiftData

/// Kanban-style board of all open work, grouped by pipeline stage. Cards can be
/// dragged between columns to change a project's status directly (unlike the
/// one-tap "Advance" action, dragging does not also push the due date out).
struct BoardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    private var columns: [ProjectStatus] {
        ProjectStatus.allCases.filter { $0 != .complete }
    }

    private func projects(for status: ProjectStatus) -> [Project] {
        projects
            .filter { $0.status == status }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { status in
                    columnView(status)
                }
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
    }

    private func columnView(_ status: ProjectStatus) -> some View {
        let items = projects(for: status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(status.label, systemImage: status.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.color)
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
                  let project = projects.first(where: { $0.id == id }) else { return false }
            project.status = status
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
