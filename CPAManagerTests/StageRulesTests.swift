import XCTest
import SwiftData
@testable import CPAManager

private var utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

final class StageConditionTests: XCTestCase {
    func testEachConditionAgainstTheFacts() {
        var facts = JobFacts()
        XCTAssertTrue(StageConditions.isMet(.allTasksDone, facts: facts))
        XCTAssertTrue(StageConditions.isMet(.documentsReceived, facts: facts))
        XCTAssertTrue(StageConditions.isMet(.signaturesComplete, facts: facts))
        XCTAssertFalse(StageConditions.isMet(.invoicePaid, facts: facts), "no invoice yet: not paid")

        facts.openTaskCount = 2; facts.openRequestCount = 1; facts.awaitingSignatureCount = 1
        facts.hasInvoice = true; facts.invoicePaid = false
        for condition in StageCondition.allCases { XCTAssertFalse(StageConditions.isMet(condition, facts: facts), "\(condition)") }
        facts.invoicePaid = true
        XCTAssertTrue(StageConditions.isMet(.invoicePaid, facts: facts))
    }

    func testWaitingSummaryWording() {
        var facts = JobFacts(); facts.hasInvoice = true
        XCTAssertNil(StageConditions.waitingSummary([], facts: facts))
        XCTAssertEqual(StageConditions.waitingSummary([.invoicePaid], facts: facts), "Waiting for the invoice to be paid")
        facts.awaitingSignatureCount = 1
        XCTAssertEqual(StageConditions.waitingSummary([.invoicePaid, .signaturesComplete], facts: facts),
                       "Waiting for the invoice to be paid and a signature")
        facts.openRequestCount = 1
        XCTAssertEqual(StageConditions.waitingSummary([.documentsReceived, .invoicePaid, .signaturesComplete], facts: facts),
                       "Waiting for requested documents, the invoice to be paid and a signature")
        XCTAssertNil(StageConditions.waitingSummary([.allTasksDone], facts: facts), "met conditions aren't listed")
    }
}

final class StageClockTests: XCTestCase {
    func testDaysInStageAndOverTheLimit() {
        let entered = day(2026, 9, 1)
        XCTAssertEqual(StageClock.daysInStage(enteredAt: entered, now: day(2026, 9, 5), calendar: utc), 4)
        XCTAssertEqual(StageClock.daysOver(limitDays: 3, enteredAt: entered, now: day(2026, 9, 5), calendar: utc), 1)
        XCTAssertEqual(StageClock.daysOver(limitDays: 4, enteredAt: entered, now: day(2026, 9, 5), calendar: utc), 0, "right on the limit is still fine")
        XCTAssertFalse(StageClock.isOver(limitDays: nil, enteredAt: entered, now: day(2026, 12, 1), calendar: utc))
        XCTAssertFalse(StageClock.isOver(limitDays: 0, enteredAt: entered, now: day(2026, 12, 1), calendar: utc))
        XCTAssertFalse(StageClock.isOver(limitDays: 3, enteredAt: nil, now: day(2026, 12, 1), calendar: utc), "no clock, no overdue")
        XCTAssertEqual(StageClock.daysInStage(enteredAt: day(2026, 9, 9), now: day(2026, 9, 5), calendar: utc), 0, "never negative")
    }

    func testStampingRules() {
        XCTAssertTrue(StageClock.needsStamp(storedKey: "", currentKey: "inProgress", enteredAt: nil))
        XCTAssertTrue(StageClock.needsStamp(storedKey: "a", currentKey: "b", enteredAt: day(2026, 9, 1)))
        XCTAssertTrue(StageClock.needsStamp(storedKey: "a", currentKey: "a", enteredAt: nil))
        XCTAssertFalse(StageClock.needsStamp(storedKey: "a", currentKey: "a", enteredAt: day(2026, 9, 1)))
    }

