import Foundation

enum TaskDependencies {
    /// A task is blocked while the task it depends on is still open. Once the blocker is
    /// done (or deleted) the task becomes available again — no manual unblocking.
    static func isBlocked(blockedByID: UUID?, openTaskIDs: Set<UUID>) -> Bool {
        guard let blockedByID else { return false }
        return openTaskIDs.contains(blockedByID)
    }

    /// Due date for a chained task once its blocker was completed: `daysAfter` days after
    /// the day the blocker was finished (never in the past).
    static func dueDateOnUnblock(daysAfter: Int, completedAt: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: completedAt)
        return calendar.date(byAdding: .day, value: max(0, daysAfter), to: day) ?? day
    }

    /// True if making `taskID` depend on `newBlockerID` would loop back on itself
    /// (A blocked by B blocked by A). `blockedBy` maps task id → the id it waits on.
    static func wouldCreateCycle(taskID: UUID, newBlockerID: UUID, blockedBy: [UUID: UUID]) -> Bool {
        var current: UUID? = newBlockerID
        var seen: Set<UUID> = []
        while let id = current {
            if id == taskID { return true }
            if !seen.insert(id).inserted { return false }   // an existing loop that doesn't involve us
            current = blockedBy[id]
        }
        return false
    }

    /// Ids that may be offered as this task's blocker.
    static func candidateBlockers(taskID: UUID, openTaskIDs: [UUID], blockedBy: [UUID: UUID]) -> [UUID] {
        openTaskIDs.filter { $0 != taskID && !wouldCreateCycle(taskID: taskID, newBlockerID: $0, blockedBy: blockedBy) }
    }
}

enum TaskChecklist {
    /// Appends an unchecked item (ignores blank input).
    static func adding(_ item: String, to checklist: String) -> String {
        let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return checklist }
        let line = "- [ ] \(clean)"
        return checklist.isEmpty ? line : checklist + "\n" + line
    }

    /// "2/5" style summary; nil when the checklist has no items.
    static func summary(_ checklist: String) -> String? {
        let progress = MarkdownBlocks.checkboxProgress(checklist)
        return progress.total == 0 ? nil : "\(progress.done)/\(progress.total)"
    }

    static func isComplete(_ checklist: String) -> Bool {
        let progress = MarkdownBlocks.checkboxProgress(checklist)
        return progress.total > 0 && progress.done == progress.total
    }
}
