import XCTest
import SwiftData
@testable import CPAManager

private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 1   // Sunday
    return c
}()
private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}
// Wednesday, September 30, 2026.
private let now = day(2026, 9, 30)

private func row(_ title: String, job: String = "", client: String = "", due: Date? = nil, priority: Priority = .normal,
                 status: TaskStatus = .none, done: Bool = false, blocked: Bool = false, completed: Date? = nil,
                 created: Date = day(2026, 9, 1), stage: String = "", service: String = "") -> TaskTableRow {
    TaskTableRow(id: UUID(), title: title, jobID: job.isEmpty ? nil : UUID(), jobTitle: job,
                 clientID: client.isEmpty ? nil : UUID(), clientName: client, stageName: stage, serviceTypeRaw: service,
                 status: status, priority: priority, dueDate: due, startDate: nil, createdAt: created, completedAt: completed,
                 isDone: done, isBlocked: blocked, subtasksDone: 0, subtasksTotal: 0)
}

final class TaskTableTests: XCTestCase {
    private func titles(_ groups: [TaskGroup]) -> [String] { groups.flatMap(\.rows).map(\.title) }

    func testTabsSplitPendingAndCompleted() {
        let rows = [row("open"), row("done", done: true, completed: now)]
        XCTAssertEqual(titles(TaskTable.apply(rows, tab: .pending, filter: TaskFilter(), sort: TaskSort(), grouping: .none, now: now, calendar: cal)), ["open"])
        XCTAssertEqual(titles(TaskTable.apply(rows, tab: .completed, filter: TaskFilter(), sort: TaskSort(), grouping: .none, now: now, calendar: cal)), ["done"])
    }

    func testDueSortPutsUndatedLastInEitherDirection() {
        let rows = [row("none"), row("late", due: day(2026, 10, 9)), row("soon", due: day(2026, 10, 1))]
        let asc = TaskTable.apply(rows, tab: .pending, filter: TaskFilter(), sort: TaskSort(key: .due, ascending: true), grouping: .none, now: now, calendar: cal)
        XCTAssertEqual(titles(asc), ["soon", "late", "none"])
        let desc = TaskTable.apply(rows, tab: .pending, filter: TaskFilter(), sort: TaskSort(key: .due, ascending: false), grouping: .none, now: now, calendar: cal)
        XCTAssertEqual(titles(desc), ["late", "soon", "none"])
    }

    func testSortByNameStatusAndPriority() {
        let rows = [row("b", priority: .low, status: .onHold), row("a", priority: .high, status: .waitingClient), row("c", priority: .normal)]
        func order(_ key: TaskSortKey, _ ascending: Bool = true) -> [String] {
            titles(TaskTable.apply(rows, tab: .pending, filter: TaskFilter(), sort: TaskSort(key: key, ascending: ascending), grouping: .none, now: now, calendar: cal))
        }
        XCTAssertEqual(order(.name), ["a", "b", "c"])
        XCTAssertEqual(order(.name, false), ["c", "b", "a"])
        XCTAssertEqual(order(.priority), ["a", "c", "b"], "high first when ascending")
        XCTAssertEqual(order(.status), ["c", "b", "a"], "No status, On hold, Waiting for client")
    }

    func testFilters() {
        let client = UUID()
        var mine = row("mine", job: "Return", client: "Dana", due: day(2026, 9, 28), priority: .high, status: .waitingClient, stage: "Review", service: "taxReturn")
        mine.clientID = client
        let rows = [mine, row("other", due: day(2026, 10, 30)), row("blocked", blocked: true)]
        func count(_ f: TaskFilter) -> Int {
            TaskTable.apply(rows, tab: .pending, filter: f, sort: TaskSort(), grouping: .none, now: now, calendar: cal).flatMap(\.rows).count
        }
        XCTAssertEqual(count(TaskFilter()), 3)
        XCTAssertEqual(count(TaskFilter(clientID: client)), 1)
        XCTAssertEqual(count(TaskFilter(serviceTypeRaw: "taxReturn")), 1)
        XCTAssertEqual(count(TaskFilter(stageName: "Review")), 1)
        XCTAssertEqual(count(TaskFilter(priority: .high)), 1)
        XCTAssertEqual(count(TaskFilter(status: .waitingClient)), 1)
        XCTAssertEqual(count(TaskFilter(due: .overdue)), 1)
        XCTAssertEqual(count(TaskFilter(due: .noDate)), 1)
        XCTAssertEqual(count(TaskFilter(hideBlocked: true)), 2)
        XCTAssertEqual(count(TaskFilter(search: "dana")), 1, "search matches the client name")
        XCTAssertEqual(count(TaskFilter(search: "RETURN")), 1, "and the job, case-insensitively")
        XCTAssertEqual(TaskFilter(priority: .high, hideBlocked: true).activeCount, 2)
        XCTAssertTrue(TaskFilter().isEmpty)
    }

