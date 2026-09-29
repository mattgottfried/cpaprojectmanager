import AppIntents
import WidgetKit

/// Tapping a row's circle in the widget. The widget extension can't open the app's
/// CloudKit-backed store, so this (1) updates the shared snapshot so the widget
/// redraws immediately, and (2) queues the completion for the app, which applies it
/// to the real task the next time it opens.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Marks a task done from the widget.")
    static var isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            PendingActions.enqueueCompletion(taskID: id)
            DashboardSnapshot.load().removingItem(id: id).save()
        }
        return .result()
    }
}
