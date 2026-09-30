import Foundation

// Pure logic behind the "next step" line on jobs and the select / keyboard behavior of
// the Work and Clients lists. No SwiftData, no SwiftUI. Unit-tested.

/// A task as `NextStep` sees it.
struct NextStepTask: Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var sortIndex: Int
    var isDone: Bool
    var blockedByID: UUID?
}

enum NextStep {
    /// The one task to do next on a job: open and not waiting on another open task, the
    /// earliest due first (undated last), then list order.
    static func pick(_ tasks: [NextStepTask]) -> NextStepTask? {
        let openIDs = Set(tasks.filter { !$0.isDone }.map(\.id))
        return tasks
            .filter { !$0.isDone && !TaskDependencies.isBlocked(blockedByID: $0.blockedByID, openTaskIDs: openIDs) }
            .min { a, b in
                let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
                if da != db { return da < db }
                return a.sortIndex < b.sortIndex
            }
    }
}

/// Multi-select and keyboard-cursor state for a list of rows.
struct ListSelection<ID: Hashable> {
    var isSelecting = false
    var selected: Set<ID> = []
    /// The row the keyboard is on (Mac); nil until an arrow key is pressed.
    var cursor: ID?

    var count: Int { selected.count }

    mutating func toggle(_ id: ID) {
        isSelecting = true
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    mutating func selectAll(_ ids: [ID]) {
        isSelecting = true
        selected = Set(ids)
    }

    mutating func finish() {
        isSelecting = false
        selected = []
    }

    /// Drops selected/cursor ids that are no longer in the list (after a delete or filter).
    mutating func prune(to ids: [ID]) {
        let live = Set(ids)
        selected = selected.intersection(live)
        if let cursor, !live.contains(cursor) { self.cursor = nil }
    }

    /// Where an arrow key moves the cursor: first/last row when there is none yet,
    /// otherwise one step, staying inside the list.
    static func moved(from current: ID?, in ids: [ID], by delta: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return delta >= 0 ? ids.first : ids.last
        }
        return ids[min(max(index + delta, 0), ids.count - 1)]
    }
}