    func testDueRangesAndBuckets() {
        // Week of Sun Sep 27 – Sat Oct 3.
        XCTAssertTrue(TaskDueRange.thisWeek.matches(day(2026, 10, 3), now: now, calendar: cal))
        XCTAssertFalse(TaskDueRange.thisWeek.matches(day(2026, 10, 4), now: now, calendar: cal))
        XCTAssertTrue(TaskDueRange.next7.matches(day(2026, 10, 6), now: now, calendar: cal))
        XCTAssertFalse(TaskDueRange.next7.matches(day(2026, 10, 7), now: now, calendar: cal))
        XCTAssertEqual(TaskDueBucket.bucket(for: day(2026, 9, 29), now: now, calendar: cal), .overdue)
        XCTAssertEqual(TaskDueBucket.bucket(for: day(2026, 9, 30, hour: 23), now: now, calendar: cal), .today)
        XCTAssertEqual(TaskDueBucket.bucket(for: day(2026, 10, 1), now: now, calendar: cal), .tomorrow)
        XCTAssertEqual(TaskDueBucket.bucket(for: day(2026, 10, 2), now: now, calendar: cal), .thisWeek)
        XCTAssertEqual(TaskDueBucket.bucket(for: day(2026, 10, 12), now: now, calendar: cal), .later)
        XCTAssertEqual(TaskDueBucket.bucket(for: nil, now: now, calendar: cal), .none)
    }

    func testGroupingInMeaningfulOrder() {
        let rows = [row("later", due: day(2026, 11, 1)), row("over", due: day(2026, 9, 1)), row("none"), row("today", due: now)]
        let groups = TaskTable.apply(rows, tab: .pending, filter: TaskFilter(), sort: TaskSort(), grouping: .due, now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.title), ["Overdue", "Today", "Later", "No due date"])

        let byClient = TaskTable.apply([row("x", client: "Zed"), row("y", client: "Amy"), row("z")], tab: .pending, filter: TaskFilter(),
                                       sort: TaskSort(), grouping: .client, now: now, calendar: cal)
        XCTAssertEqual(byClient.map(\.title), ["Amy", "Zed", "No client"])