    func testSummaryText() {
        let entered = day(2026, 9, 1)
        XCTAssertEqual(StageClock.summary(limitDays: nil, enteredAt: entered, now: day(2026, 9, 2), calendar: utc), "1 day in stage")
        XCTAssertEqual(StageClock.summary(limitDays: 5, enteredAt: entered, now: day(2026, 9, 4), calendar: utc), "3 days in stage · limit 5")
        XCTAssertEqual(StageClock.summary(limitDays: 2, enteredAt: entered, now: day(2026, 9, 4), calendar: utc), "3 days in stage · limit 2 (1 over)")
        XCTAssertNil(StageClock.summary(limitDays: 2, enteredAt: nil, now: day(2026, 9, 4), calendar: utc))
    }
}

final class StageSweepLogicTests: XCTestCase {
    func testNeedsAutomoveAndSomethingToWaitFor() {
        let facts = JobFacts()
        XCTAssertFalse(StageSweep.shouldMove(autoMove: false, stageTasksDone: [true], conditions: [], facts: facts))
        XCTAssertFalse(StageSweep.shouldMove(autoMove: true, stageTasksDone: [], conditions: [], facts: facts), "an empty stage never skips itself")
        XCTAssertTrue(StageSweep.shouldMove(autoMove: true, stageTasksDone: [true, true], conditions: [], facts: facts))
        XCTAssertFalse(StageSweep.shouldMove(autoMove: true, stageTasksDone: [true, false], conditions: [], facts: facts))
    }

    func testConditionsAloneCanDriveAMove() {
        var facts = JobFacts(); facts.hasInvoice = true
        XCTAssertFalse(StageSweep.shouldMove(autoMove: true, stageTasksDone: [], conditions: [.invoicePaid], facts: facts))
        facts.invoicePaid = true
        XCTAssertTrue(StageSweep.shouldMove(autoMove: true, stageTasksDone: [], conditions: [.invoicePaid], facts: facts))
        XCTAssertFalse(StageSweep.shouldMove(autoMove: true, stageTasksDone: [false], conditions: [.invoicePaid], facts: facts), "tasks still gate it")
    }
}

