import XCTest
import SwiftData
@testable import CPAManager

final class PipelineLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testEveryServiceHasItsOwnBuiltInPipeline() {
        var names: Set<String> = []
        for service in ServiceType.allCases {
            let definition = PipelineDefinition.builtIn(for: service)
            let flow = StatusFlow.flow(for: service)
            names.insert(definition.name)
            XCTAssertEqual(definition.name, service.label)
            XCTAssertEqual(definition.stages.map { $0.id }, flow.statuses.map { $0.rawValue })
            XCTAssertEqual(definition.stages.map { $0.name }, flow.statuses.map { flow.label($0) })
            XCTAssertEqual(definition.firstStage?.id, ProjectStatus.notStarted.rawValue)
            XCTAssertEqual(definition.stages.last?.kind, .done)
            XCTAssertEqual(Set(definition.stages.map { $0.id }).count, definition.stages.count)
            XCTAssertFalse(definition.boardStages.contains { $0.id == ProjectStatus.complete.rawValue })
        }
        XCTAssertEqual(names.count, ServiceType.allCases.count, "one distinct pipeline per service")
        XCTAssertEqual(PipelineDefinition.standard, PipelineDefinition.builtIn(for: .taxReturn))
    }

    func testEveryKindMapsToALegacyStatusAndOnlyDoneIsComplete() {
        for kind in StageKind.allCases {
            XCTAssertEqual(kind.legacyStatus.isComplete, kind == .done, kind.rawValue)
        }
    }

    func testNextStageWalksForwardAndStopsAtTheEnd() {
        let pipeline = PipelineStarters.bookkeeping
        let first = pipeline.stages[0]
        XCTAssertEqual(pipeline.next(after: first.id)?.name, "Reconciling")
        XCTAssertNil(pipeline.next(after: pipeline.stages.last!.id))
        XCTAssertNil(pipeline.next(after: "no-such-stage"))
    }

    func testValidation() {
        XCTAssertTrue(PipelineDefinition(name: "Ok", stages: [
            PipelineStage(name: "A", kind: .working), PipelineStage(name: "Done", kind: .done),
        ]).validationErrors().isEmpty)

        let bad = PipelineDefinition(name: " ", stages: [PipelineStage(name: "A", kind: .working)])
        let errors = bad.validationErrors()
        XCTAssertTrue(errors.contains("Give the pipeline a name."))
        XCTAssertTrue(errors.contains("Add at least two stages."))
        XCTAssertTrue(errors.contains("Add a Done stage so finished jobs leave the board."))

        let dupes = PipelineDefinition(name: "X", stages: [
            PipelineStage(name: "Same", kind: .working), PipelineStage(name: " same ", kind: .done),
        ])
        XCTAssertTrue(dupes.validationErrors().contains("Stage names must be different."))

        let blank = PipelineDefinition(name: "X", stages: [
            PipelineStage(name: "", kind: .working), PipelineStage(name: "Done", kind: .done),
        ])
        XCTAssertTrue(blank.validationErrors().contains("Every stage needs a name."))
    }

    func testEveryStarterPipelineIsValid() {
        for starter in PipelineStarters.all {
            XCTAssertTrue(starter.validationErrors().isEmpty, "\(starter.name): \(starter.validationErrors())")
        }
        XCTAssertEqual(PipelineStarters.all.count, 4)
    }

    func testEnteringAStagePlansTasksDueDateAndStatus() {
        let stage = PipelineStage(name: "Docs", kind: .waiting, automation: StageAutomation(
            tasks: [StageTask(title: "Collect IDs", dueInDays: 3), StageTask(title: "  ", dueInDays: 1)],
            setDueInDays: 14
        ))
        let plan = PipelineMove.plan(entering: stage, now: date(2026, 9, 30, hour: 15), calendar: calendar)
        XCTAssertEqual(plan.status, .awaitingDocs)
        XCTAssertFalse(plan.isDone)
        XCTAssertEqual(plan.dueDate, date(2026, 10, 14))
        XCTAssertEqual(plan.tasks, [PipelineMove.NewTask(title: "Collect IDs", dueDate: date(2026, 10, 3))], "blank task titles are skipped")
    }

    func testDoneStageCompletesAndLeavesDueDateAlone() {
        let plan = PipelineMove.plan(entering: PipelineStage(name: "Done", kind: .done), now: date(2026, 9, 30), calendar: calendar)
        XCTAssertTrue(plan.isDone)
        XCTAssertEqual(plan.status, .complete)
        XCTAssertNil(plan.dueDate)
        XCTAssertTrue(plan.tasks.isEmpty)
    }

    func testStageInfoResolution() {
        let custom = PipelineStarters.onboarding
        let stage = custom.stages[1]
        let info = PipelineResolver.info(definition: custom, stageKey: stage.id, status: .awaitingDocs)
        XCTAssertEqual(info.name, "Documents & setup")
        XCTAssertEqual(info.color, .orange)

        // Built-in pipeline: the status is the stage (a tax return's Awaiting Signature).
        let standard = PipelineResolver.info(definition: nil, stageKey: "", status: .awaitingSignature)
        XCTAssertEqual(standard.name, "Awaiting Signature")
        XCTAssertEqual(standard.color, .yellow)
        // Out-of-flow statuses read as the stage they map to; general work says "Waiting on Client".
        XCTAssertEqual(PipelineResolver.info(definition: nil, stageKey: "", status: .review).name, "In Progress")
        XCTAssertEqual(PipelineResolver.info(definition: nil, stageKey: "", status: .waitingOnClient, flow: .general).name, "Waiting on Client")
        XCTAssertEqual(PipelineResolver.info(definition: nil, stageKey: "", status: .waitingOnClient, flow: .taxReturn).name, "On Hold")

        // A custom stage that no longer exists falls back to the coarse status.
        let orphan = PipelineResolver.info(definition: custom, stageKey: "deleted", status: .inProgress)
        XCTAssertEqual(orphan.name, ProjectStatus.inProgress.label)

        XCTAssertTrue(PipelineResolver.info(definition: nil, stageKey: "", status: .complete).isDone)
    }

    func testStagesSurviveJSONRoundTrip() throws {
        let original = PipelineStarters.onboarding.stages
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([PipelineStage].self, from: data), original)
    }
}

