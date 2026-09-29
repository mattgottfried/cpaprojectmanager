import Foundation
import SwiftData

/// A single checklist item within a project.
@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var dueDate: Date? = nil
    var sortIndex: Int = 0
    var completedAt: Date? = nil
    var createdAt: Date = Date.now
    /// A standalone "do this next" item with no due date. Shown on Today so
    /// undated work doesn't disappear.
    var isNextAction: Bool = false
    /// Hidden from Today until this day (start-of-day comparison).
    var snoozedUntil: Date? = nil

    var project: Project? = nil
    /// Optional client link for tasks that don't belong to a project.
    var client: Client? = nil

    init(
        title: String = "",
        notes: String = "",
        isDone: Bool = false,
        dueDate: Date? = nil,
        sortIndex: Int = 0,
        isNextAction: Bool = false,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.isDone = isDone
        self.dueDate = dueDate
        self.sortIndex = sortIndex
        self.isNextAction = isNextAction
        self.project = project
        self.createdAt = .now
    }

    /// Toggle done state and keep the completion timestamp in sync.
    func toggle() {
        isDone.toggle()
        completedAt = isDone ? .now : nil
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: .now)
    }
}