final class StageAutomationCodingTests: XCTestCase {
    func testOlderJSONStillDecodesAndNewFieldsRoundTrip() throws {
        let old = try JSONDecoder().decode(StageAutomation.self, from: Data(#"{"tasks":[],"autoMove":true}"#.utf8))
        XCTAssertNil(old.timeLimitDays)
        XCTAssertEqual(old.conditions, [])

        let full = StageAutomation(tasks: [], setDueInDays: nil, autoMove: true, timeLimitDays: 5, conditions: [.invoicePaid, .documentsReceived])
        let again = try JSONDecoder().decode(StageAutomation.self, from: try JSONEncoder().encode(full))
        XCTAssertEqual(again, full)
        XCTAssertFalse(full.isEmpty)
        XCTAssertFalse(StageAutomation(timeLimitDays: 3).isEmpty)
        XCTAssertFalse(StageAutomation(conditions: [.allTasksDone]).isEmpty)
    }
}

@MainActor
final class StageRulesEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    private func twoStagePipeline(_ first: StageAutomation) -> Pipeline {
        Pipeline(definition: PipelineDefinition(name: "P", stages: [
            PipelineStage(name: "Billing", kind: .notStarted, automation: first),
            PipelineStage(name: "Work", kind: .working, automation: StageAutomation(timeLimitDays: 2)),
            PipelineStage(name: "Done", kind: .done),
        ]))
    }

    func testEnteringAStageStartsItsClockAndAStageChangeRestartsIt() throws {
        let context = try makeContext()
        let pipeline = twoStagePipeline(StageAutomation())
        context.insert(pipeline)
        let job = Project(title: "J")
        context.insert(job)
        PipelineEngine.assign(job, to: pipeline, context: context)
        XCTAssertEqual(job.stageEnteredKey, pipeline.stages[0].id)
        XCTAssertNotNil(job.stageEnteredAt)

        let first = try XCTUnwrap(job.stageEnteredAt)
        let later = first.addingTimeInterval(3 * 86_400)
        XCTAssertTrue(PipelineEngine.advance(job, in: pipeline, context: context))
        // advance() stamps with the real clock; move it back so the test controls time.
        job.stageEnteredAt = first
        StageRules.stamp(job, now: later)
        XCTAssertEqual(job.stageEnteredAt, first, "same stage: the clock keeps running")
        XCTAssertEqual(job.stageEnteredKey, pipeline.stages[1].id)
    }

    func testTimeLimitComesFromTheStageSetup() throws {
        let context = try makeContext()
        let pipeline = twoStagePipeline(StageAutomation())
        context.insert(pipeline)
        let job = Project(title: "J")
        context.insert(job)
        PipelineEngine.assign(job, to: pipeline, context: context)
        XCTAssertNil(StageRules.timeLimit(for: job, pipelines: [pipeline], context: context))
        _ = PipelineEngine.advance(job, in: pipeline, context: context)
        XCTAssertEqual(StageRules.timeLimit(for: job, pipelines: [pipeline], context: context), 2)
    }

    func testReconcileStampsJobsThatNeverHadAClock() throws {
        let context = try makeContext()
        let job = Project(title: "Old job")
        context.insert(job)
        XCTAssertNil(job.stageEnteredAt)
        XCTAssertEqual(StageRules.reconcileAll(context: context), 1)
        XCTAssertNotNil(job.stageEnteredAt)
        XCTAssertEqual(StageRules.reconcileAll(context: context), 0, "idempotent")
    }

    func testSweepMovesAJobWhenItsInvoiceGetsPaid() throws {
        let context = try makeContext()
        let pipeline = twoStagePipeline(StageAutomation(autoMove: true, conditions: [.invoicePaid]))
        context.insert(pipeline)
        let client = Client(name: "Dana")
        context.insert(client)
        let job = Project(title: "J", client: client)
        context.insert(job)
        let invoice = Invoice(number: 1, status: .sent, client: client)
        context.insert(invoice)
        job.invoiceID = invoice.id
        PipelineEngine.assign(job, to: pipeline, context: context)

        XCTAssertEqual(StageRules.sweep(context: context), 0, "still unpaid")
        XCTAssertEqual(job.stageKey, pipeline.stages[0].id)

        invoice.status = .paid
        XCTAssertEqual(StageRules.sweep(context: context), 1)
        XCTAssertEqual(job.stageKey, pipeline.stages[1].id)
        XCTAssertEqual(StageRules.sweep(context: context), 0, "the next stage has no automove")
    }

    func testCompletingTheLastTaskWaitsForConditionsThenTheSweepFinishesTheMove() throws {
        let context = try makeContext()
        let pipeline = twoStagePipeline(StageAutomation(
            tasks: [StageTask(title: "Prep", dueInDays: 1)], autoMove: true, conditions: [.documentsReceived]))
        context.insert(pipeline)
        let client = Client(name: "Dana")
        context.insert(client)
        let job = Project(title: "J", client: client)
        context.insert(job)
        let request = DocumentRequest(title: "W-2", client: client)
        context.insert(request)
        PipelineEngine.assign(job, to: pipeline, context: context)

        let prep = try XCTUnwrap(job.taskList.first { $0.title == "Prep" })
        TaskCompletion.complete(prep, context: context)
        XCTAssertEqual(job.stageKey, pipeline.stages[0].id, "the W-2 hasn't arrived")

        request.markReceived()
        XCTAssertEqual(StageRules.sweep(context: context), 1)
        XCTAssertEqual(job.stageKey, pipeline.stages[1].id)
    }

    func testFactsCountOpenWork() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        let job = Project(title: "J", client: client)
        context.insert(job)
        context.insert(TaskItem(title: "a", project: job))
        let done = TaskItem(title: "b", project: job)
        done.isDone = true
        context.insert(done)
        context.insert(DocumentRequest(title: "W-2", client: client))
        let sent = Document(filename: "Letter", fileExtension: "pdf", data: Data([1]), client: client)
        sent.signatureStatus = .sent
        context.insert(sent)
        try context.save()

        let facts = StageRules.facts(for: job, context: context)
        XCTAssertEqual(facts.openTaskCount, 1)
        XCTAssertEqual(facts.openRequestCount, 1)
        XCTAssertEqual(facts.awaitingSignatureCount, 1)
        XCTAssertFalse(facts.hasInvoice)
    }
}

