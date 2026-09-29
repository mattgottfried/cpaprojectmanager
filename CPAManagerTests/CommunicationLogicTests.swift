import XCTest
@testable import CPAManager

final class MergeFieldsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testRenderReplacesKnownTokensCaseInsensitivelyAndKeepsUnknown() {
        let out = MergeFields.render("Hi {FirstName}, re {taxyear} — {mystery} {", values: ["firstname": "Dana", "taxyear": "2025"])
        XCTAssertEqual(out, "Hi Dana, re 2025 — {mystery} {")
    }

    func testRenderHandlesEmptyValuesAndAdjacentTokens() {
        XCTAssertEqual(MergeFields.render("{a}{b}", values: ["a": "x", "b": ""]), "x")
        XCTAssertEqual(MergeFields.render("no tokens", values: [:]), "no tokens")
    }

    func testUnknownTokens() {
        let known = Set(MergeFields.tokens.map { $0.token })
        XCTAssertEqual(MergeFields.unknownTokens(in: "{client} {typo} {typo} {two words}", known: known), ["typo"])
    }

    func testValues() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        let values = MergeFields.values(clientName: "Dana Reyes", company: "Reyes LLC", email: "d@x.com", firmName: "GP CPA", now: now, fee: "$450", calendar: calendar)
        XCTAssertEqual(values["firstname"], "Dana")
        XCTAssertEqual(values["taxyear"], "2025")
        XCTAssertEqual(values["date"], "March 9, 2026")
        XCTAssertEqual(values["fee"], "$450")
    }

    func testStarterTemplatesOnlyUseKnownTokens() {
        let known = Set(MergeFields.tokens.map { $0.token })
        for letter in TemplateStarters.letters {
            XCTAssertTrue(MergeFields.unknownTokens(in: letter.body, known: known).isEmpty, letter.name)
        }
        for email in TemplateStarters.emails {
            XCTAssertTrue(MergeFields.unknownTokens(in: email.subject + email.body, known: known).isEmpty, email.name)
        }
    }

    func testMailto() {
        let url = MailtoBuilder.url(to: "d@x.com", subject: "Hi & bye", body: "Line 1\nLine 2")
        XCTAssertEqual(url?.scheme, "mailto")
        let comps = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.path, "d@x.com")
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "subject" }?.value, "Hi & bye")
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "body" }?.value, "Line 1\nLine 2")
        XCTAssertNil(MailtoBuilder.url(to: "", subject: "", body: ""))
        XCTAssertNil(MailtoBuilder.url(to: "not an address", subject: "", body: ""))
    }
}

final class MarkdownBlocksTests: XCTestCase {
    func testParseLines() {
        XCTAssertEqual(MarkdownBlocks.parseLine("# Title"), .heading(level: 1, text: "Title"))
        XCTAssertEqual(MarkdownBlocks.parseLine("### Small"), .heading(level: 3, text: "Small"))
        XCTAssertEqual(MarkdownBlocks.parseLine("#hashtag"), .paragraph(text: "#hashtag"))
        XCTAssertEqual(MarkdownBlocks.parseLine("#### too deep"), .paragraph(text: "#### too deep"))
        XCTAssertEqual(MarkdownBlocks.parseLine("- [ ] call IRS"), .checkbox(checked: false, text: "call IRS"))
        XCTAssertEqual(MarkdownBlocks.parseLine("- [x] done"), .checkbox(checked: true, text: "done"))
        XCTAssertEqual(MarkdownBlocks.parseLine("* item"), .bullet(text: "item"))
        XCTAssertEqual(MarkdownBlocks.parseLine("   "), .blank)
        XCTAssertEqual(MarkdownBlocks.parseLine("just text"), .paragraph(text: "just text"))
    }