final class RecurringLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testDefaultTitleMatchesTheOriginalConvention() {
        // A monthly close due 6/27/2026 covers May → "MM/yyyy" of the period.
        let title = RecurringNaming.title(pattern: "", name: "Acme Bookkeeping", clientName: "Acme", frequency: .monthly, due: date(2026, 6, 27), calendar: calendar)
        XCTAssertEqual(title, "Acme Bookkeeping - 05/2026")
        XCTAssertEqual(RecurringNaming.title(pattern: "", name: "Estimates", clientName: "Dana", frequency: .annually, due: date(2026, 4, 15), calendar: calendar), "Estimates - 2025")
    }

    func testCustomPatternTokens() {
        let title = RecurringNaming.title(
            pattern: "{client} {month} {year} close ({quarter}) due {due}",
            name: "Books", clientName: "Acme LLC", frequency: .monthly, due: date(2026, 6, 27), calendar: calendar
        )
        XCTAssertEqual(title, "Acme LLC May 2026 close (Q2) due Jun 27, 2026")
        XCTAssertEqual(
            RecurringNaming.title(pattern: "{CLIENT} – {monthnum}", name: "x", clientName: "Zed", frequency: .monthly, due: date(2026, 1, 15), calendar: calendar),
            "Zed – 12"
        )
    }

    func testPreviewFollowsGeneratorSteppingAndWeekendSkip() {
        let dates = RecurrencePreview.dates(startingAt: date(2026, 10, 30), frequency: .monthly, count: 3, adjustForWeekends: false, calendar: calendar)
        XCTAssertEqual(dates, [date(2026, 10, 30), date(2026, 11, 30), date(2026, 12, 30)].map { calendar.startOfDay(for: $0) })

        // 2026-11-01 is a Sunday → moves per DateMath.skippingWeekend.
        let adjusted = RecurrencePreview.dates(startingAt: date(2026, 10, 1), frequency: .monthly, count: 2, adjustForWeekends: true, calendar: calendar)
        XCTAssertEqual(adjusted.count, 2)
        XCTAssertNotEqual(calendar.component(.weekday, from: adjusted[1]), 1)
        XCTAssertNotEqual(calendar.component(.weekday, from: adjusted[1]), 7)
    }

    func testPreviewStopsAtTheEndDate() {
        let dates = RecurrencePreview.dates(startingAt: date(2026, 1, 15), frequency: .monthly, count: 12, adjustForWeekends: false, endDate: date(2026, 3, 20), calendar: calendar)
        XCTAssertEqual(dates.count, 3)
    }

    func testHasEnded() {
        XCTAssertFalse(RecurringPreviewHelper.ended(next: date(2026, 3, 15), end: nil, calendar: calendar))
        XCTAssertFalse(RecurringPreviewHelper.ended(next: date(2026, 3, 15), end: date(2026, 3, 15), calendar: calendar))
        XCTAssertTrue(RecurringPreviewHelper.ended(next: date(2026, 3, 16), end: date(2026, 3, 15), calendar: calendar))
    }
}

