import XCTest
@testable import CPAManager

final class TaskRecurrenceTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // 2026-09-30 is a Wednesday; 2026-10-02 a Friday; 2026-10-03 a Saturday.

    func testStepPerRule() {
        let wed = date(2026, 9, 30)
        XCTAssertEqual(TaskRecurrence.step(wed, rule: .daily, calendar: calendar), date(2026, 10, 1))
        XCTAssertEqual(TaskRecurrence.step(wed, rule: .weekly, calendar: calendar), date(2026, 10, 7))
        XCTAssertEqual(TaskRecurrence.step(wed, rule: .monthly, calendar: calendar), date(2026, 10, 30))
        XCTAssertEqual(TaskRecurrence.step(wed, rule: .yearly, calendar: calendar), date(2027, 9, 30))
        XCTAssertNil(TaskRecurrence.step(wed, rule: .none, calendar: calendar))
    }

    func testWeekdaysSkipWeekend() {
        let fri = date(2026, 10, 2)
        XCTAssertEqual(TaskRecurrence.step(fri, rule: .weekdays, calendar: calendar), date(2026, 10, 5))
    }

    func testMonthlyClampsToShortMonths() {
        XCTAssertEqual(TaskRecurrence.step(date(2026, 1, 31), rule: .monthly, calendar: calendar), date(2026, 2, 28))
    }

    func testNextOccurrenceKeepsCadenceAndNeverLandsInThePast() {
        let now = date(2026, 9, 30, hour: 10)
        // Due today, completed today → one period ahead.
        XCTAssertEqual(TaskRecurrence.nextOccurrence(after: date(2026, 9, 30), rule: .weekly, now: now, calendar: calendar), date(2026, 10, 7))
        // A weekly Friday task five weeks late → the next Friday, not five stacked overdues.
        XCTAssertEqual(TaskRecurrence.nextOccurrence(after: date(2026, 8, 21), rule: .weekly, now: now, calendar: calendar), date(2026, 10, 2))
        // Due in the future → simply the next one after it.
        XCTAssertEqual(TaskRecurrence.nextOccurrence(after: date(2026, 10, 10), rule: .daily, now: now, calendar: calendar), date(2026, 10, 11))
        XCTAssertNil(TaskRecurrence.nextOccurrence(after: now, rule: .none, now: now, calendar: calendar))
    }

    func testNextWeekday() {
        let wed = date(2026, 9, 30, hour: 9)
        XCTAssertEqual(TaskRecurrence.nextWeekday(6, from: wed, calendar: calendar), date(2026, 10, 2))       // Friday
        XCTAssertEqual(TaskRecurrence.nextWeekday(4, from: wed, calendar: calendar), date(2026, 9, 30))       // today (Wed)
        XCTAssertEqual(TaskRecurrence.nextWeekday(4, from: wed, includingToday: false, calendar: calendar), date(2026, 10, 7))
    }

    // MARK: Parser

    func testExtractsTrailingRepeatPhrases() {
        XCTAssertEqual(RecurrenceParser.extract(from: "Pay estimated tax every quarter").rule, .none, "quarterly isn't supported yet")
        XCTAssertEqual(RecurrenceParser.extract(from: "Water plants daily"), .init(title: "Water plants", rule: .daily, weekday: nil))
        XCTAssertEqual(RecurrenceParser.extract(from: "Review books every month"), .init(title: "Review books", rule: .monthly, weekday: nil))
        XCTAssertEqual(RecurrenceParser.extract(from: "Standup every weekday"), .init(title: "Standup", rule: .weekdays, weekday: nil))
        XCTAssertEqual(RecurrenceParser.extract(from: "Renew domain annually"), .init(title: "Renew domain", rule: .yearly, weekday: nil))
    }

    func testEveryWeekdayNameIsWeeklyOnThatDay() {
        let result = RecurrenceParser.extract(from: "Send invoices every Friday")
        XCTAssertEqual(result.title, "Send invoices")
        XCTAssertEqual(result.rule, .weekly)
        XCTAssertEqual(result.weekday, 6)
        XCTAssertEqual(RecurrenceParser.extract(from: "Team sync every sunday").weekday, 1)
    }

    func testLeadingPhraseAndNoPhrase() {
        XCTAssertEqual(RecurrenceParser.extract(from: "Weekly review of books").rule, .weekly)
        XCTAssertEqual(RecurrenceParser.extract(from: "Weekly review of books").title, "review of books")
        let plain = RecurrenceParser.extract(from: "Call the office")
        XCTAssertEqual(plain.rule, .none)
        XCTAssertEqual(plain.title, "Call the office")
    }

    func testWholeLineThatIsOnlyAPhraseIsKeptAsText() {
        let result = RecurrenceParser.extract(from: "daily")
        XCTAssertEqual(result.rule, .none)
        XCTAssertEqual(result.title, "daily")
    }

    func testQuickCaptureAnchorsRepeatingTasks() {
        let now = date(2026, 9, 30, hour: 9)
        let daily = QuickCapture.parse("Water plants daily", now: now, calendar: calendar)
        XCTAssertEqual(daily.rule, .daily)
        XCTAssertEqual(daily.dueDate, date(2026, 9, 30))

        let friday = QuickCapture.parse("Send invoices every Friday", now: now, calendar: calendar)
        XCTAssertEqual(friday.dueDate, date(2026, 10, 2))

        let plain = QuickCapture.parse("Call the office", now: now, calendar: calendar)
        XCTAssertEqual(plain.rule, .none)
        XCTAssertNil(plain.dueDate)
    }
}
