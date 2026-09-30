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
    /// Raw `RepeatRule`; empty/"none" means it doesn't repeat.
    var repeatRuleRaw: String = ""
    /// Subtasks as Markdown checkbox lines ("- [ ] call the bank"); see `TaskChecklist`.
    var checklist: String = ""
    /// Hidden from Today until that task is done (see `TaskDependencies`).
    var blockedByID: UUID? = nil
    /// Set on pipeline tasks that wait for the one before them: when the blocker is
    /// completed this task gets a due date this many days later (see `TaskDependencies`).
    var dueInDaysAfterBlocker: Int? = nil
    /// Free-text "waiting on…" note (e.g. "client's W-2"), shown on the task.
    var waitingOn: String = ""

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

    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .none }
        set { repeatRuleRaw = newValue == .none ? "" : newValue.rawValue }
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
