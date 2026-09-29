import XCTest
@testable import CPAManager

final class GoogleOAuthTests: XCTestCase {
    func testRedirectSchemeIsReversedClientID() {
        XCTAssertEqual(
            GoogleOAuth.redirectScheme(clientID: "123456-abcdef.apps.googleusercontent.com"),
            "com.googleusercontent.apps.123456-abcdef"
        )
        XCTAssertEqual(
            GoogleOAuth.redirectURI(clientID: " 123456-abcdef.apps.googleusercontent.com "),
            "com.googleusercontent.apps.123456-abcdef:/oauth2redirect"
        )
        XCTAssertNil(GoogleOAuth.redirectScheme(clientID: "not-a-google-client-id"))
        XCTAssertNil(GoogleOAuth.redirectScheme(clientID: ".apps.googleusercontent.com"))
    }

    /// RFC 7636, Appendix B.
    func testPKCEChallengeMatchesRFCVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(GoogleOAuth.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierIsURLSafeAndLongEnough() {
        let verifier = GoogleOAuth.makeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
        XCTAssertNotEqual(verifier, GoogleOAuth.makeVerifier())
    }

    func testAuthorizationURLCarriesPKCEAndOfflineAccess() throws {
        let url = try XCTUnwrap(GoogleOAuth.authorizationURL(
            clientID: "abc.apps.googleusercontent.com",
            redirectURI: "com.googleusercontent.apps.abc:/oauth2redirect",
            state: "xyz", challenge: "chal"
        ))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), "chal")
        XCTAssertEqual(value("access_type"), "offline")
        XCTAssertEqual(value("state"), "xyz")
        XCTAssertTrue(value("scope")?.contains("gmail.readonly") == true)
        XCTAssertTrue(value("scope")?.contains("calendar.events") == true)
    }
}

final class GmailParsingTests: XCTestCase {
    private let sampleJSON = """
    {
      "id": "18c1",
      "threadId": "18c0",
      "snippet": "  Attached are the Q3 numbers  ",
      "internalDate": "1790000000000",
      "payload": { "headers": [
        {"name": "From", "value": "\\"Dana Lee\\" <dana@acme.com>"},
        {"name": "subject", "value": "Re: Q3 numbers"},
        {"name": "Date", "value": "Mon, 28 Sep 2026 10:00:00 -0400"}
      ]}
    }
    """

    func testParsesMessageMetadata() throws {
        let message = try JSONDecoder().decode(GmailMessage.self, from: Data(sampleJSON.utf8))
        let email = GmailParsing.parse(message)
        XCTAssertEqual(email.id, "18c1")
        XCTAssertEqual(email.threadID, "18c0")
        XCTAssertEqual(email.subject, "Re: Q3 numbers", "header names are case-insensitive")
        XCTAssertEqual(email.senderName, "Dana Lee")
        XCTAssertEqual(email.senderEmail, "dana@acme.com")
        XCTAssertEqual(email.snippet, "Attached are the Q3 numbers")
        XCTAssertEqual(email.date, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(GmailParsing.inboxText(email), "Re: Q3 numbers — Dana Lee")
    }

    func testSenderFormats() {
        XCTAssertEqual(GmailParsing.senderParts("Dana Lee <dana@acme.com>").name, "Dana Lee")
        XCTAssertEqual(GmailParsing.senderParts("Dana Lee <dana@acme.com>").email, "dana@acme.com")
        XCTAssertEqual(GmailParsing.senderParts("dana@acme.com").email, "dana@acme.com")
        XCTAssertEqual(GmailParsing.senderParts("dana@acme.com").name, "")
        XCTAssertEqual(GmailParsing.senderParts("Support").name, "Support")
    }

    func testMissingHeadersFallBackGracefully() throws {
        let json = #"{"id": "m1"}"#
        let email = GmailParsing.parse(try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8)))
        XCTAssertEqual(email.subject, "(no subject)")
        XCTAssertEqual(email.threadID, "m1")
        XCTAssertEqual(GmailParsing.inboxText(email), "(no subject)")
        XCTAssertNil(email.date)
    }

    func testListResponseAndLinks() throws {
        let json = #"{"messages":[{"id":"a","threadId":"t1"},{"id":"b","threadId":"t2"}],"resultSizeEstimate":2}"#
        let list = try JSONDecoder().decode(GmailListResponse.self, from: Data(json.utf8))
        XCTAssertEqual(list.messages?.map { $0.id }, ["a", "b"])
        XCTAssertNil(try JSONDecoder().decode(GmailListResponse.self, from: Data("{}".utf8)).messages)
        XCTAssertEqual(GmailParsing.webLink(threadID: "t1"), "https://mail.google.com/mail/u/0/#all/t1")
        XCTAssertEqual(GmailParsing.externalID("a"), "gmail:a")
    }

    func testClientMatchingAndQuery() {
        XCTAssertEqual(GmailParsing.matchClientIndex(senderEmail: "DANA@acme.com", clientEmails: ["x@y.com", " dana@Acme.com "]), 1)
        XCTAssertNil(GmailParsing.matchClientIndex(senderEmail: "", clientEmails: [""]))
        XCTAssertEqual(GmailParsing.effectiveQuery("  "), GmailParsing.defaultQuery)
        XCTAssertEqual(GmailParsing.effectiveQuery("label:cpa"), "label:cpa")
    }
}

