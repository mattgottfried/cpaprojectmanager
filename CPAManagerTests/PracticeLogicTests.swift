import XCTest
@testable import CPAManager

final class TaxCalendarTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func due(_ form: TaxCalendar.Form, _ year: Int, extended: Bool = false) -> Date {
        TaxCalendar.dueDate(form: form, taxYear: year, extended: extended, calendar: calendar)
    }

    func testStandardDueDatesFor2025Returns() {
        // 2026 dates: Mar 15 is a Sunday → Monday Mar 16 (matches the IRS 2026 calendar).
        XCTAssertEqual(due(.f1065, 2025), date(2026, 3, 16))
        XCTAssertEqual(due(.f1120S, 2025), date(2026, 3, 16))
        XCTAssertEqual(due(.f1040, 2025), date(2026, 4, 15))
        XCTAssertEqual(due(.f1120, 2025), date(2026, 4, 15))
        XCTAssertEqual(due(.f1041, 2025), date(2026, 4, 15))
        XCTAssertEqual(due(.f990, 2025), date(2026, 5, 15))
    }

    func testExtendedDueDatesFor2025Returns() {
        XCTAssertEqual(due(.f1065, 2025, extended: true), date(2026, 9, 15))
        XCTAssertEqual(due(.f1120S, 2025, extended: true), date(2026, 9, 15))
        XCTAssertEqual(due(.f1040, 2025, extended: true), date(2026, 10, 15))
        XCTAssertEqual(due(.f1120, 2025, extended: true), date(2026, 10, 15))
        XCTAssertEqual(due(.f1041, 2025, extended: true), date(2026, 9, 30))
        XCTAssertEqual(due(.f990, 2025, extended: true), date(2026, 11, 16), "Nov 15, 2026 is a Sunday")
    }

    func testEmancipationDayMovesAprilDeadline() {
        // April 15, 2022 was a Friday, but D.C. Emancipation Day was observed that day.
        XCTAssertEqual(due(.f1040, 2021), date(2022, 4, 18))
    }

    func testMLKDayMovesJanuaryEstimatedPayment() {
        // January 15, 2024 was Martin Luther King Jr. Day → due Tuesday the 16th.
        let dates = TaxCalendar.estimatedPaymentDates(taxYear: 2023, calendar: calendar)
        XCTAssertEqual(dates.last, date(2024, 1, 16))
    }

    func testEstimatedPaymentDates2025() {
        let dates = TaxCalendar.estimatedPaymentDates(taxYear: 2025, calendar: calendar)
        XCTAssertEqual(dates, [date(2025, 4, 15), date(2025, 6, 16), date(2025, 9, 15), date(2026, 1, 15)])
    }

    func testDeadlinesForAnIndividualIncludeEstimatesAndExtension() {
        let plain = TaxCalendar.deadlines(for: .individual1040, taxYear: 2025, extended: false, calendar: calendar)
        XCTAssertEqual(plain.count, 5)   // 4 estimates + return
        XCTAssertEqual(plain.map { $0.date }, plain.map { $0.date }.sorted())

        let extended = TaxCalendar.deadlines(for: .individual1040, taxYear: 2025, extended: true, calendar: calendar)
        XCTAssertEqual(extended.count, 6)
        XCTAssertEqual(extended.last?.kind, .extended)
    }

    func testBusinessEntitiesGetNoEstimatesAndUnknownEntityGetsNothing() {
        XCTAssertEqual(TaxCalendar.deadlines(for: .sCorp1120S, taxYear: 2025, extended: false, calendar: calendar).count, 1)
        XCTAssertTrue(TaxCalendar.deadlines(for: .other, taxYear: 2025, extended: true, calendar: calendar).isEmpty)
    }
}

final class DocumentChecklistTests: XCTestCase {
    func testEveryEntityHasSuggestions() {
        for entity in EntityType.allCases {
            XCTAssertFalse(DocumentChecklist.suggestions(for: entity).isEmpty, entity.label)
        }
    }

    func testProgress() {
        XCTAssertEqual(DocumentChecklist.progress(received: 2, total: 4), 0.5)
        XCTAssertEqual(DocumentChecklist.progress(received: 0, total: 0), 0)
    }

