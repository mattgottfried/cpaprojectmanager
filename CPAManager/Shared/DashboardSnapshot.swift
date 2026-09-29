import Foundation

/// A small, Codable summary the app writes to the shared App Group container so the
/// home-screen widget can render without touching SwiftData. Kept intentionally
/// plain (no `@Model` references) because this file is compiled into the widget too.
struct DashboardSnapshot: Codable, Hashable {
    struct Item: Codable, Hashable, Identifiable {
        var id: UUID
        var title: String
        var subtitle: String
        var dueDate: Date?
        var isOverdue: Bool
        /// True for a standalone/checklist task the widget can complete (vs. a
        /// project, which opens the app). Optional so older snapshots still decode.
        var isTask: Bool? = nil
    }

    var generatedAt: Date
    var dueTodayCount: Int
    var overdueCount: Int
    var openProjectCount: Int
    var upcoming: [Item]
    /// Overdue + due today + "next up", in Today-screen order. Optional so snapshots
    /// written by an older build still decode.
    var todayItems: [Item]? = nil
    var inboxCount: Int? = nil

    static let empty = DashboardSnapshot(
        generatedAt: .now,
        dueTodayCount: 0,
        overdueCount: 0,
        openProjectCount: 0,
        upcoming: []
    )
}

extension DashboardSnapshot {
    /// Read the latest snapshot from the shared container (returns `.empty` if none).
    static func load() -> DashboardSnapshot {
        guard
            let defaults = AppGroup.sharedDefaults,
            let data = defaults.data(forKey: AppGroup.snapshotKey),
            let snapshot = try? JSONDecoder().decode(DashboardSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    /// Persist this snapshot to the shared container.
    func save() {
        guard
            let defaults = AppGroup.sharedDefaults,
            let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: AppGroup.snapshotKey)
    }
}

/// Completions requested from the widget, waiting for the app to apply them to the
/// real SwiftData store (the widget extension can't open that CloudKit-backed store).
enum PendingActions {
    static let completionsKey = "pendingTaskCompletions"

    static func enqueueCompletion(taskID: UUID) {
        guard let defaults = AppGroup.sharedDefaults else { return }
        var ids = defaults.stringArray(forKey: completionsKey) ?? []
        let id = taskID.uuidString
        if !ids.contains(id) { ids.append(id) }
        defaults.set(ids, forKey: completionsKey)
    }

    /// Returns and clears the queue.
    static func drainCompletions() -> [UUID] {
        guard let defaults = AppGroup.sharedDefaults else { return [] }
        let ids = defaults.stringArray(forKey: completionsKey) ?? []
        defaults.removeObject(forKey: completionsKey)
        return ids.compactMap { UUID(uuidString: $0) }
    }
}

extension DashboardSnapshot {
    /// The widget's optimistic edit after a tap: drop the item and fix the counts so
    /// the widget updates instantly, before the app has processed the completion.
    func removingItem(id: UUID) -> DashboardSnapshot {
        var copy = self
        let all = (todayItems ?? []) + upcoming
        if let item = all.first(where: { $0.id == id }) {
            if item.isOverdue {
                copy.overdueCount = max(0, copy.overdueCount - 1)
            } else if let due = item.dueDate, Calendar.current.isDateInToday(due) {
                copy.dueTodayCount = max(0, copy.dueTodayCount - 1)
            }
        }
        copy.upcoming.removeAll { $0.id == id }
        copy.todayItems?.removeAll { $0.id == id }
        return copy
    }
}
