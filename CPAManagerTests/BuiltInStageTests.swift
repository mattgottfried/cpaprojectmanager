import XCTest
import SwiftData
@testable import CPAManager

private func automation(_ titles: [String], due: Int? = nil) -> StageAutomation {
    StageAutomation(tasks: titles.map { StageTask(title: $0, dueInDays: 2) }, setDueInDays: due)
}

final class BuiltInSetupLogicTests: XCTestCase {
    private let old = Date(timeIntervalSince1970: 1_000)
    private let new = Date(timeIntervalSince1970: 2_000)

    func testTheNewestDuplicateWins() {
        let resolved = BuiltInSetup.resolve([
            BuiltInSetupInput(serviceTypeRaw: "bookkeeping", stageKey: "inProgress", automation: automation(["old"]), updatedAt: old),
            BuiltInSetupInput(serviceTypeRaw: "bookkeeping", stageKey: "inProgress", automation: automation(["new"]), updatedAt: new),
            BuiltInSetupInput(serviceTypeRaw: "payroll", stageKey: "inProgress", automation: automation(["other service"]), updatedAt: old),
        ])
        XCTAssertEqual(BuiltInSetup.automation(serviceTypeRaw: "bookkeeping", stageKey: "inProgress", in: resolved).tasks.map(\.title), ["new"])
        XCTAssertEqual(BuiltInSetup.automation(serviceTypeRaw: "payroll", stageKey: "inProgress", in: resolved).tasks.map(\.title), ["other service"])
        XCTAssertTrue(BuiltInSetup.automation(serviceTypeRaw: "payroll", stageKey: "complete", in: resolved).isEmpty)
    }

    func testAnEqualTimeTieKeepsTheOneWithTasks() {
        let resolved = BuiltInSetup.resolve([
            BuiltInSetupInput(serviceTypeRaw: "a", stageKey: "s", automation: StageAutomation(), updatedAt: old),
            BuiltInSetupInput(serviceTypeRaw: "a", stageKey: "s", automation: automation(["keep"]), updatedAt: old),
        ])
        XCTAssertEqual(BuiltInSetup.automation(serviceTypeRaw: "a", stageKey: "s", in: resolved).tasks.count, 1)
    }

    func testSummaryAndCleaning() {
        XCTAssertEqual(BuiltInSetup.summary(StageAutomation()), "No tasks")
        XCTAssertEqual(BuiltInSetup.summary(automation(["a"])), "1 task")
        XCTAssertEqual(BuiltInSetup.summary(automation(["a", "b"], due: 14)), "2 tasks · due in 14 days")
        XCTAssertEqual(BuiltInSetup.cleaned(automation(["a", "  ", ""])).tasks.map(\.title), ["a"])
    }
}

