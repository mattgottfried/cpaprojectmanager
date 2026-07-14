import Foundation
import SwiftData
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Computes the dashboard summary and writes it to the shared App Group container,
/// then nudges WidgetKit to refresh. Called whenever data changes.
enum SnapshotBuilder {

    static func rebuild(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        var overdue = 0
        var dueToday = 0
        var openCount = 0
        var items: [DashboardSnapshot.Item] = []

        if let projects = try? context.fetch(FetchDescriptor<Project>()) {
            for project in projects where !project.status.isComplete {
                openCount += 1
                guard let due = project.dueDate else { continue }
                let day = calendar.startOfDay(for: due)
                if day < today { overdue += 1 } else if day == today { dueToday += 1 }
                items.append(.init(
                    id: project.id,
                    title: project.title,
                    subtitle: project.clientName,
                    dueDate: due,
                    isOverdue: day < today
                ))
            }
        }

        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            for task in tasks where !task.isDone {
                guard let due = task.dueDate else { continue }
                let day = calendar.startOfDay(for: due)
                if day < today { overdue += 1 } else if day == today { dueToday += 1 }
                items.append(.init(
                    id: task.id,
                    title: task.title,
                    subtitle: task.project?.title ?? "Task",
                    dueDate: due,
                    isOverdue: day < today
                ))
            }
        }

        let upcoming = items
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(5)

        let snapshot = DashboardSnapshot(
            generatedAt: .now,
            dueTodayCount: dueToday,
            overdueCount: overdue,
            openProjectCount: openCount,
            upcoming: Array(upcoming)
        )
        snapshot.save()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
