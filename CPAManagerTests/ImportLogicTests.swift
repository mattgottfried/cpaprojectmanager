import XCTest
@testable import CPAManager

final class CSVParserTests: XCTestCase {
    func testQuotesCommasNewlinesAndEscapedQuotes() {
        let text = "name,notes\r\n\"Reyes, Dana\",\"said \"\"hi\"\"\nthen left\"\nPlain,ok\n"
        let rows = CSVParser.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1], ["Reyes, Dana", "said \"hi\"\nthen left"])
        XCTAssertEqual(rows[2], ["Plain", "ok"])
    }

    func testBOMBlankRowsAndNoTrailingNewline() {
        let rows = CSVParser.parse("\u{FEFF}a,b\n\n , \nx,y")
        XCTAssertEqual(rows, [["a", "b"], ["x", "y"]])
        XCTAssertEqual(CSVParser.parse(""), [])
    }

    func testRoundTripWithCSVWriter() {
        let tricky = "He said \"go\", then\nleft"
        let line = [CSVWriter.escape("a"), CSVWriter.escape(tricky)].joined(separator: ",")
        XCTAssertEqual(CSVParser.parse(line), [["a", tricky]])
    }
}

final class ClientImportTests: XCTestCase {
    func testQuickBooksStyleHeadersAndDedupe() {
        let rows = CSVParser.parse("""
        Customer,Company,Email,Phone Numbers,Notes
        Dana Reyes,Reyes LLC,DANA@X.COM,555-1234,VIP
        Acme Co,Acme Co,,555-9999,
        Dana Again,,dana@x.com,,
        ,,,,
        Solo,,solo@x.com,,
        """)
        let plan = ClientImport.plan(rows: rows, existingEmails: ["solo@x.com"], existingNames: [])
        XCTAssertEqual(plan.records.map(\.name), ["Dana Reyes", "Acme Co"])
        XCTAssertEqual(plan.records[0].email, "dana@x.com", "emails are lowercased")
        XCTAssertEqual(plan.records[0].company, "Reyes LLC")
        XCTAssertEqual(plan.records[1].company, "", "company equal to the name isn't duplicated")
        XCTAssertEqual(plan.skipped, [ImportSkip(row: 4, reason: "Email already exists"), ImportSkip(row: 5, reason: "Email already exists")])
    }

    func testMissingNameColumn() {
        let plan = ClientImport.plan(rows: CSVParser.parse("Email,Phone\na@x.com,1"), existingEmails: [], existingNames: [])
        XCTAssertNotNil(plan.missingRequiredColumn)
        XCTAssertTrue(plan.records.isEmpty)
    }

    func testEntityAndTagMapping() {
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "S Corp"), EntityType.sCorp1120S.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "1120-S"), EntityType.sCorp1120S.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "C-Corp (1120)"), EntityType.cCorp1120.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "Partnership"), EntityType.partnership1065.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "Individual"), EntityType.individual1040.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: ""), EntityType.individual1040.rawValue)
        XCTAssertEqual(ClientImport.entityTypeRaw(from: "Sole prop"), EntityType.other.rawValue)
        let rows = CSVParser.parse("Name,Tags\nA,\"referral; s-corp | vip\"")
        XCTAssertEqual(ClientImport.plan(rows: rows, existingEmails: [], existingNames: []).records[0].tags, ["referral", "s-corp", "vip"])
    }
}

final class TimeImportTests: XCTestCase {
    func testHoursParsing() {
        XCTAssertEqual(TimeImport.hours(from: "1.5"), 1.5)
        XCTAssertEqual(TimeImport.hours(from: "1,5"), 1.5)
        XCTAssertEqual(TimeImport.hours(from: "1:30"), 1.5)
        XCTAssertEqual(TimeImport.hours(from: "1h 30m"), 1.5)
        XCTAssertEqual(TimeImport.hours(from: "45m"), 0.75)
        XCTAssertNil(TimeImport.hours(from: "0"))
        XCTAssertNil(TimeImport.hours(from: "abc"))
        XCTAssertNil(TimeImport.hours(from: ""))
    }

    func testDateParsing() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let expected = cal.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        XCTAssertEqual(TimeImport.parseDate("2026-03-09", calendar: cal), expected)
        XCTAssertEqual(TimeImport.parseDate("3/9/2026", calendar: cal), expected)
        XCTAssertEqual(TimeImport.parseDate("Mar 9, 2026", calendar: cal), expected)
        XCTAssertNil(TimeImport.parseDate("someday", calendar: cal))
    }

    func testPlanSkipsBadRowsAndReadsOptionalColumns() {
        let rows = CSVParser.parse("""
        Date,Client,Project,Hours,Rate,Billable,Notes
        2026-03-09,Dana Reyes,Reyes 1040,1:30,$200,yes,Call
        not a date,X,,1,,,
        2026-03-10,Acme,,zero,,,
        2026-03-11,Acme,,2,,no,
        """)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let plan = TimeImport.plan(rows: rows, calendar: cal)
        XCTAssertEqual(plan.records.count, 2)
        XCTAssertEqual(plan.records[0].rate, 200)
        XCTAssertEqual(plan.records[0].hours, 1.5)
        XCTAssertTrue(plan.records[0].isBillable)
        XCTAssertFalse(plan.records[1].isBillable)
        XCTAssertNil(plan.records[1].rate)
        XCTAssertEqual(plan.skipped.map(\.row), [3, 4])
    }

    func testMissingRequiredColumns() {
        XCTAssertNotNil(TimeImport.plan(rows: CSVParser.parse("Client,Hours\nA,1")).missingRequiredColumn)
        XCTAssertNotNil(TimeImport.plan(rows: CSVParser.parse("Date,Client\n2026-01-01,A")).missingRequiredColumn)
    }
}