        let byPriority = TaskTable.apply([row("l", priority: .low), row("h", priority: .high)], tab: .pending, filter: TaskFilter(),
                                         sort: TaskSort(), grouping: .priority, now: now, calendar: cal)
        XCTAssertEqual(byPriority.map(\.title), ["High", "Low"])
        XCTAssertTrue(TaskTable.apply([], tab: .pending, filter: TaskFilter(), sort: TaskSort(), grouping: .none, now: now, calendar: cal).isEmpty)
    }

    func testPresetsRoundTripAndReplaceBySameName() {
        var saved = TaskPresets.saving("  My view ", filter: TaskFilter(priority: .high), sort: TaskSort(key: .name, ascending: false), grouping: .client, to: [])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].name, "My view")
        saved = TaskPresets.saving("my VIEW", filter: TaskFilter(status: .onHold), sort: TaskSort(), grouping: .none, to: saved)
        XCTAssertEqual(saved.count, 1, "same name replaces")
        XCTAssertEqual(saved[0].filter.status, .onHold)
        XCTAssertEqual(TaskPresets.saving("  ", filter: TaskFilter(), sort: TaskSort(), grouping: .none, to: saved).count, 1, "blank names are ignored")

        let decoded = TaskPresets.decode(TaskPresets.encode(saved))
        XCTAssertEqual(decoded, saved)
        XCTAssertTrue(TaskPresets.decode("").isEmpty)
        XCTAssertTrue(TaskPresets.decode("not json").isEmpty)
        XCTAssertFalse(TaskPresets.builtIn.isEmpty)
    }

    func testBoardHasAColumnPerStatusAndCalendarCountsDays() {
        let rows = [row("a", due: day(2026, 10, 1), status: .waitingClient), row("b", due: day(2026, 9, 1)), row("c", due: day(2026, 10, 1))]
        let columns = TaskBoard.columns(rows)
        XCTAssertEqual(columns.count, TaskStatus.allCases.count)
        XCTAssertEqual(columns.first { $0.status == .none }?.rows.map(\.title), ["b", "c"], "by due date")
        XCTAssertEqual(columns.first { $0.status == .waitingClient }?.rows.count, 1)

        let grid = TaskCalendar.monthGrid(for: day(2026, 10, 1), rows: rows, jobDueDates: [day(2026, 10, 1)], now: now, calendar: cal)
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(grid.first?.date, day(2026, 9, 27, hour: 0), "starts on the Sunday before the 1st (a Thursday)")
        let oct1 = grid.first { cal.isDate($0.date, inSameDayAs: day(2026, 10, 1)) }
        XCTAssertEqual(oct1?.taskCount, 2)
        XCTAssertEqual(oct1?.jobDueCount, 1)
        XCTAssertEqual(oct1?.inMonth, true)
        XCTAssertEqual(grid.first { cal.isDate($0.date, inSameDayAs: day(2026, 9, 1)) }?.overdueCount, nil, "September 1 isn't in this grid")
        XCTAssertEqual(TaskCalendar.rows(on: day(2026, 10, 1), from: rows, calendar: cal).count, 2)
    }
}

final class InsightsLogicTests: XCTestCase {
    private func job(_ title: String, stage: String = "In progress", order: Int = 1, service: String = "taxReturn", due: Date? = nil,
                     complete: Bool = false, inProgress: Bool = true, activity: Date = day(2026, 9, 29)) -> InsightsJob {
        InsightsJob(id: UUID(), title: title, clientName: "Dana", serviceTypeRaw: service, stageName: stage, stageOrder: order,
                    isComplete: complete, isInProgress: inProgress, dueDate: due, lastActivity: activity)
    }

    func testApproachingMeansDueOnThatExactDay() {
        let jobs = [job("today", due: now), job("tomorrow", due: day(2026, 10, 1)), job("week", due: day(2026, 10, 7)),
                    job("done", due: now, complete: true)]
        XCTAssertEqual(JobInsights.approaching(jobs, on: .today, now: now, calendar: cal).map(\.title), ["today"])
        XCTAssertEqual(JobInsights.approaching(jobs, on: .tomorrow, now: now, calendar: cal).map(\.title), ["tomorrow"])
        XCTAssertEqual(JobInsights.approaching(jobs, on: .inAWeek, now: now, calendar: cal).map(\.title), ["week"])
        XCTAssertTrue(JobInsights.approaching(jobs, on: .dayAfter, now: now, calendar: cal).isEmpty)
    }

    func testOverdueNoActivityAndInProgress() {
        let jobs = [job("late", due: day(2026, 9, 1)), job("fine", due: day(2026, 12, 1)), job("quiet", activity: day(2026, 9, 1)),
                    job("new", inProgress: false), job("done", due: day(2026, 9, 1), complete: true, activity: day(2026, 1, 1))]
        XCTAssertEqual(JobInsights.overdue(jobs, now: now, calendar: cal).map(\.title), ["late"])
        XCTAssertEqual(JobInsights.noActivity(jobs, overDays: 7, now: now, calendar: cal).map(\.title), ["quiet"])
        XCTAssertEqual(JobInsights.inProgress(jobs).map(\.title), ["fine", "late", "quiet"])
    }

    func testJobsByStageCountsOpenJobsInPipelineOrder() {
        let jobs = [job("a", stage: "Review", order: 2), job("b", stage: "Prepare", order: 1), job("c", stage: "Prepare", order: 1),
                    job("d", stage: "Review", order: 2, complete: true), job("e", stage: "Start", order: 0, service: "bookkeeping")]
        let counts = JobInsights.byStage(jobs)
        XCTAssertEqual(counts.map(\.stageName), ["Start", "Prepare", "Review"], "services sort by name: bookkeeping before taxReturn")
        XCTAssertEqual(counts.map(\.count), [1, 2, 1])
    }