@MainActor
final class BuiltInStageEngineTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    private func project(_ context: ModelContext, service: ServiceType = .bookkeeping) -> Project {
        let p = Project(title: "Books", serviceType: service)
        context.insert(p)
        return p
    }

    func testEnteringAStageCreatesItsTasksOneAtATime() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Request statements", "Reconcile accounts"]),
                                 service: .bookkeeping, stageKey: ProjectStatus.inProgress.rawValue, context: context)
        let job = project(context)

        PipelineEngine.advanceAny(job, pipelines: [], context: context)
        XCTAssertEqual(job.status, .inProgress)
        let tasks = job.taskList
        XCTAssertEqual(tasks.map(\.title), ["Request statements", "Reconcile accounts"])
        XCTAssertNotNil(tasks[0].dueDate)
        XCTAssertNil(tasks[1].dueDate, "the second waits for the first")
        XCTAssertEqual(tasks[1].blockedByID, tasks[0].id)
    }

    func testEachStageHasItsOwnTasks() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Prepare return"]), service: .taxReturn, stageKey: ProjectStatus.inProgress.rawValue, context: context)
        BuiltInSetupService.save(automation(["Send for e-signature"]), service: .taxReturn, stageKey: ProjectStatus.awaitingSignature.rawValue, context: context)
        let job = project(context, service: .taxReturn)

        PipelineEngine.setBuiltInStatus(job, to: .inProgress, context: context)
        XCTAssertEqual(job.taskList.map(\.title), ["Prepare return"])
        PipelineEngine.setBuiltInStatus(job, to: .awaitingSignature, context: context)
        XCTAssertEqual(job.taskList.map(\.title), ["Prepare return", "Send for e-signature"])
        XCTAssertEqual(job.status, .awaitingSignature, "the built-in status is exact, not a coarse one")
    }

    func testNewJobsGetTheFirstStagesTasksAndTheDueDateReset() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Send engagement letter"], due: 10),
                                 service: .bookkeeping, stageKey: ProjectStatus.notStarted.rawValue, context: context)
        let job = project(context)
        PipelineEngine.applyDefault(to: job, context: context, defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertEqual(job.taskList.map(\.title), ["Send engagement letter"])
        XCTAssertNotNil(job.dueDate)
    }

    func testSettingTheSameStageAgainDoesNotDuplicateTasks() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Once"]), service: .bookkeeping, stageKey: ProjectStatus.inProgress.rawValue, context: context)
        let job = project(context)
        PipelineEngine.setBuiltInStatus(job, to: .inProgress, context: context)
        PipelineEngine.setBuiltInStatus(job, to: .inProgress, context: context)
        PipelineEngine.runBuiltInAutomation(job, context: context)
        XCTAssertEqual(job.taskList.count, 1, "open tasks with the same title are not repeated")
    }

    func testCompletingAJobRunsTheCompleteStage() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Send closing letter"]), service: .bookkeeping, stageKey: ProjectStatus.complete.rawValue, context: context)
        let job = project(context)
        PipelineEngine.complete(job, pipelines: [], context: context)
        XCTAssertTrue(job.status.isComplete)
        XCTAssertEqual(job.taskList.map(\.title), ["Send closing letter"])
    }

    func testSavingEmptyRemovesTheSetupAndDuplicatesAreCollapsed() throws {
        let context = try makeContext()
        // Two devices created the same stage independently.
        context.insert(BuiltInStageSetup(service: .payroll, stageKey: "inProgress", automation: automation(["a"]), now: Date(timeIntervalSince1970: 1)))
        context.insert(BuiltInStageSetup(service: .payroll, stageKey: "inProgress", automation: automation(["b"]), now: Date(timeIntervalSince1970: 2)))
        XCTAssertEqual(BuiltInSetupService.automation(for: .payroll, stageKey: "inProgress", context: context).tasks.map(\.title), ["b"])

        BuiltInSetupService.save(automation(["c"]), service: .payroll, stageKey: "inProgress", context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuiltInStageSetup>()), 1, "the stray duplicate is removed")
        XCTAssertEqual(BuiltInSetupService.automation(for: .payroll, stageKey: "inProgress", context: context).tasks.map(\.title), ["c"])

        BuiltInSetupService.save(StageAutomation(), service: .payroll, stageKey: "inProgress", context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BuiltInStageSetup>()), 0)
    }

    func testCustomPipelineJobsAreUnaffectedByBuiltInSetup() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Built-in only"]), service: .bookkeeping, stageKey: ProjectStatus.notStarted.rawValue, context: context)
        let job = project(context)
        job.pipelineID = UUID()
        PipelineEngine.runBuiltInAutomation(job, context: context)
        XCTAssertTrue(job.taskList.isEmpty)
    }

    func testBuiltInSetupSurvivesBackupAndSyncEncoding() throws {
        let context = try makeContext()
        BuiltInSetupService.save(automation(["Round trip"]), service: .advisory, stageKey: "inProgress", context: context)
        try context.save()

        let file = BackupService.export(context: context)
        XCTAssertEqual(file.builtInStages?.count, 1)

        let encoded = SyncCodec.encode(file)
        let key = try XCTUnwrap(encoded.entries.keys.first { $0.collection == .builtInStages })
        let decoded = SyncCodec.decode([try XCTUnwrap(encoded.entries[key])])
        XCTAssertEqual(decoded.file.builtInStages?.count, 1)
        XCTAssertTrue(decoded.failed.isEmpty)

        let target = try makeContext()
        BackupService.restore(decoded.file, into: target, overwrite: true)
        XCTAssertEqual(BuiltInSetupService.automation(for: .advisory, stageKey: "inProgress", context: target).tasks.map(\.title), ["Round trip"])
    }
}