final class TaskCommentTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ d: Int, hour: Int, minute: Int) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour, minute: minute))!
    }

    func testAddingAppendsADatedEntryAndParsesBack() {
        var notes = ""
        notes = TaskComments.adding("Called the client", to: notes, at: date(30, hour: 14, minute: 5), calendar: utc)
        notes = TaskComments.adding("  Sent the engagement letter ", to: notes, at: date(30, hour: 9, minute: 30), calendar: utc)
        XCTAssertEqual(notes, "[[2026-09-30 14:05]] Called the client\n[[2026-09-30 09:30]] Sent the engagement letter")

        let parsed = TaskComments.parse(notes, calendar: utc)
        XCTAssertEqual(parsed.map(\.text), ["Called the client", "Sent the engagement letter"])
        XCTAssertEqual(parsed.first?.date, date(30, hour: 14, minute: 5))
        XCTAssertEqual(parsed.map(\.id), [0, 1])
    }

    func testBlankCommentChangesNothing() {
        XCTAssertEqual(TaskComments.adding("   ", to: "keep me", calendar: utc), "keep me")
    }

    func testOlderPlainNotesBecomeTheFirstUndatedComment() {
        let notes = TaskComments.adding("New one", to: "Client prefers email\nand mornings", at: date(30, hour: 8, minute: 0), calendar: utc)
        let parsed = TaskComments.parse(notes, calendar: utc)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertNil(parsed[0].date)
        XCTAssertEqual(parsed[0].text, "Client prefers email\nand mornings")
        XCTAssertEqual(parsed[1].text, "New one")
    }

    func testMultilineCommentsStayTogetherAndLookalikesAreNotStamps() {
        let notes = "[[2026-09-30 08:00]] First line\nsecond line\n[[not a stamp]] still the same comment"
        let parsed = TaskComments.parse(notes, calendar: utc)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].text, "First line\nsecond line\n[[not a stamp]] still the same comment")
        XCTAssertEqual(TaskComments.count("", calendar: utc), 0)
    }

    func testTimeTotalsCountRunningEntries() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let total = TaskTime.seconds(
            startedAt: [start, start.addingTimeInterval(7200)],
            endedAt: [start.addingTimeInterval(1800), nil],
            now: start.addingTimeInterval(7200 + 600)
        )
        XCTAssertEqual(total, 1800 + 600)
        XCTAssertEqual(TaskTime.label(seconds: 0), "none yet")
        XCTAssertEqual(TaskTime.label(seconds: 20), "under a minute")
        XCTAssertEqual(TaskTime.label(seconds: 45 * 60), "45 min")
        XCTAssertEqual(TaskTime.label(seconds: 2 * 3600), "2 h")
        XCTAssertEqual(TaskTime.label(seconds: 5400), "1 h 30 min")
    }
}

final class BulkTemplateLogicTests: XCTestCase {
    func testSkipsTitlesAJobAlreadyHasOpen() {
        let indices = BulkTemplate.newStepIndices(
            templateTitles: ["Request documents", "Prepare return", "Review"],
            openTaskTitles: ["request DOCUMENTS ", "Other"]
        )
        XCTAssertEqual(indices, [1, 2])
        XCTAssertEqual(BulkTemplate.newStepIndices(templateTitles: ["A"], openTaskTitles: []), [0])
        XCTAssertEqual(BulkTemplate.newStepIndices(templateTitles: ["A"], openTaskTitles: ["a"]), [])
    }

