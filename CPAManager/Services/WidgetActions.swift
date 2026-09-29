import Foundation
import SwiftData

/// Applies actions taken in the widget (which can't open the CloudKit-backed store)
/// to the real data. Called on launch and whenever the app becomes active.
enum WidgetActions {
    static func applyPending(context: ModelContext, reminderHour: Int) {
        let ids = Set(PendingActions.drainCompletions())
        guard !ids.isEmpty else { return }

        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        var changed = false
        for task in tasks where ids.contains(task.id) && !task.isDone {
            task.toggle()
            changed = true
        }
        guard changed else { return }
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        SnapshotBuilder.rebuild(context: context)
    }
}
