import XCTest
@testable import CPAManager

final class TodayPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday, 2026-09-30 12:00 UTC.
    private var now: Date { date(2026, 9, 30, hour: 12) }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func item(due: Date? = nil, snooze: Date? = nil, done: Bool = false, next: Bool = false) -> PlannerItem {
        PlannerItem(id: UUID(), dueDate: due, snoozedUntil: snooze, isDone: done, isNextAction: next)
    }

    func testBucketsByDay() {
        let overdue = item(due: date(2026, 9, 29))
        let today = item(due: date(2026, 9, 30, hour: 18))
        let soon = item(due: date(2026, 10, 3))
        let far = item(due: date(2026, 11, 20))
        let plan = TodayPlanner.plan([overdue, today, soon, far], now: now, calendar: calendar)

        XCTAssertEqual(plan.ids(.overdue), [overdue.id])
        XCTAssertEqual(plan.ids(.today), [today.id])
        XCTAssertEqual(plan.ids(.comingUp), [soon.id])
        XCTAssertFalse(plan.sections.values.flatMap { $0 }.contains(far.id))
    }

    func testUndatedOnlyAppearsWhenNextAction() {
        let plain = item()
        let next = item(next: true)
        let plan = TodayPlanner.plan([plain, next], now: now, calendar: calendar)
        XCTAssertEqual(plan.ids(.next), [next.id])
        XCTAssertFalse(plan.sections.values.flatMap { $0 }.contains(plain.id))
    }

    func testDoneItemsAreExcluded() {
        let done = item(due: date(2026, 9, 29), done: true)
        let plan = TodayPlanner.plan([done], now: now, calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSnoozeHidesUntilItsDay() {
        let snoozed = item(due: date(2026, 9, 29), snooze: date(2026, 10, 1))
        let hidden = TodayPlanner.plan([snoozed], now: now, calendar: calendar)
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(hidden.snoozedCount, 1)

        let later = date(2026, 10, 1, hour: 8)
        let visible = TodayPlanner.plan([snoozed], now: later, calendar: calendar)
        XCTAssertEqual(visible.ids(.overdue), [snoozed.id])
        XCTAssertEqual(visible.snoozedCount, 0)
    }

    func testSortsByDueDateThenInputOrder() {
        let a = item(due: date(2026, 9, 28))
        let b = item(due: date(2026, 9, 27))
        let c = item(due: date(2026, 9, 27))
        let plan = TodayPlanner.plan([a, b, c], now: now, calendar: calendar)
        XCTAssertEqual(plan.ids(.overdue), [b.id, c.id, a.id])
    }

    func testSnoozeDates() {
        // Wednesday 2026-09-30.
        XCTAssertEqual(TodayPlanner.snoozeDate(.tomorrow, now: now, calendar: calendar), date(2026, 10, 1))
        XCTAssertEqual(TodayPlanner.snoozeDate(.thisWeekend, now: now, calendar: calendar), date(2026, 10, 3))
        XCTAssertEqual(TodayPlanner.snoozeDate(.nextWeek, now: now, calendar: calendar), date(2026, 10, 5))
    }
}