    func testSummaryWording() {
        XCTAssertEqual(BulkTemplate.summary(jobs: 3, tasks: 9, skippedJobs: 0), "Added 9 tasks to 3 jobs")
        XCTAssertEqual(BulkTemplate.summary(jobs: 1, tasks: 1, skippedJobs: 0), "Added 1 task to 1 job")
        XCTAssertEqual(BulkTemplate.summary(jobs: 2, tasks: 4, skippedJobs: 1), "Added 4 tasks to 2 jobs (1 already had them)")
        XCTAssertEqual(BulkTemplate.summary(jobs: 0, tasks: 0, skippedJobs: 2), "No new tasks added — every job already has them")
    }
}

@MainActor
final class BulkTemplateServiceTests: XCTestCase {
    func testAppliesToManyJobsChainedAndWithoutDuplicates() throws {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = try ModelContainer(for: Persistence.schema, configurations: config).mainContext

        let template = WorkflowTemplate(name: "Setup")
        context.insert(template)
        for (index, title) in ["Request documents", "Prepare"].enumerated() {
            context.insert(TemplateTask(title: title, sortIndex: index, dayOffset: index * 3, template: template))
        }
        let a = Project(title: "A"), b = Project(title: "B")
        context.insert(a); context.insert(b)
        context.insert(TaskItem(title: "request documents", project: b))

        let result = BulkTemplateService.apply(template, to: [a, b], context: context)
        XCTAssertEqual(result.jobs, 2)
        XCTAssertEqual(result.tasks, 3, "A gets both steps, B already had the first")
        XCTAssertEqual(a.taskList.count, 2)
        XCTAssertEqual(b.taskList.count, 2)
        let prepare = try XCTUnwrap(a.taskList.first { $0.title == "Prepare" })
        XCTAssertNotNil(prepare.blockedByID, "the second step waits on the first")
        XCTAssertNil(prepare.dueDate, "and is dated when the first is done")

        let again = BulkTemplateService.apply(template, to: [a, b], context: context)
        XCTAssertEqual(again.tasks, 0, "re-running adds nothing")
        XCTAssertEqual(again.skippedJobs, 2)
    }
}

final class StageReminderLogicTests: XCTestCase {
    func testDefaultsAndOverrides() {
        XCTAssertEqual(StageReminder.effectiveDays(configured: nil, isWaiting: true), 7, "waiting stages remind after a week by default")
        XCTAssertNil(StageReminder.effectiveDays(configured: nil, isWaiting: false))
        XCTAssertEqual(StageReminder.effectiveDays(configured: 3, isWaiting: false), 3)
        XCTAssertEqual(StageReminder.effectiveDays(configured: 14, isWaiting: true), 14)
        XCTAssertNil(StageReminder.effectiveDays(configured: 0, isWaiting: true), "0 switches the default off")
    }

    func testDueOncePerStay() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let entered = utc.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!
        func at(_ day: Int) -> Date { utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 15))! }
        XCTAssertFalse(StageReminder.isDue(days: 7, enteredAt: entered, remindedFor: nil, now: at(7), calendar: utc), "6 days in")
        XCTAssertTrue(StageReminder.isDue(days: 7, enteredAt: entered, remindedFor: nil, now: at(8), calendar: utc), "7 days in")
        XCTAssertFalse(StageReminder.isDue(days: 7, enteredAt: entered, remindedFor: entered, now: at(20), calendar: utc), "already reminded for this stay")
        let reentered = utc.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 9))!
        XCTAssertTrue(StageReminder.isDue(days: 7, enteredAt: reentered, remindedFor: entered, now: at(20), calendar: utc), "a new stay re-arms it")
        XCTAssertFalse(StageReminder.isDue(days: nil, enteredAt: entered, remindedFor: nil, now: at(20), calendar: utc))
        XCTAssertFalse(StageReminder.isDue(days: 7, enteredAt: nil, remindedFor: nil, now: at(20), calendar: utc))
    }

    func testTitles() {
        XCTAssertEqual(StageReminder.title(client: "Dana Lee", job: "2025 Dana Lee 1040", days: 7),
                       "Follow up with Dana Lee: 2025 Dana Lee 1040 has been waiting 7 days")
        XCTAssertEqual(StageReminder.title(client: "", job: "Books", days: 1), "Follow up: Books has been waiting 1 day")
    }
}

