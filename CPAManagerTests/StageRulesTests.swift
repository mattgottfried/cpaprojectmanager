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