    func testTasksToDoOnADayAndByPriority() {
        let rows = [row("today", due: now, priority: .high), row("over", due: day(2026, 9, 20)), row("tomorrow", due: day(2026, 10, 1)),
                    row("waiting", due: now, blocked: true), row("done", due: now, done: true)]
        XCTAssertEqual(TaskInsights.toDo(rows, on: now, now: now, calendar: cal).map(\.title), ["over", "today"], "today includes overdue")
        XCTAssertEqual(TaskInsights.toDo(rows, on: day(2026, 10, 1), now: now, calendar: cal).map(\.title), ["tomorrow"], "other days don't")
        let groups = TaskInsights.byPriority(TaskInsights.toDo(rows, on: now, now: now, calendar: cal))
        XCTAssertEqual(groups.map(\.priority), [.high, .normal])
    }

    func testWeeklyPlannedVsDoneAndRate() {
        let rows = [row("a", due: day(2026, 9, 30), done: true, completed: day(2026, 9, 29)),
                    row("b", due: day(2026, 9, 29)),
                    row("c", due: day(2026, 9, 22), done: true, completed: day(2026, 9, 23)),
                    row("d", due: day(2026, 9, 23), done: true, completed: day(2026, 9, 25))]
        let points = TaskInsights.weekly(rows, weeks: 2, now: now, calendar: cal)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].planned, 2)   // this week: a, b
        XCTAssertEqual(points[1].done, 1)
        XCTAssertEqual(points[0].planned, 2)   // last week: c, d
        XCTAssertEqual(points[0].done, 2)
        XCTAssertEqual(TaskInsights.completionRate(points) ?? 0, 0.75, accuracy: 0.001)
        XCTAssertNil(TaskInsights.completionRate([]))
    }

    func testWidgetLayoutDefaultsHidesAndKeepsNewOnesOff() {
        XCTAssertEqual(InsightsLayout.visible(from: "").count, InsightsWidget.allCases.count)
        XCTAssertEqual(InsightsLayout.visible(from: "jobs,tasksToDo"), [.jobs, .tasksToDo])
        XCTAssertTrue(InsightsLayout.visible(from: "-").isEmpty)
        var slots = InsightsLayout.slots(from: "jobs")
        XCTAssertEqual(slots.count, InsightsWidget.allCases.count)
        XCTAssertFalse(slots.last?.isVisible ?? true, "widgets not in the saved list come back hidden")
        slots[1].isVisible = true
        XCTAssertEqual(InsightsLayout.encode(slots), "jobs,\(slots[1].widget.rawValue)")
        XCTAssertEqual(InsightsLayout.encode(slots.map { InsightsSlot(widget: $0.widget, isVisible: false) }), "-")
        XCTAssertEqual(InsightsLayout.visible(from: "jobs,bogus,jobs"), [.jobs])
    }
}

final class StageAutoMoveLogicTests: XCTestCase {
    func testMovesOnlyWhenTheCurrentStagesTasksAreAllDone() {
        XCTAssertTrue(StageAutoMove.shouldMove(autoMove: true, completedTaskStageKey: "s", currentStageKey: "s", stageTasksDone: [true, true]))
        XCTAssertFalse(StageAutoMove.shouldMove(autoMove: true, completedTaskStageKey: "s", currentStageKey: "s", stageTasksDone: [true, false]))
        XCTAssertFalse(StageAutoMove.shouldMove(autoMove: false, completedTaskStageKey: "s", currentStageKey: "s", stageTasksDone: [true]))
        XCTAssertFalse(StageAutoMove.shouldMove(autoMove: true, completedTaskStageKey: "old", currentStageKey: "s", stageTasksDone: [true]), "a finished task from an earlier stage doesn't move the job")
        XCTAssertFalse(StageAutoMove.shouldMove(autoMove: true, completedTaskStageKey: "", currentStageKey: "", stageTasksDone: [true]), "tasks not made by a stage never trigger it")
        XCTAssertFalse(StageAutoMove.shouldMove(autoMove: true, completedTaskStageKey: "s", currentStageKey: "s", stageTasksDone: []))
    }