@MainActor
final class StageReminderEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testAWaitingStageMakesOneFollowUpTaskAfterAWeek() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineDefinition(name: "P", stages: [
            PipelineStage(name: "Work", kind: .working),
            PipelineStage(name: "Waiting on client", kind: .waiting),
            PipelineStage(name: "Done", kind: .done),
        ]))
        context.insert(pipeline)
        let client = Client(name: "Dana Lee")
        context.insert(client)
        let job = Project(title: "Dana 1040", client: client)
        context.insert(job)
        // Start in the waiting stage explicitly (advance never lands on one).
        PipelineEngine.assign(job, to: pipeline, startStageKey: pipeline.stages[1].id, context: context)
        let entered = Date.now.addingTimeInterval(-8 * 86_400)
        job.stageEnteredAt = entered
        job.stageEnteredKey = pipeline.stages[1].id

        XCTAssertEqual(StageRules.reminderDays(for: job, pipelines: [pipeline], context: context), 7)
        XCTAssertEqual(StageRules.fireReminders(context: context), 1)
        let reminder = try XCTUnwrap(job.taskList.first { $0.title.hasPrefix("Follow up with Dana Lee") })
        XCTAssertNotNil(reminder.dueDate, "due today so it lands on Today")
        XCTAssertEqual(StageRules.fireReminders(context: context), 0, "once per stay")

        // Leaving and re-entering the stage starts a new stay.
        PipelineEngine.enter(job, stage: pipeline.stages[0], context: context)
        PipelineEngine.enter(job, stage: pipeline.stages[1], context: context)
        job.stageEnteredAt = Date.now.addingTimeInterval(-8 * 86_400)
        XCTAssertEqual(StageRules.fireReminders(context: context), 1)
    }

    func testBuiltInWaitingOnClientRemindsByDefaultAndCanBeSwitchedOff() throws {
        let context = try makeContext()
        let job = Project(title: "Books", serviceType: .bookkeeping)
        context.insert(job)
        job.status = .waitingOnClient
        job.stageEnteredKey = job.statusFlow.normalize(job.status).rawValue
        job.stageEnteredAt = Date.now.addingTimeInterval(-9 * 86_400)
        XCTAssertEqual(StageRules.reminderDays(for: job, pipelines: [], context: context), 7)

        BuiltInSetupService.save(StageAutomation(remindAfterDays: 0), service: .bookkeeping,
                                 stageKey: ProjectStatus.waitingOnClient.rawValue, context: context)
        XCTAssertNil(StageRules.reminderDays(for: job, pipelines: [], context: context))
        XCTAssertEqual(StageRules.fireReminders(context: context), 0)
    }

    func testOtherStagesDoNotRemindUnlessAsked() throws {
        let context = try makeContext()
        let job = Project(title: "J")
        context.insert(job)
        job.status = .inProgress
        job.stageEnteredKey = ProjectStatus.inProgress.rawValue
        job.stageEnteredAt = Date.now.addingTimeInterval(-30 * 86_400)
        XCTAssertNil(StageRules.reminderDays(for: job, pipelines: [], context: context))
        XCTAssertEqual(StageRules.fireReminders(context: context), 0)
    }
}