    func testToggleCheckboxRoundTripsAndIgnoresOtherLines() {
        let text = "# Notes\n- [ ] one\n- [x] two\nplain"
        let once = MarkdownBlocks.toggleCheckbox(in: text, lineIndex: 1)
        XCTAssertEqual(once, "# Notes\n- [x] one\n- [x] two\nplain")
        XCTAssertEqual(MarkdownBlocks.toggleCheckbox(in: once, lineIndex: 2), "# Notes\n- [x] one\n- [ ] two\nplain")
        XCTAssertEqual(MarkdownBlocks.toggleCheckbox(in: text, lineIndex: 3), text)
        XCTAssertEqual(MarkdownBlocks.toggleCheckbox(in: text, lineIndex: 99), text)
    }

    func testProgressAndStructure() {
        let text = "- [x] a\n- [ ] b\n- [ ] c"
        let progress = MarkdownBlocks.checkboxProgress(text)
        XCTAssertEqual(progress.done, 1)
        XCTAssertEqual(progress.total, 3)
        XCTAssertTrue(MarkdownBlocks.hasStructure(text))
        XCTAssertFalse(MarkdownBlocks.hasStructure("Talked about the 2025 return.\nCall back Tuesday."))
    }
}

final class OccasionsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.startOfDay(for: date(y, m, d))
    }

    func testNextOccurrenceThisYearOrNext() {
        let born = date(1980, 6, 15)
        XCTAssertEqual(Occasions.nextOccurrence(of: born, from: date(2026, 6, 1), calendar: calendar), day(2026, 6, 15))
        XCTAssertEqual(Occasions.nextOccurrence(of: born, from: date(2026, 6, 15), calendar: calendar), day(2026, 6, 15), "today counts")
        XCTAssertEqual(Occasions.nextOccurrence(of: born, from: date(2026, 6, 16), calendar: calendar), day(2027, 6, 15))
    }

    func testLeapDayFallsOnFeb28InCommonYears() {
        let leap = date(2000, 2, 29)
        XCTAssertEqual(Occasions.nextOccurrence(of: leap, from: date(2027, 1, 10), calendar: calendar), day(2027, 2, 28))
        XCTAssertEqual(Occasions.nextOccurrence(of: leap, from: date(2028, 1, 10), calendar: calendar), day(2028, 2, 29))
    }

    func testUpcomingWindowOrderYearsAndAcknowledgement() {
        let a = UUID(), b = UUID(), c = UUID()
        let sources = [
            OccasionSource(clientID: a, clientName: "Alice", birthday: date(1990, 6, 17), anniversary: date(2021, 6, 15),
                           birthdayAckYear: 0, anniversaryAckYear: 2026, isActive: true),
            OccasionSource(clientID: b, clientName: "Bob", birthday: date(1985, 6, 30), anniversary: nil,
                           birthdayAckYear: 0, anniversaryAckYear: 0, isActive: true),
            OccasionSource(clientID: c, clientName: "Inactive", birthday: date(1970, 6, 15), anniversary: nil,
                           birthdayAckYear: 0, anniversaryAckYear: 0, isActive: false),
        ]
        let result = Occasions.upcoming(sources, now: date(2026, 6, 15), withinDays: 3, calendar: calendar)
        XCTAssertEqual(result.map { $0.clientName }, ["Alice", "Alice"])
        XCTAssertEqual(result[0].kind, .anniversary)
        XCTAssertEqual(result[0].daysAway, 0)
        XCTAssertEqual(result[0].years, 5)
        XCTAssertTrue(result[0].acknowledged)
        XCTAssertEqual(result[1].kind, .birthday)
        XCTAssertEqual(result[1].daysAway, 2)
        XCTAssertNil(result[1].years, "birthdays never show an age")
        XCTAssertFalse(result[1].acknowledged)

        let wider = Occasions.upcoming(sources, now: date(2026, 6, 15), withinDays: 20, calendar: calendar)
        XCTAssertEqual(wider.count, 3)
    }

    func testOrdinalAndTitles() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 101, 111].map(Occasions.ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "101st", "111th"])
        let occasion = Occasion(clientID: UUID(), clientName: "Alice", kind: .anniversary, date: .now, daysAway: 0, years: 1, acknowledged: false)
        XCTAssertEqual(Occasions.title(for: occasion), "Alice — 1st year as a client")
    }
}
