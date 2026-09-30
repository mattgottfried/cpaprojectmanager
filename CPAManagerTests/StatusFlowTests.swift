import XCTest
import SwiftData
@testable import CPAManager

final class StatusFlowTests: XCTestCase {
    func testTaxReturnFlowMatchesTheFirmsList() {
        XCTAssertEqual(StatusFlow.taxReturn.statuses.map { StatusFlow.taxReturn.label($0) },
                       ["Not Started", "In Progress", "On Hold", "Awaiting Signature", "Ready to File", "Filed", "Complete"])
    }

    func testGeneralFlowIsFourStatuses() {
        XCTAssertEqual(StatusFlow.general.statuses.map { StatusFlow.general.label($0) },
                       ["Not Started", "In Progress", "Waiting on Client", "Completed"])
    }

    func testFlowIsChosenByServiceType() {
        XCTAssertEqual(StatusFlow.flow(for: .taxReturn), .taxReturn)
        for type in ServiceType.allCases where type != .taxReturn {
            XCTAssertEqual(StatusFlow.flow(for: type), .general, type.rawValue)
        }
    }

    func testNormalizeMapsRetiredAndOutOfFlowStatuses() {
        XCTAssertEqual(StatusFlow.taxReturn.normalize(.awaitingDocs), .notStarted)
        XCTAssertEqual(StatusFlow.taxReturn.normalize(.review), .inProgress)
        XCTAssertEqual(StatusFlow.taxReturn.normalize(.filed), .filed)
        XCTAssertEqual(StatusFlow.general.normalize(.awaitingDocs), .waitingOnClient)
        XCTAssertEqual(StatusFlow.general.normalize(.review), .inProgress)
        XCTAssertEqual(StatusFlow.general.normalize(.awaitingSignature), .inProgress)
        XCTAssertEqual(StatusFlow.general.normalize(.readyToFile), .inProgress)
        XCTAssertEqual(StatusFlow.general.normalize(.filed), .complete)
        for flow in StatusFlow.allCases {
            for status in flow.statuses { XCTAssertEqual(flow.normalize(status), status, "in-flow statuses are untouched") }
            for status in ProjectStatus.allCases { XCTAssertTrue(flow.statuses.contains(flow.normalize(status))) }
        }
    }

    func testAdvanceSequenceSkipsTheWaitingStatus() {
        XCTAssertEqual(StatusFlow.taxReturn.next(after: .notStarted), .inProgress)
        XCTAssertEqual(StatusFlow.taxReturn.next(after: .inProgress), .awaitingSignature)
        XCTAssertEqual(StatusFlow.taxReturn.next(after: .awaitingSignature), .readyToFile)
        XCTAssertEqual(StatusFlow.taxReturn.next(after: .filed), .complete)
        XCTAssertNil(StatusFlow.taxReturn.next(after: .complete))
        XCTAssertNil(StatusFlow.taxReturn.next(after: .waitingOnClient), "on hold: resume first")
        XCTAssertEqual(StatusFlow.general.next(after: .notStarted), .inProgress)
        XCTAssertEqual(StatusFlow.general.next(after: .inProgress), .complete)
        XCTAssertNil(StatusFlow.general.next(after: .complete))
        XCTAssertEqual(StatusFlow.taxReturn.next(after: .awaitingDocs), .inProgress, "a retired status is normalized first")
    }
}

@MainActor
final class StatusSplitModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testProjectAdvanceFollowsItsFlow() {
        let tax = Project(title: "1040", status: .inProgress, serviceType: .taxReturn)
        XCTAssertEqual(tax.nextStatusPreview, .awaitingSignature)
        let books = Project(title: "Books", status: .inProgress, serviceType: .bookkeeping)
        XCTAssertEqual(books.nextStatusPreview, .complete)
        XCTAssertEqual(books.statusLabel, "In Progress")
        books.putOnHold(reason: .waitingOnClient, detail: "statements")
        XCTAssertEqual(books.statusLabel, "Waiting on Client")
        XCTAssertNil(books.nextStatusPreview)
        books.takeOffHold()
        XCTAssertEqual(books.status, .inProgress)
        tax.putOnHold(reason: .waitingOnClient, detail: "")
        XCTAssertEqual(tax.statusLabel, "On Hold")
    }

    func testCustomPipelineJobsAreNeverOnHold() {
        let job = Project(title: "Custom", status: .waitingOnClient, serviceType: .bookkeeping)
        job.pipelineID = UUID()
        XCTAssertFalse(job.isOnHold)
        job.putOnHold(reason: .other, detail: "")
        XCTAssertEqual(job.status, .waitingOnClient, "hold is refused on custom-pipeline jobs, so nothing changes")
    }

    func testMigrationMovesRetiredStatusesAndIsIdempotent() throws {
        let context = try makeContext()
        let docs = Project(title: "A", status: .awaitingDocs, serviceType: .taxReturn)
        let review = Project(title: "B", status: .review, serviceType: .taxReturn)
        let generalWaiting = Project(title: "C", status: .awaitingDocs, serviceType: .payroll)
        let generalFiled = Project(title: "D", status: .filed, serviceType: .advisory)
        let fine = Project(title: "E", status: .readyToFile, serviceType: .taxReturn)
        [docs, review, generalWaiting, generalFiled, fine].forEach { context.insert($0) }
        generalFiled.completedAt = nil

        XCTAssertEqual(StatusMigration.run(context: context), 4)
        XCTAssertEqual(docs.status, .notStarted)
        XCTAssertEqual(review.status, .inProgress)
        XCTAssertEqual(generalWaiting.status, .waitingOnClient)
        XCTAssertEqual(generalFiled.status, .complete)
        XCTAssertNotNil(generalFiled.completedAt, "becoming complete stamps the completion time")
        XCTAssertEqual(fine.status, .readyToFile)
        XCTAssertEqual(StatusMigration.run(context: context), 0, "second run changes nothing")
    }

    func testMigrationFixesHoldResumeStatus() throws {
        let context = try makeContext()
        let project = Project(title: "X", status: .waitingOnClient, serviceType: .taxReturn)
        project.holdResumeStatusRaw = ProjectStatus.review.rawValue
        context.insert(project)
        XCTAssertEqual(StatusMigration.run(context: context), 1)
        XCTAssertEqual(project.holdResumeStatusRaw, ProjectStatus.inProgress.rawValue)
        project.takeOffHold()
        XCTAssertEqual(project.status, .inProgress)
    }
}
