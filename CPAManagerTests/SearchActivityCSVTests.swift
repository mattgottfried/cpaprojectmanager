import XCTest
@testable import CPAManager

final class GlobalSearchTests: XCTestCase {
    private func doc(_ id: String, _ kind: SearchDoc.Kind, _ title: String, sub: String = "", keys: String = "") -> SearchDoc {
        SearchDoc(id: id, kind: kind, title: title, subtitle: sub, keywords: keys)
    }

    private var docs: [SearchDoc] {
        [
            doc("c1", .client, "Dana Lee", sub: "S-Corp", keys: "dana@acme.com referral"),
            doc("c2", .client, "Acme Holdings", keys: "delaney"),
            doc("p1", .project, "Lee 2025 Form 1040", sub: "Dana Lee"),
            doc("t1", .task, "Call Dana about the 1099s"),
            doc("n1", .note, "Talked with Dana Lee about extension", sub: "Call"),
        ]
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertTrue(GlobalSearch.search(docs, query: "  ").isEmpty)
    }

    func testTitlePrefixBeatsMidTitleBeatsSubtitle() {
        let hits = GlobalSearch.search(docs, query: "dana")
        XCTAssertEqual(hits.first?.doc.id, "c1", "prefix match on a client title wins")
        XCTAssertTrue(hits.map { $0.doc.id }.contains("p1"), "subtitle match still found")
        let ids = hits.map { $0.doc.id }
        XCTAssertLessThan(ids.firstIndex(of: "t1")!, ids.firstIndex(of: "p1")!, "word-in-title outranks subtitle")
    }

    func testAllWordsMustMatch() {
        let hits = GlobalSearch.search(docs, query: "dana 1099")
        XCTAssertEqual(hits.map { $0.doc.id }, ["t1"])
    }

    func testKeywordsAreSearchableButRankLow() {
        let hits = GlobalSearch.search(docs, query: "referral")
        XCTAssertEqual(hits.map { $0.doc.id }, ["c1"])
        XCTAssertEqual(GlobalSearch.search(docs, query: "dana@acme").first?.doc.id, "c1")
    }

    func testCaseAccentsAndPunctuationAreIgnored() {
        XCTAssertEqual(GlobalSearch.normalize("  Café—DANA, Lee! "), "cafe dana lee")
        XCTAssertEqual(GlobalSearch.search(docs, query: "DANA!!").first?.doc.id, "c1")
    }

    func testExactTitleWinsAndLimitApplies() {
        XCTAssertEqual(GlobalSearch.search(docs, query: "dana lee").first?.doc.id, "c1")
        XCTAssertEqual(GlobalSearch.search(docs, query: "a", limit: 2).count, 2)
    }

    func testDeepLinkRoundTrip() {
        let id = UUID()
        for link in [DeepLink.client(id), .project(id), .task(id), .invoice(id)] {
            XCTAssertEqual(DeepLink(identifier: link.identifier), link)
        }
        XCTAssertNil(DeepLink(identifier: "client:not-a-uuid"))
        XCTAssertNil(DeepLink(identifier: "spaceship:\(id.uuidString)"))
        XCTAssertNil(DeepLink(identifier: "nonsense"))
    }
}

final class ActivityFeedTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ d: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: hour))!
    }

    private func event(_ id: String, _ d: Int, _ hour: Int) -> ActivityEvent {
        ActivityEvent(id: id, date: date(d, hour: hour), kind: .taskDone, title: id)
    }

    func testGroupsByDayNewestFirstWithLabels() {
        let now = date(30, hour: 15)
        let sections = ActivityFeed.sections(
            [event("a", 30, 9), event("b", 30, 14), event("c", 29, 8), event("d", 25, 8)],
            days: 7, now: now, calendar: calendar
        )
        XCTAssertEqual(Array(sections.map { $0.label }.prefix(2)), ["Today", "Yesterday"])
        XCTAssertEqual(sections[0].events.map { $0.id }, ["b", "a"])
        XCTAssertEqual(sections.count, 3)
    }

    func testDropsOldAndFutureDays() {
        let now = date(30, hour: 15)
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        let future = ActivityEvent(id: "future", date: tomorrow, kind: .taskDone, title: "future")
        let sections = ActivityFeed.sections([event("old", 20, 9), future, event("today", 30, 10)], days: 3, now: now, calendar: calendar)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.events.map { $0.id }, ["today"])
    }
}

final class CSVWriterTests: XCTestCase {
    func testEscapesCommasQuotesAndNewlines() {
        XCTAssertEqual(CSVWriter.escape("plain"), "plain")
        XCTAssertEqual(CSVWriter.escape("Lee, Dana"), "\"Lee, Dana\"")
        XCTAssertEqual(CSVWriter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVWriter.escape("two\nlines"), "\"two\nlines\"")
    }

    func testFormulaInjectionIsNeutralisedButNumbersSurvive() {
        XCTAssertEqual(CSVWriter.sanitize("=SUM(A1:A9)"), "'=SUM(A1:A9)")
        XCTAssertEqual(CSVWriter.sanitize("+1 555"), "'+1 555")
        XCTAssertEqual(CSVWriter.sanitize("@cmd"), "'@cmd")
        XCTAssertEqual(CSVWriter.sanitize("-5.25"), "-5.25")
        XCTAssertEqual(CSVWriter.sanitize("-dash text"), "'-dash text")
        XCTAssertEqual(CSVWriter.sanitize("normal"), "normal")
        XCTAssertEqual(CSVWriter.sanitize(""), "")
    }

    func testEncodeUsesCRLFAndSanitizesEveryCell() {
        let csv = CSVWriter.encode(headers: ["Name", "Note"], rows: [["Dana", "=HYPERLINK(\"x\")"], ["Lee, J", "ok"]])
        XCTAssertEqual(csv, "Name,Note\r\nDana,\"'=HYPERLINK(\"\"x\"\")\"\r\n\"Lee, J\",ok\r\n")
    }

    func testMoneyAndDateFormatting() {
        XCTAssertEqual(CSVWriter.money(1250), "1250.00")
        XCTAssertEqual(CSVWriter.money(0.1 + 0.2), "0.30")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(CSVWriter.date(calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)), calendar: calendar), "2026-01-05")
        XCTAssertEqual(CSVWriter.date(nil), "")
    }
}
