import Foundation
import SwiftData

/// The one place a task gets completed, so repeating tasks behave the same from the
/// Today screen, the weekly review, and the widget.
enum TaskCompletion {
    /// Marks `task` done. If it repeats, schedules and returns the next occurrence.
    @discardableResult
    static func complete(_ task: TaskItem, context: ModelContext, now: Date = .now) -> TaskItem? {
        guard !task.isDone else { return nil }
        task.toggle()

        let rule = task.repeatRule
        guard rule != .none,
              let next = TaskRecurrence.nextOccurrence(after: task.dueDate ?? now, rule: rule, now: now)
        else { return nil }

        let copy = TaskItem(
            title: task.title,
            notes: task.notes,
            dueDate: next,
            sortIndex: task.sortIndex,
            project: task.project
        )
        copy.client = task.client
        copy.repeatRule = rule
        context.insert(copy)
        return copy
    }

    /// Reverses `complete`, removing any occurrence it spawned.
    static func undo(_ task: TaskItem, spawned: TaskItem?, context: ModelContext) {
        if task.isDone { task.toggle() }
        if let spawned { context.delete(spawned) }
    }
}
