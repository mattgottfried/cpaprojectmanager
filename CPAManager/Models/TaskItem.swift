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

    var project: Project? = nil

    init(
        title: String = "",
        notes: String = "",
        isDone: Bool = false,
        dueDate: Date? = nil,
        sortIndex: Int = 0,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.isDone = isDone
        self.dueDate = dueDate
        self.sortIndex = sortIndex
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