    func testRequestEmailListsMissingItems() {
        let body = DocumentChecklist.requestEmailBody(clientName: "Dana", items: ["W-2s", "1098"], dueDate: nil, firm: "Gottfried CPA")
        XCTAssertTrue(body.contains("Hi Dana"))
        XCTAssertTrue(body.contains("• W-2s"))
        XCTAssertTrue(body.contains("• 1098"))
        XCTAssertFalse(body.contains("by "), "no date line without a due date")
        XCTAssertTrue(body.hasSuffix("Gottfried CPA"))
    }
}

final class RecurringInvoicePlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testNothingDueBeforeTheIssueDate() {
        let plan = RecurringInvoicePlanner.plan(nextIssue: date(2026, 10, 1), frequency: .monthly, now: date(2026, 9, 30, hour: 10), calendar: calendar)
        XCTAssertTrue(plan.issueDates.isEmpty)
        XCTAssertEqual(plan.nextIssueDate, date(2026, 10, 1))
    }

    func testDueTodayDraftsOneAndAdvances() {
        let plan = RecurringInvoicePlanner.plan(nextIssue: date(2026, 9, 30), frequency: .monthly, now: date(2026, 9, 30, hour: 10), calendar: calendar)
        XCTAssertEqual(plan.issueDates, [date(2026, 9, 30)])
        XCTAssertEqual(plan.nextIssueDate, date(2026, 10, 30))
    }

    func testCatchUpIsCappedButScheduleMovesPastToday() {
        // Five monthly periods missed (May…Sep) → only the latest three are drafted.
        let plan = RecurringInvoicePlanner.plan(nextIssue: date(2026, 5, 1), frequency: .monthly, now: date(2026, 9, 30), calendar: calendar)
        XCTAssertEqual(plan.issueDates, [date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1)])
        XCTAssertEqual(plan.nextIssueDate, date(2026, 10, 1))
    }

    func testDueDateAppliesNetTerms() {
        XCTAssertEqual(RecurringInvoicePlanner.dueDate(issue: date(2026, 9, 30), termsDays: 30, calendar: calendar), date(2026, 10, 30))
        XCTAssertEqual(RecurringInvoicePlanner.dueDate(issue: date(2026, 9, 30), termsDays: -5, calendar: calendar), date(2026, 9, 30))
    }
}

final class ExpenseMathTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func row(_ cat: ExpenseCategory, _ amount: Double, percent: Int = 100, month: Int = 3) -> ExpenseMath.Row {
        ExpenseMath.Row(category: cat, date: calendar.date(from: DateComponents(year: 2026, month: month, day: 10))!, amount: amount, deductiblePercent: percent)
    }

    func testDeductibleUsesCentsAndClampsPercent() {
        XCTAssertEqual(ExpenseMath.deductible(amount: 45.10, percent: 50), 22.55)
        XCTAssertEqual(ExpenseMath.deductible(amount: 100, percent: 150), 100)
        XCTAssertEqual(ExpenseMath.deductible(amount: 100, percent: -5), 0)
    }

    func testTotalsByCategorySortedBiggestFirst() {
        let totals = ExpenseMath.totalsByCategory([
            row(.software, 20), row(.software, 30), row(.meals, 80, percent: 50), row(.travel, 10),
        ])
        XCTAssertEqual(totals.map { $0.category }, [.meals, .software, .travel])
        XCTAssertEqual(totals[0].total, 80)
        XCTAssertEqual(totals[0].deductible, 40)
        XCTAssertEqual(totals[1].total, 50)
    }

    func testRangeFiltersByDate() {
        let range = ExpenseMath.yearRange(2026, calendar: calendar)
        let other = ExpenseMath.Row(category: .other, date: calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!, amount: 99, deductiblePercent: 100)
        let totals = ExpenseMath.totalsByCategory([row(.software, 20), other], in: range)
        XCTAssertEqual(totals.map { $0.category }, [.software])
    }

    func testMealsDefaultToFiftyPercentEverythingElseFull() {
        XCTAssertEqual(ExpenseCategory.meals.defaultDeductiblePercent, 50)
        XCTAssertEqual(ExpenseCategory.software.defaultDeductiblePercent, 100)
    }
}
