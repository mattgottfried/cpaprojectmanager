import Foundation

/// A unified due-dated item (project or task) for the dashboard and deadlines views.
struct AgendaItem: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let dueDate: Date
    let isComplete: Bool
    /// The project to navigate to when tapped (a task points at its parent).
    let project: Project?
}

enum Agenda {
    static func items(projects: [Project], tasks: [TaskItem], includeComplete: Bool = false) -> [AgendaItem] {
        var result: [AgendaItem] = []

        for project in projects {
            guard let due = project.dueDate else { continue }
            if !includeComplete && project.status.isComplete { continue }
            result.append(AgendaItem(
                id: project.id,
                title: project.title,
                subtitle: project.clientName,
                dueDate: due,
                isComplete: project.status.isComplete,
                project: project
            ))
        }

        for task in tasks {
            guard let due = task.dueDate else { continue }
            if !includeComplete && task.isDone { continue }
            result.append(AgendaItem(
                id: task.id,
                title: task.title,
                subtitle: task.project?.title ?? "Task",
                dueDate: due,
                isComplete: task.isDone,
                project: task.project
            ))
        }

        return result.sorted { $0.dueDate < $1.dueDate }
    }

    /// Bucket label for grouping (Overdue / Today / This Week / Later).
    static func bucket(for date: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: .now)
        let day = calendar.startOfDay(for: date)
        if day < today { return "Overdue" }
        if day == today { return "Today" }
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days <= 7 { return "This Week" }
        return "Later"
    }

    static let bucketOrder = ["Overdue", "Today", "This Week", "Later"]
}
