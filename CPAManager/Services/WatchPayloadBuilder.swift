import Foundation

/// Turns the dashboard snapshot into the compact payload shown on the Apple Watch.
enum WatchPayloadBuilder {
    static func make(
        snapshot: DashboardSnapshot,
        timerStartedAt: Date?,
        timerLabel: String,
        limit: Int = 10
    ) -> WatchPayload {
        let source = snapshot.todayItems ?? snapshot.upcoming
        let tasks: [WatchPayload.Task] = source.prefix(limit).map { item in
            WatchPayload.Task(
                id: item.id, title: item.title, subtitle: item.subtitle,
                isOverdue: item.isOverdue, isTask: item.isTask ?? false
            )
        }
        return WatchPayload(
            generatedAt: snapshot.generatedAt,
            overdueCount: snapshot.overdueCount,
            dueTodayCount: snapshot.dueTodayCount,
            tasks: tasks,
            timerStartedAt: timerStartedAt,
            timerLabel: timerLabel
        )
    }
}
