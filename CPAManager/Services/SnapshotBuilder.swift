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

        // Today-screen order: overdue, due today, then undated "next up".
        var plannerItems: [PlannerItem] = []
        var itemByID: [UUID: DashboardSnapshot.Item] = [:]
        if let projects = try? context.fetch(FetchDescriptor<Project>()) {
            for project in projects where !project.status.isComplete {
                plannerItems.append(PlannerItem(id: project.id, dueDate: project.dueDate, snoozedUntil: nil, isDone: false, isNextAction: false))
                itemByID[project.id] = .init(
                    id: project.id, title: project.title, subtitle: project.clientName,
                    dueDate: project.dueDate,
                    isOverdue: project.dueDate.map { calendar.startOfDay(for: $0) < today } ?? false,
                    isTask: false
                )
            }
        }
        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            let openTaskIDs = Set(tasks.filter { !$0.isDone }.map(\.id))
            for task in tasks where !task.isDone && task.project?.status.isComplete != true {
                plannerItems.append(PlannerItem(
                    id: task.id, dueDate: task.dueDate, snoozedUntil: task.snoozedUntil, isDone: false,
                    isNextAction: task.isNextAction,
                    isBlocked: TaskDependencies.isBlocked(blockedByID: task.blockedByID, openTaskIDs: openTaskIDs)
                ))
                itemByID[task.id] = .init(
                    id: task.id, title: task.title,
                    subtitle: task.project?.title ?? task.client?.displayName ?? "",
                    dueDate: task.dueDate,
                    isOverdue: task.dueDate.map { calendar.startOfDay(for: $0) < today } ?? false,
                    isTask: true
                )
            }
        }
        if let clients = try? context.fetch(FetchDescriptor<Client>()) {
            for client in clients where client.status != .inactive {
                guard let due = client.followUpDate else { continue }
                plannerItems.append(PlannerItem(id: client.id, dueDate: due, snoozedUntil: nil, isDone: false, isNextAction: false))
                itemByID[client.id] = .init(
                    id: client.id, title: "Follow up: \(client.displayName)", subtitle: "",
                    dueDate: due,
                    isOverdue: calendar.startOfDay(for: due) < today,
                    isTask: false
                )
            }
        }
        let plan = TodayPlanner.plan(plannerItems)
        let todayItems: [DashboardSnapshot.Item] = [TodaySection.overdue, .today, .next]
            .flatMap { plan.ids($0) }
            .compactMap { itemByID[$0] }
        let inboxCount = (try? context.fetchCount(
            FetchDescriptor<InboxItem>(predicate: #Predicate<InboxItem> { $0.isProcessed == false })
        )) ?? 0

        let snapshot = DashboardSnapshot(
            generatedAt: .now,
            dueTodayCount: dueToday,
            overdueCount: overdue,
            openProjectCount: openCount,
            upcoming: Array(upcoming),
            todayItems: Array(todayItems.prefix(12)),
            inboxCount: inboxCount
        )
        snapshot.save()

        #if os(iOS) && !targetEnvironment(macCatalyst)
        WatchBridge.shared.push(snapshot: snapshot)
        #endif

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