    func testStageAutomationDecodesOldJSONAndCountsAutomoveAsSetup() throws {
        let old = Data(#"{"tasks":[{"id":"\#(UUID().uuidString)","title":"A","dueInDays":2}],"setDueInDays":5}"#.utf8)
        let decoded = try JSONDecoder().decode(StageAutomation.self, from: old)
        XCTAssertEqual(decoded.tasks.map(\.title), ["A"])
        XCTAssertEqual(decoded.setDueInDays, 5)
        XCTAssertFalse(decoded.autoMove)
        XCTAssertEqual(try JSONDecoder().decode(StageAutomation.self, from: Data("{}".utf8)), StageAutomation())
        var withMove = StageAutomation()
        withMove.autoMove = true
        XCTAssertFalse(withMove.isEmpty, "a stage with only automove on is still a setup")
        XCTAssertEqual(try JSONDecoder().decode(StageAutomation.self, from: JSONEncoder().encode(withMove)), withMove)
        XCTAssertEqual(BuiltInSetup.summary(withMove), "automove")
    }
}

@MainActor
final class StageAutoMoveEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    private func stageAutomation(_ titles: [String], autoMove: Bool) -> StageAutomation {
        StageAutomation(tasks: titles.map { StageTask(title: $0, dueInDays: 1) }, setDueInDays: nil, autoMove: autoMove)
    }

    func testCustomPipelineJobMovesOnWhenTheStagesLastTaskIsDone() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineDefinition(name: "P", stages: [
            PipelineStage(name: "One", kind: .notStarted, automation: stageAutomation(["A", "B"], autoMove: true)),
            PipelineStage(name: "Two", kind: .working, automation: stageAutomation(["C"], autoMove: false)),
            PipelineStage(name: "Done", kind: .done),
        ]))
        context.insert(pipeline)
        let job = Project(title: "J")
        context.insert(job)
        PipelineEngine.assign(job, to: pipeline, context: context)
        XCTAssertEqual(job.stageKey, pipeline.stages[0].id)

        let a = try XCTUnwrap(job.taskList.first { $0.title == "A" })
        let b = try XCTUnwrap(job.taskList.first { $0.title == "B" })
        XCTAssertEqual(a.stageKey, pipeline.stages[0].id)

        TaskCompletion.complete(a, context: context)
        XCTAssertEqual(job.stageKey, pipeline.stages[0].id, "B is still open")
        TaskCompletion.complete(b, context: context)
        XCTAssertEqual(job.stageKey, pipeline.stages[1].id, "all of stage one's tasks are done: moved on")
        XCTAssertEqual(job.taskList.filter { $0.title == "C" }.count, 1, "and stage two's tasks were created")
    }

    func testOffByDefaultAndOldStageTasksDoNotMoveTheJob() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineDefinition(name: "P", stages: [
            PipelineStage(name: "One", kind: .notStarted, automation: stageAutomation(["A"], autoMove: false)),
            PipelineStage(name: "Two", kind: .working, automation: stageAutomation(["B"], autoMove: true)),
            PipelineStage(name: "Three", kind: .review),
            PipelineStage(name: "Done", kind: .done),
        ]))
        context.insert(pipeline)
        let job = Project(title: "J")
        context.insert(job)
        PipelineEngine.assign(job, to: pipeline, context: context)
        let a = try XCTUnwrap(job.taskList.first { $0.title == "A" })

        TaskCompletion.complete(a, context: context)
        XCTAssertEqual(job.stageKey, pipeline.stages[0].id, "automove is off for stage one")

        PipelineEngine.advanceAny(job, pipelines: [pipeline], context: context)   // by hand to stage two
        XCTAssertEqual(job.stageKey, pipeline.stages[1].id)
        TaskCompletion.undo(a, spawned: nil, context: context)
        TaskCompletion.complete(a, context: context)   // an old stage's task again
        XCTAssertEqual(job.stageKey, pipeline.stages[1].id, "a task from an earlier stage doesn't trigger stage two")
    }

    func testBuiltInPipelineAutomove() throws {
        let context = try makeContext()
        BuiltInSetupService.save(stageAutomation(["Collect books"], autoMove: true), service: .bookkeeping,
                                 stageKey: ProjectStatus.notStarted.rawValue, context: context)
        BuiltInSetupService.save(stageAutomation(["Reconcile"], autoMove: false), service: .bookkeeping,
                                 stageKey: ProjectStatus.inProgress.rawValue, context: context)
        let job = Project(title: "Books", serviceType: .bookkeeping)
        context.insert(job)
        PipelineEngine.applyDefault(to: job, context: context, defaults: UserDefaults(suiteName: "test-\(UUID())")!)

        let first = try XCTUnwrap(job.taskList.first)
        XCTAssertEqual(first.stageKey, ProjectStatus.notStarted.rawValue)
        TaskCompletion.complete(first, context: context)   // the last task of the stage: the job moves on by itself
        XCTAssertEqual(job.status, .inProgress)
        XCTAssertEqual(job.taskList.map(\.title), ["Collect books", "Reconcile"])
        let reconcile = try XCTUnwrap(job.taskList.last)
        TaskCompletion.complete(reconcile, context: context)
        XCTAssertEqual(job.status, .inProgress, "automove is off for the In Progress stage")
    }

    func testStageKeyAndPriorityAndStatusSurviveBackup() throws {
        let context = try makeContext()
        let task = TaskItem(title: "T")
        task.stageKey = "abc"; task.priority = .high; task.status = .waitingAgency; task.startDate = day(2026, 9, 1)
        context.insert(task)
        let file = BackupService.export(context: context)
        XCTAssertEqual(file.tasks.first?.stageKey, "abc")
        let target = try makeContext()
        BackupService.restore(file, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<TaskItem>()).first)
        XCTAssertEqual(restored.stageKey, "abc")
        XCTAssertEqual(restored.priority, .high)
        XCTAssertEqual(restored.status, .waitingAgency)
        XCTAssertEqual(restored.startDate, day(2026, 9, 1))
    }
}

