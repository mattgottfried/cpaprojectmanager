import XCTest
import SwiftData
@testable import CPAManager

final class NextStepTests: XCTestCase {
    private func task(_ title: String, due: Int? = nil, index: Int, done: Bool = false, blockedBy: UUID? = nil) -> NextStepTask {
        NextStepTask(id: UUID(), title: title, dueDate: due.map { Date(timeIntervalSince1970: Double($0) * 86_400) },
                     sortIndex: index, isDone: done, blockedByID: blockedBy)
    }

    func testPicksEarliestDueThenListOrder() {
        let a = task("late", due: 20, index: 0)
        let b = task("soon", due: 10, index: 1)
        let c = task("undated", index: 2)
        XCTAssertEqual(NextStep.pick([a, b, c])?.title, "soon")
        XCTAssertEqual(NextStep.pick([task("x", index: 1), task("y", index: 0)])?.title, "y")
    }

    func testSkipsDoneAndBlockedTasks() {
        let first = task("first", index: 0)
        let second = task("second", due: 1, index: 1, blockedBy: first.id)
        XCTAssertEqual(NextStep.pick([first, second])?.title, "first", "second waits on first")
        var done = first; done.isDone = true
        XCTAssertEqual(NextStep.pick([done, second])?.title, "second", "unblocked once first is done")
        var allDone = second; allDone.isDone = true
        XCTAssertNil(NextStep.pick([done, allDone]))
        XCTAssertNil(NextStep.pick([]))
    }
}

final class ListSelectionTests: XCTestCase {
    func testToggleStartsSelectingAndFinishClears() {
        var s = ListSelection<Int>()
        s.toggle(1); s.toggle(2)
        XCTAssertTrue(s.isSelecting)
        XCTAssertEqual(s.selected, [1, 2])
        s.toggle(1)
        XCTAssertEqual(s.selected, [2])
        s.finish()
        XCTAssertFalse(s.isSelecting)
        XCTAssertTrue(s.selected.isEmpty)
    }

    func testPruneDropsRowsThatDisappeared() {
        var s = ListSelection<Int>()
        s.selectAll([1, 2, 3]); s.cursor = 3
        s.prune(to: [1, 2])
        XCTAssertEqual(s.selected, [1, 2])
        XCTAssertNil(s.cursor)
    }

    func testCursorMovesAndStaysInsideTheList() {
        let ids = [10, 20, 30]
        XCTAssertEqual(ListSelection<Int>.moved(from: nil, in: ids, by: 1), 10, "down from nothing = first")
        XCTAssertEqual(ListSelection<Int>.moved(from: nil, in: ids, by: -1), 30, "up from nothing = last")
        XCTAssertEqual(ListSelection<Int>.moved(from: 10, in: ids, by: 1), 20)
        XCTAssertEqual(ListSelection<Int>.moved(from: 30, in: ids, by: 1), 30, "clamped at the end")
        XCTAssertEqual(ListSelection<Int>.moved(from: 10, in: ids, by: -1), 10, "clamped at the start")
        XCTAssertEqual(ListSelection<Int>.moved(from: 99, in: ids, by: 1), 10, "unknown cursor restarts")
        XCTAssertNil(ListSelection<Int>.moved(from: nil, in: [], by: 1))
    }

    func testAddingTagsNormalizesAndDedupes() {
        XCTAssertEqual(TagSet.adding("#Referral", to: ""), "referral")
        XCTAssertEqual(TagSet.adding("referral", to: "referral, bookkeeping"), "referral, bookkeeping")
        XCTAssertEqual(TagSet.adding("  ", to: "a"), "a")
    }
}

@MainActor
final class BulkActionsTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testBulkCompleteAndSetDueDate() throws {
        let context = try makeContext()
        let a = Project(title: "A", serviceType: .bookkeeping)
        let b = Project(title: "B", serviceType: .bookkeeping)
        context.insert(a); context.insert(b)
        BulkActions.complete([a, b], pipelines: [], context: context)
        XCTAssertTrue(a.status.isComplete && b.status.isComplete)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        BulkActions.setDueDate([a, b], to: due)
        XCTAssertEqual(a.dueDate, due)
        XCTAssertEqual(b.dueDate, due)
    }

    func testBulkTagAndStatus() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        BulkActions.addTag("VIP", to: [client])
        BulkActions.setStatus(.inactive, for: [client])
        XCTAssertEqual(client.tags, ["vip"])
        XCTAssertEqual(client.status, .inactive)
    }

    func testDeleteWithUndoBringsTheClientAndItsWorkBack() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        let project = Project(title: "Return", client: client)
        context.insert(project)
        context.insert(TaskItem(title: "Collect W-2", project: project))
        try context.save()

        let toast = context.deleteWithUndo("Deleted client", includeFiles: true) { context.delete(client) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 0, "cascade removed the task")

        toast.undo?()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 1)
    }

    func testPerformUndoableRevertsAnEdit() throws {
        let context = try makeContext()
        let project = Project(title: "A", serviceType: .bookkeeping)
        context.insert(project)
        try context.save()
        let toast = context.performUndoable("Completed", overwrite: true) {
            BulkActions.complete([project], pipelines: [], context: context)
        }
        XCTAssertTrue(project.status.isComplete)
        toast.undo?()
        XCTAssertFalse(project.status.isComplete)
    }
}
