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
        dateChainedTasks(after: task, completedAt: task.completedAt ?? now)

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
        for next in chained(after: task) where !next.isDone { next.dueDate = nil }
    }

    /// Pipeline tasks that were waiting on `task` and have no date yet.
    private static func chained(after task: TaskItem) -> [TaskItem] {
        (task.project?.tasks ?? []).filter { $0.blockedByID == task.id && $0.dueInDaysAfterBlocker != nil }
    }

    /// Gives the tasks that were waiting on `task` their due date, counted from today.
    private static func dateChainedTasks(after task: TaskItem, completedAt: Date) {
        for next in chained(after: task) where next.dueDate == nil && !next.isDone {
            next.dueDate = TaskDependencies.dueDateOnUnblock(daysAfter: next.dueInDaysAfterBlocker ?? 0, completedAt: completedAt)
        }
    }
}