final class CalendarParsingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func decode(_ json: String) throws -> GoogleEventsResponse {
        try JSONDecoder().decode(GoogleEventsResponse.self, from: Data(json.utf8))
    }

    func testParsesTimedAndAllDayEventsAndSkipsOursAndCancelled() throws {
        let response = try decode("""
        {"items":[
          {"id":"e1","summary":"Client call","start":{"dateTime":"2026-09-30T14:00:00Z"},"end":{"dateTime":"2026-09-30T14:30:00Z"},"location":"Zoom","htmlLink":"https://calendar.google.com/e1"},
          {"id":"e2","summary":"Conference","start":{"date":"2026-09-30"},"end":{"date":"2026-10-01"}},
          {"id":"cpa0123456789abcdef0123456789abcdef","summary":"Task we pushed","start":{"date":"2026-09-30"},"end":{"date":"2026-10-01"}},
          {"id":"e3","summary":"Nope","status":"cancelled","start":{"dateTime":"2026-09-30T09:00:00Z"}},
          {"id":"e4","start":{"dateTime":"2026-09-30T08:00:00Z"}}
        ]}
        """)
        let events = CalendarParsing.events(from: response, calendar: calendar)
        XCTAssertEqual(events.map { $0.id }, ["e2", "e4", "e1"], "all-day first, then by start time")
        XCTAssertEqual(events.first { $0.id == "e4" }?.title, "(no title)")
        let call = try XCTUnwrap(events.first { $0.id == "e1" })
        XCTAssertEqual(call.location, "Zoom")
        XCTAssertEqual(call.link, URL(string: "https://calendar.google.com/e1"))
        XCTAssertFalse(call.isAllDay)
        XCTAssertTrue(try XCTUnwrap(events.first { $0.id == "e2" }).isAllDay)
    }

    func testEventsOnADay() throws {
        let response = try decode("""
        {"items":[
          {"id":"a","summary":"Today","start":{"dateTime":"2026-09-30T14:00:00Z"}},
          {"id":"b","summary":"Tomorrow","start":{"dateTime":"2026-10-01T14:00:00Z"}},
          {"id":"c","summary":"All day today","start":{"date":"2026-09-30"},"end":{"date":"2026-10-01"}},
          {"id":"d","summary":"All day tomorrow","start":{"date":"2026-10-01"},"end":{"date":"2026-10-02"}}
        ]}
        """)
        let events = CalendarParsing.events(from: response, calendar: calendar)
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 9))!
        let today = CalendarParsing.events(events, on: day, calendar: calendar)
        XCTAssertEqual(Set(today.map { $0.id }), ["a", "c"])
    }
}

final class CalendarSyncPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func item(_ title: String, day: Int, id: UUID = UUID()) -> CalendarSyncItem {
        CalendarSyncItem(id: id, title: title, day: calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!, notes: "")
    }

    func testEventIDIsValidBase32HexWithOurPrefix() {
        let id = item("x", day: 1).eventID
        XCTAssertTrue(id.hasPrefix("cpa"))
        XCTAssertEqual(id.count, 35)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuv0123456789")
        XCTAssertNil(id.rangeOfCharacter(from: allowed.inverted))
    }

    func testPlanCreatesUpdatesAndDeletes() {
        let unchanged = item("Same", day: 5)
        let renamed = item("New title", day: 6)
        let brandNew = item("Fresh", day: 7)

        let synced: [String: String] = [
            unchanged.eventID: unchanged.signature(calendar: calendar),
            renamed.eventID: "Old title|2026-10-06|",
            "cpa-gone": "x",
        ]
        let plan = CalendarSyncPlanner.plan(items: [unchanged, renamed, brandNew], synced: synced, calendar: calendar)
        XCTAssertEqual(plan.creates, [brandNew])
        XCTAssertEqual(plan.updates, [renamed])
        XCTAssertEqual(plan.deletes, ["cpa-gone"])
    }

    func testMovingTheDateCountsAsAnUpdate() {
        let id = UUID()
        let before = item("Task", day: 5, id: id)
        let after = item("Task", day: 9, id: id)
        let plan = CalendarSyncPlanner.plan(items: [after], synced: [before.eventID: before.signature(calendar: calendar)], calendar: calendar)
        XCTAssertEqual(plan.updates, [after])
        XCTAssertTrue(plan.creates.isEmpty)
    }

    func testAllDayBodyEndsTheNextDay() throws {
        let body = CalendarSyncPlanner.eventBody(item("Task", day: 5), calendar: calendar, includeID: true)
        XCTAssertEqual((body["start"] as? [String: String])?["date"], "2026-10-05")
        XCTAssertEqual((body["end"] as? [String: String])?["date"], "2026-10-06")
        XCTAssertEqual(body["transparency"] as? String, "transparent")
        XCTAssertNotNil(body["id"])
        XCTAssertNil(CalendarSyncPlanner.eventBody(item("Task", day: 5), calendar: calendar, includeID: false)["id"])
    }

    func testDayStringPadsAndHandlesMonthEnd() {
        let d = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        XCTAssertEqual(CalendarSyncPlanner.dayString(d, calendar: calendar), "2026-01-03")
        let last = item("End of month", day: 31)
        let body = CalendarSyncPlanner.eventBody(last, calendar: calendar, includeID: false)
        XCTAssertEqual((body["end"] as? [String: String])?["date"], "2026-11-01")
    }
}
