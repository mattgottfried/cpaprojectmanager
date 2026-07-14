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
    }

    var generatedAt: Date
    var dueTodayCount: Int
    var overdueCount: Int
    var openProjectCount: Int
    var upcoming: [Item]

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