@MainActor
final class TaskTableServiceTests: XCTestCase {
    func testRowsResolveJobClientBlockedAndSubtasks() throws {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = try ModelContainer(for: Persistence.schema, configurations: config).mainContext
        let client = Client(name: "Dana")
        context.insert(client)
        let job = Project(title: "Return", client: client)
        context.insert(job)
        let first = TaskItem(title: "First", project: job)
        let second = TaskItem(title: "Second", project: job)
        second.blockedByID = first.id
        second.checklist = "- [x] one\n- [ ] two"
        context.insert(first); context.insert(second)

        let rows = TaskTableService.rows(tasks: [first, second], pipelines: [])
        let r2 = try XCTUnwrap(rows.first { $0.title == "Second" })
        XCTAssertTrue(r2.isBlocked)
        XCTAssertEqual(r2.clientName, "Dana", "the client comes from the job")
        XCTAssertEqual(r2.jobTitle, "Return")
        XCTAssertEqual(r2.subtasksDone, 1)
        XCTAssertEqual(r2.subtasksTotal, 2)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.title == "First" }).isBlocked)

        let csv = TaskTableService.csv(rows)
        XCTAssertTrue(csv.hasPrefix("Task,Job,Client,Stage,Status,Priority,Due,Start,Created,Completed,Subtasks"))
        XCTAssertTrue(csv.contains("1/2"))
    }

    func testBulkTaskActions() throws {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = try ModelContainer(for: Persistence.schema, configurations: config).mainContext
        let a = TaskItem(title: "A"), b = TaskItem(title: "B")
        context.insert(a); context.insert(b)
        BulkActions.setPriority(.high, for: [a, b])
        BulkActions.setStatus(.onHold, for: [a, b])
        BulkActions.setDueDate([a], to: day(2026, 10, 10))
        BulkActions.complete([b], context: context)
        XCTAssertEqual(a.priority, .high)
        XCTAssertEqual(b.status, .onHold)
        XCTAssertEqual(a.dueDate, day(2026, 10, 10))
        XCTAssertTrue(b.isDone)
        XCTAssertFalse(a.isDone)
    }
}