/// Thin wrapper so the test reads naturally.
private enum RecurringPreviewHelper {
    static func ended(next: Date, end: Date?, calendar: Calendar) -> Bool {
        RecurrencePreview.hasEnded(nextDue: next, endDate: end, calendar: calendar)
    }
}

@MainActor
final class PipelineEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testAssignEntersFirstStageAndRunsAutomation() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.onboarding)
        context.insert(pipeline)
        let project = Project(title: "Onboard Dana")
        context.insert(project)

        PipelineEngine.assign(project, to: pipeline, context: context)

        XCTAssertEqual(project.pipelineID, pipeline.id)
        XCTAssertEqual(project.stageKey, pipeline.stages[0].id)
        XCTAssertEqual(project.status, .inProgress)
        XCTAssertNotNil(project.dueDate, "the Engagement letter stage resets the due date")
        XCTAssertEqual(project.taskList.map { $0.title }, ["Send engagement letter"])
    }

    func testAdvanceMovesThroughStagesCompletesAtTheEndAndDoesNotDuplicateTasks() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.bookkeeping)
        context.insert(pipeline)
        let project = Project(title: "Acme 09/2026")
        context.insert(project)
        PipelineEngine.assign(project, to: pipeline, context: context)
        XCTAssertEqual(project.taskList.count, 1)   // "Request bank and card statements"

        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))   // Reconciling
        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))   // Review
        XCTAssertEqual(project.taskList.count, 2)
        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))   // Delivered
        XCTAssertTrue(project.status.isComplete)
        XCTAssertNotNil(project.completedAt)
        XCTAssertFalse(PipelineEngine.advance(project, in: pipeline, context: context), "nothing after the last stage")

        // Re-entering a stage with an open automation task doesn't duplicate it.
        let review = try XCTUnwrap(pipeline.stages.first { $0.name == "Review" })
        PipelineEngine.enter(project, stage: review, context: context)
        PipelineEngine.enter(project, stage: review, context: context)
        XCTAssertEqual(project.taskList.filter { $0.title == "Send reports to client" }.count, 1)
    }

    func testAssigningToTheBuiltInPipelineKeepsStatus() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.payroll)
        context.insert(pipeline)
        let project = Project(title: "Payroll")
        context.insert(project)
        PipelineEngine.assign(project, to: pipeline, context: context)
        let status = project.status
        PipelineEngine.assign(project, to: nil, context: context)
        XCTAssertNil(project.pipelineID)
        XCTAssertEqual(project.stageKey, "")
        XCTAssertEqual(project.status, status)
    }

    func testTemplateWithAPipelineStartsJobsThere() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.bookkeeping)
        context.insert(pipeline)
        let template = WorkflowTemplate(name: "Monthly close", detail: "")
        template.pipelineID = pipeline.id
        template.startStageKey = pipeline.stages[1].id     // start at "Reconciling"
        context.insert(template)

        let project = WorkflowEngine.instantiate(template: template, for: nil, into: context)
        XCTAssertEqual(project.pipelineID, pipeline.id)
        XCTAssertEqual(project.stageKey, pipeline.stages[1].id)
    }

    func testStageInfoForAProjectUsesItsPipeline() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.irsNotice)
        context.insert(pipeline)
        let project = Project(title: "Notice CP2000")
        context.insert(project)
        PipelineEngine.assign(project, to: pipeline, context: context)
        XCTAssertEqual(PipelineEngine.info(for: project, in: [pipeline]).name, "Notice received")
        XCTAssertEqual(PipelineEngine.info(for: project, in: []).name, ProjectStatus.notStarted.label, "missing pipeline falls back")
    }

    // MARK: Waiting stages are manual

    func testAdvanceSkipsWaitingStagesButTheyCanBeChosen() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.bookkeeping)   // Not started, Reconciling, Waiting, Review, Delivered
        context.insert(pipeline)
        let project = Project(title: "Acme")
        context.insert(project)
        PipelineEngine.assign(project, to: pipeline, context: context)
        let waiting = try XCTUnwrap(pipeline.stages.first { $0.kind == .waiting })

        XCTAssertNotEqual(project.stageKey, waiting.id)
        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))
        XCTAssertEqual(pipeline.definition.stage(withKey: project.stageKey)?.name, "Reconciling")
        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))
        XCTAssertEqual(pipeline.definition.stage(withKey: project.stageKey)?.name, "Review", "advance jumped over Waiting on client")

        // Choosing it by hand works, and Advance from it resumes at the next real stage.
        PipelineEngine.enter(project, stage: waiting, context: context)
        XCTAssertEqual(project.stageKey, waiting.id)
        XCTAssertEqual(project.status, .waitingOnClient)
        XCTAssertEqual(PipelineEngine.nextStageName(for: project, in: [pipeline]), "Review")
        XCTAssertTrue(PipelineEngine.advance(project, in: pipeline, context: context))
        XCTAssertEqual(pipeline.definition.stage(withKey: project.stageKey)?.name, "Review")
    }

    func testNewJobsNeverStartInAWaitingStage() throws {
        let definition = PipelineDefinition(name: "X", stages: [
            PipelineStage(name: "Waiting first", kind: .waiting),
            PipelineStage(name: "Work", kind: .working),
            PipelineStage(name: "Done", kind: .done),
        ])
        XCTAssertEqual(definition.firstStartStage?.name, "Work")
        let context = try makeContext()
        let pipeline = Pipeline(definition: definition)
        context.insert(pipeline)
        let project = Project(title: "P")
        context.insert(project)
        PipelineEngine.assign(project, to: pipeline, context: context)
        XCTAssertEqual(project.status, .inProgress)
        // An explicitly chosen start stage is honored, even a waiting one.
        let other = Project(title: "Q")
        context.insert(other)
        PipelineEngine.assign(other, to: pipeline, startStageKey: definition.stages[0].id, context: context)
        XCTAssertEqual(other.status, .waitingOnClient)
    }

    func testEveryStarterStartsOnARealStageAndAdvanceNeverLandsOnWaiting() {
        for starter in PipelineStarters.all {
            XCTAssertNotEqual(starter.firstStage?.kind, .waiting, starter.name)
            var key = starter.firstStartStage!.id
            while let next = starter.next(after: key) {
                XCTAssertNotEqual(next.kind, .waiting, starter.name)
                key = next.id
            }
            XCTAssertEqual(starter.stage(withKey: key)?.kind, .done, "advance reaches the Done stage: \(starter.name)")
        }
    }

    // MARK: Default pipeline per service

    func testDefaultPipelineIsAppliedOnlyToItsService() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.payroll)
        context.insert(pipeline)
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        suite.set(pipeline.id.uuidString, forKey: PipelineDefaults.key(for: .payroll))

        let payroll = Project(title: "Payroll run", serviceType: .payroll)
        context.insert(payroll)
        PipelineEngine.applyDefault(to: payroll, context: context, defaults: suite)
        XCTAssertEqual(payroll.pipelineID, pipeline.id)
        XCTAssertEqual(payroll.stageKey, pipeline.stages[0].id)

        let books = Project(title: "Books", serviceType: .bookkeeping)
        context.insert(books)
        PipelineEngine.applyDefault(to: books, context: context, defaults: suite)
        XCTAssertNil(books.pipelineID, "other services keep their built-in pipeline")

        // A stale id (pipeline deleted) is ignored; an already-assigned job isn't reassigned.
        suite.set(UUID().uuidString, forKey: PipelineDefaults.key(for: .advisory))
        let advisory = Project(title: "Adv", serviceType: .advisory)
        context.insert(advisory)
        PipelineEngine.applyDefault(to: advisory, context: context, defaults: suite)
        XCTAssertNil(advisory.pipelineID)
        let previous = payroll.stageKey
        PipelineEngine.applyDefault(to: payroll, context: context, defaults: suite)
        XCTAssertEqual(payroll.stageKey, previous)
    }

    func testTemplateWithoutPipelineUsesTheServiceDefault() throws {
        let context = try makeContext()
        let pipeline = Pipeline(definition: PipelineStarters.irsNotice)
        context.insert(pipeline)
        UserDefaults.standard.set(pipeline.id.uuidString, forKey: PipelineDefaults.key(for: .irsNotice))
        defer { UserDefaults.standard.removeObject(forKey: PipelineDefaults.key(for: .irsNotice)) }
        let template = WorkflowTemplate(name: "Notice", detail: "", serviceType: .irsNotice)
        context.insert(template)
        let project = WorkflowEngine.instantiate(template: template, for: nil, into: context)
        XCTAssertEqual(project.pipelineID, pipeline.id)
    }
}

