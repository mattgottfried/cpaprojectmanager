import XCTest
@testable import CPAManager

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}
private func day(_ m: Int, _ d: Int, hour: Int = 10) -> Date { utc.date(from: DateComponents(year: 2026, month: m, day: d, hour: hour))! }
// Wednesday, September 30, 2026.
private let now = day(9, 30)

private func task(_ title: String, due: Date?, done: Bool = false, blocked: Bool = false, high: Bool = false, snoozed: Date? = nil) -> WeekTaskInput {
    WeekTaskInput(id: UUID(), title: title, subtitle: "", dueDate: due, isDone: done, isBlocked: blocked, isHigh: high, snoozedUntil: snoozed)
}

final class WeekAgendaTests: XCTestCase {
    func testWindowIsTodayThroughSixDaysAhead() {
        let tasks = [
            task("yesterday", due: day(9, 29)),
            task("today", due: day(9, 30, hour: 8)),
            task("day six", due: day(10, 6)),
            task("day seven", due: day(10, 7)),
            task("undated", due: nil),
        ]
        let titles = WeekAgenda.entries(tasks, now: now, calendar: utc).map(\.title)
        XCTAssertEqual(titles, ["today", "day six"])
        XCTAssertEqual(WeekAgenda.overdueCount(tasks, now: now, calendar: utc), 1)
    }

    func testDoneBlockedAndSnoozedAreLeftOut() {
        let tasks = [
            task("done", due: day(10, 1), done: true),
            task("blocked", due: day(10, 1), blocked: true),
            task("snoozed", due: day(10, 1), snoozed: day(10, 3)),
            task("snooze over", due: day(10, 1), snoozed: day(9, 29)),
            task("fine", due: day(10, 1)),
        ]
        XCTAssertEqual(WeekAgenda.entries(tasks, now: now, calendar: utc).map(\.title), ["fine", "snooze over"])
        XCTAssertEqual(WeekAgenda.overdueCount([task("late done", due: day(9, 1), done: true), task("late blocked", due: day(9, 1), blocked: true)], now: now, calendar: utc), 0)
    }

    func testOrderIsByDayThenHighPriorityThenTitle() {
        let tasks = [
            task("b normal", due: day(10, 2, hour: 15)),
            task("z high", due: day(10, 2, hour: 9), high: true),
            task("a normal", due: day(10, 2, hour: 11)),
            task("early", due: day(10, 1)),
        ]
        XCTAssertEqual(WeekAgenda.entries(tasks, now: now, calendar: utc).map(\.title), ["early", "z high", "a normal", "b normal"])
    }

    func testDayLabels() {
        XCTAssertEqual(WeekAgenda.dayLabel(day(9, 30, hour: 20), now: now, calendar: utc), "today")
        XCTAssertEqual(WeekAgenda.dayLabel(day(10, 1), now: now, calendar: utc), "tomorrow")
        XCTAssertEqual(WeekAgenda.dayLabel(day(10, 3), now: now, calendar: utc), "Sat")
    }

    func testSpokenSummary() {
        let entries = WeekAgenda.entries([
            task("Call Smith", due: day(9, 30)), task("Send 1099s", due: day(10, 1)),
            task("Review", due: day(10, 2)), task("File", due: day(10, 3)), task("Pay", due: day(10, 4)),
        ], now: now, calendar: utc)
        XCTAssertEqual(
            Briefing.week(overdue: 2, entries: entries, now: now, calendar: utc),
            "2 overdue. 5 due this week: Call Smith (today), Send 1099s (tomorrow), Review (Fri) and 2 more."
        )
        XCTAssertEqual(Briefing.week(overdue: 0, entries: [], now: now, calendar: utc), "Nothing else due this week.")
        XCTAssertEqual(Briefing.week(overdue: 1, entries: [], now: now, calendar: utc), "1 overdue. Nothing else due this week.")
    }
}
