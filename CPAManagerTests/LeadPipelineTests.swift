import XCTest
@testable import CPAManager

final class LeadPipelineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func lead(_ stage: LeadStage, value: Double = 0, last: Date? = nil, created: Date? = nil) -> LeadSummary {
        LeadSummary(id: UUID(), stage: stage, value: value, lastContact: last, createdAt: created ?? date(2026, 9, 1))
    }

    func testExistingProspectsCountAsNewLeads() {
        XCTAssertEqual(LeadPipeline.effectiveStage(raw: "", status: .prospect), .new)
        XCTAssertNil(LeadPipeline.effectiveStage(raw: "", status: .active))
        XCTAssertEqual(LeadPipeline.effectiveStage(raw: "won", status: .active), .won)
        XCTAssertEqual(LeadPipeline.effectiveStage(raw: "bogus", status: .prospect), .new)
    }

    func testAdvanceWalksTheFunnelAndStopsAtTerminalStages() {
        XCTAssertEqual(LeadPipeline.advance(.new), .contacted)
        XCTAssertEqual(LeadPipeline.advance(.contacted), .proposalSent)
        XCTAssertEqual(LeadPipeline.advance(.proposalSent), .won)
        XCTAssertNil(LeadPipeline.advance(.won))
        XCTAssertNil(LeadPipeline.advance(.lost))
    }

    func testStageDrivesClientStatus() {
        XCTAssertEqual(LeadPipeline.status(for: .new), .prospect)
        XCTAssertEqual(LeadPipeline.status(for: .proposalSent), .prospect)
        XCTAssertEqual(LeadPipeline.status(for: .won), .active)
        XCTAssertEqual(LeadPipeline.status(for: .lost), .inactive)
    }

    func testSummaryCountsValueAndWinRate() {
        let summary = LeadPipeline.summarize([
            lead(.new, value: 1000), lead(.contacted, value: 2000), lead(.proposalSent, value: 3000),
            lead(.won, value: 5000), lead(.won), lead(.lost, value: 800),
        ])
        XCTAssertEqual(summary.openCount, 3)
        XCTAssertEqual(summary.openValue, 6000, "won/lost value isn't pipeline")
        XCTAssertEqual(summary.countByStage[.won], 2)
        XCTAssertEqual(try XCTUnwrap(summary.winRate), 2.0 / 3.0, accuracy: 0.0001)
    }

    func testWinRateIsNilUntilSomethingCloses() {
        XCTAssertNil(LeadPipeline.summarize([lead(.new)]).winRate)
        XCTAssertNil(LeadPipeline.summarize([]).winRate)
    }

    func testStaleLeads() {
        let now = date(2026, 9, 30)
        let neglected = lead(.contacted, last: date(2026, 9, 1))
        let fresh = lead(.new, last: date(2026, 9, 28))
        let neverContactedOld = lead(.new, created: date(2026, 9, 10))
        let neverContactedNew = lead(.new, created: date(2026, 9, 29))
        let won = lead(.won, last: date(2026, 1, 1))

        let stale = LeadPipeline.staleLeads([fresh, neglected, neverContactedNew, won, neverContactedOld], now: now, calendar: calendar)
        XCTAssertEqual(stale, [neglected.id, neverContactedOld.id])
    }
}
