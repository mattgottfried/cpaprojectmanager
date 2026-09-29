import XCTest
@testable import CPAManager

final class ClientLogicTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func summary(
        name: String = "Smith", status: ClientStatus = .active, entity: EntityType = .individual1040,
        tags: [String] = [], open: Int = 0, email: String = "", company: String = ""
    ) -> ClientSummary {
        ClientSummary(id: UUID(), displayName: name, company: company, email: email,
                      status: status, entityType: entity, tags: tags, openWorkCount: open)
    }

    // MARK: Tags

    func testTagParsingNormalizesAndDedupes() {
        XCTAssertEqual(TagSet.parse("Referral, #bookkeeping ,referral,  "), ["referral", "bookkeeping"])
        XCTAssertEqual(TagSet.parse("  Side   Hustle "), ["side hustle"])
        XCTAssertEqual(TagSet.parse(""), [])
    }

    func testTagEncodeRoundTrips() {
        let encoded = TagSet.encode(["Referral", "referral", "S-Corp"])
        XCTAssertEqual(encoded, "referral, s-corp")
        XCTAssertEqual(TagSet.parse(encoded), ["referral", "s-corp"])
    }

    func testTagCountsSortedByUseThenName() {
        let counts = TagSet.counts([["a", "b"], ["b"], ["b", "c"], ["c"]])
        XCTAssertEqual(counts.map { $0.tag }, ["b", "c", "a"])
        XCTAssertEqual(counts.first?.count, 3)
    }

    // MARK: Filters

    func testFilterCombinesCriteria() {
        let match = summary(status: .active, entity: .sCorp1120S, tags: ["referral"], open: 2)
        let wrongStatus = summary(status: .prospect, entity: .sCorp1120S, tags: ["referral"], open: 2)
        let noWork = summary(status: .active, entity: .sCorp1120S, tags: ["referral"], open: 0)

        let filter = ClientFilter(status: .active, entityType: .sCorp1120S, tag: "Referral", onlyWithOpenWork: true)
        XCTAssertTrue(filter.matches(match))
        XCTAssertFalse(filter.matches(wrongStatus))
        XCTAssertFalse(filter.matches(noWork))
        XCTAssertEqual(filter.activeCount, 4)
    }

    func testEmptyFilterMatchesEverything() {
        XCTAssertTrue(ClientFilter().isEmpty)
        XCTAssertTrue(ClientFilter().matches(summary()))
    }

    func testSearchMatchesNameCompanyEmailAndTags() {
        let client = summary(name: "Dana Lee", tags: ["referral"], email: "dana@acme.com", company: "Acme")
        var filter = ClientFilter()
        for query in ["dana", "acme", "referral", "ACME.COM"] {
            filter.search = query
            XCTAssertTrue(filter.matches(client), query)
        }
        filter.search = "zzz"
        XCTAssertFalse(filter.matches(client))
        XCTAssertTrue(ClientFilter(search: "zzz").isEmpty, "search alone isn't a saved filter")
    }

    // MARK: Activity

    func testLastContactLabels() {
        let now = date(2026, 9, 30)
        XCTAssertEqual(ClientActivity.lastContactLabel(nil, now: now, calendar: calendar), "No contact logged")
        XCTAssertEqual(ClientActivity.lastContactLabel(date(2026, 9, 30), now: now, calendar: calendar), "Today")
        XCTAssertEqual(ClientActivity.lastContactLabel(date(2026, 9, 29), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(ClientActivity.lastContactLabel(date(2026, 9, 25), now: now, calendar: calendar), "5 days ago")
        XCTAssertEqual(ClientActivity.lastContactLabel(date(2026, 9, 9), now: now, calendar: calendar), "3 weeks ago")
        XCTAssertEqual(ClientActivity.lastContactLabel(date(2026, 6, 1), now: now, calendar: calendar), "4 months ago")
    }

    // MARK: Weekly review

    func testReviewDueLogic() {
        let now = date(2026, 9, 30)
        XCTAssertTrue(WeeklyReviewPlanner.isDue(lastReview: nil, now: now, calendar: calendar))
        XCTAssertFalse(WeeklyReviewPlanner.isDue(lastReview: date(2026, 9, 25), now: now, calendar: calendar))
        XCTAssertTrue(WeeklyReviewPlanner.isDue(lastReview: date(2026, 9, 23), now: now, calendar: calendar))
    }

    func testQuietClients() {
        let now = date(2026, 9, 30)
        func input(last: Date?, created: Date, work: Bool = true, active: Bool = true) -> WeeklyReviewPlanner.QuietInput {
            .init(id: UUID(), lastContact: last, createdAt: created, hasOpenWork: work, isActive: active)
        }
        let long = input(last: date(2026, 8, 1), created: date(2026, 1, 1))
        let medium = input(last: date(2026, 9, 10), created: date(2026, 1, 1))
        let recent = input(last: date(2026, 9, 28), created: date(2026, 1, 1))
        let newClient = input(last: nil, created: date(2026, 9, 25))
        let neverContactedOld = input(last: nil, created: date(2026, 7, 1))
        let noWork = input(last: date(2026, 1, 1), created: date(2026, 1, 1), work: false)
        let inactive = input(last: date(2026, 1, 1), created: date(2026, 1, 1), active: false)

        let quiet = WeeklyReviewPlanner.quietClients(
            [recent, medium, long, newClient, neverContactedOld, noWork, inactive],
            now: now, calendar: calendar
        )
        // Longest silence first; never-contacted is measured from when they were added.
        XCTAssertEqual(quiet, [neverContactedOld.id, long.id, medium.id])
    }

    func testQuietClientsSkipsThoseWithAFutureFollowUp() {
        let now = date(2026, 9, 30)
        let scheduled = WeeklyReviewPlanner.QuietInput(
            id: UUID(), lastContact: date(2026, 8, 1), createdAt: date(2026, 1, 1),
            hasOpenWork: true, isActive: true, followUpDate: date(2026, 10, 15)
        )
        let overdueFollowUp = WeeklyReviewPlanner.QuietInput(
            id: UUID(), lastContact: date(2026, 8, 1), createdAt: date(2026, 1, 1),
            hasOpenWork: true, isActive: true, followUpDate: date(2026, 9, 20)
        )
        let quiet = WeeklyReviewPlanner.quietClients([scheduled, overdueFollowUp], now: now, calendar: calendar)
        XCTAssertEqual(quiet, [overdueFollowUp.id])
    }

    func testFollowUpPresets() {
        let now = date(2026, 9, 30, hour: 15)
        XCTAssertEqual(FollowUpPreset.tomorrow.date(from: now, calendar: calendar), date(2026, 10, 1))
        XCTAssertEqual(FollowUpPreset.inAWeek.date(from: now, calendar: calendar), date(2026, 10, 7))
        XCTAssertEqual(FollowUpPreset.inTwoWeeks.date(from: now, calendar: calendar), date(2026, 10, 14))
        XCTAssertEqual(FollowUpPreset.inAMonth.date(from: now, calendar: calendar), date(2026, 10, 30))
    }

    func testLoggingContactClearsOnlyDueFollowUps() {
        let now = date(2026, 9, 30)
        XCTAssertTrue(ClientActivity.shouldClearFollowUp(date(2026, 9, 30), now: now, calendar: calendar))
        XCTAssertTrue(ClientActivity.shouldClearFollowUp(date(2026, 9, 1), now: now, calendar: calendar))
        XCTAssertFalse(ClientActivity.shouldClearFollowUp(date(2026, 10, 5), now: now, calendar: calendar))
        XCTAssertFalse(ClientActivity.shouldClearFollowUp(nil, now: now, calendar: calendar))
    }
}

final class FocusHoursTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // 2026-09-30 is a Wednesday; 2026-10-03 a Saturday.

    func testDisabledIsAlwaysWithin() {
        XCTAssertTrue(FocusHours().isWithin(date(2026, 9, 30, hour: 10), calendar: calendar))
    }

    func testWeekdayWindow() {
        let focus = FocusHours(isEnabled: true, startHour: 18, endHour: 22, weekendsAllDay: true)
        XCTAssertFalse(focus.isWithin(date(2026, 9, 30, hour: 10), calendar: calendar))
        XCTAssertTrue(focus.isWithin(date(2026, 9, 30, hour: 19), calendar: calendar))
        XCTAssertFalse(focus.isWithin(date(2026, 9, 30, hour: 22), calendar: calendar))
    }

    func testWeekendsAllDay() {
        let on = FocusHours(isEnabled: true, startHour: 18, endHour: 22, weekendsAllDay: true)
        let off = FocusHours(isEnabled: true, startHour: 18, endHour: 22, weekendsAllDay: false)
        XCTAssertTrue(on.isWithin(date(2026, 10, 3, hour: 9), calendar: calendar))
        XCTAssertFalse(off.isWithin(date(2026, 10, 3, hour: 9), calendar: calendar))
    }

    func testOvernightWindowWraps() {
        let focus = FocusHours(isEnabled: true, startHour: 22, endHour: 2, weekendsAllDay: false)
        XCTAssertTrue(focus.isWithin(date(2026, 9, 30, hour: 23), calendar: calendar))
        XCTAssertTrue(focus.isWithin(date(2026, 10, 1, hour: 1), calendar: calendar))
        XCTAssertFalse(focus.isWithin(date(2026, 9, 30, hour: 12), calendar: calendar))
    }

    func testAlertHourMovesToWindowStartOnWeekdays() {
        let focus = FocusHours(isEnabled: true, startHour: 18, endHour: 22, weekendsAllDay: true)
        XCTAssertEqual(focus.alertHour(on: date(2026, 9, 30, hour: 0), defaultHour: 8, calendar: calendar), 18)
        XCTAssertEqual(focus.alertHour(on: date(2026, 10, 3, hour: 0), defaultHour: 8, calendar: calendar), 8)
        XCTAssertEqual(FocusHours().alertHour(on: date(2026, 9, 30, hour: 0), defaultHour: 8, calendar: calendar), 8)
    }

    func testHourLabel() {
        XCTAssertEqual(FocusHours.hourLabel(0), "12 AM")
        XCTAssertEqual(FocusHours.hourLabel(12), "12 PM")
        XCTAssertEqual(FocusHours.hourLabel(18), "6 PM")
    }
}
