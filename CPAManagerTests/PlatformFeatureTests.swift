import XCTest
import UserNotifications
@testable import CPAManager

final class NotificationActionParserTests: XCTestCase {
    private let id = UUID()

    func testCategoriesByRequestPrefix() {
        XCTAssertEqual(NotificationActionParser.category(forRequestID: "task-\(id)"), NotificationActionParser.taskCategory)
        XCTAssertEqual(NotificationActionParser.category(forRequestID: "followup-\(id)"), NotificationActionParser.followUpCategory)
        XCTAssertEqual(NotificationActionParser.category(forRequestID: "invoice-\(id)"), NotificationActionParser.invoiceCategory)
        XCTAssertNil(NotificationActionParser.category(forRequestID: "project-\(id)"))
        XCTAssertNil(NotificationActionParser.category(forRequestID: "garbage"))
        XCTAssertNil(NotificationActionParser.category(forRequestID: "task-not-a-uuid"))
    }

    func testActionButtons() {
        typealias P = NotificationActionParser
        XCTAssertEqual(P.command(requestID: "task-\(id)", actionID: P.doneAction), .completeTask(id))
        XCTAssertEqual(P.command(requestID: "task-\(id)", actionID: P.snoozeAction), .snoozeTask(id))
        XCTAssertEqual(P.command(requestID: "followup-\(id)", actionID: P.contactedAction), .markContacted(id))
        XCTAssertEqual(P.command(requestID: "followup-\(id)", actionID: P.nextWeekAction), .remindClientNextWeek(id))
        XCTAssertEqual(P.command(requestID: "invoice-\(id)", actionID: P.paidAction), .markInvoicePaid(id))
    }

    func testActionsOnTheWrongKindOfNotificationAreIgnored() {
        typealias P = NotificationActionParser
        XCTAssertNil(P.command(requestID: "invoice-\(id)", actionID: P.doneAction))
        XCTAssertNil(P.command(requestID: "task-\(id)", actionID: P.paidAction))
        XCTAssertNil(P.command(requestID: "task-\(id)", actionID: "SOMETHING_ELSE"))
    }

    func testTappingTheNotificationOpensTheRightRecord() {
        typealias P = NotificationActionParser
        let tap = UNNotificationDefaultActionIdentifier
        XCTAssertEqual(P.command(requestID: "task-\(id)", actionID: tap), .open(.task(id)))
        XCTAssertEqual(P.command(requestID: "project-\(id)", actionID: tap), .open(.project(id)))
        XCTAssertEqual(P.command(requestID: "followup-\(id)", actionID: tap), .open(.client(id)))
        XCTAssertEqual(P.command(requestID: "invoice-\(id)", actionID: tap), .open(.invoice(id)))
        XCTAssertNil(P.command(requestID: "mystery-\(id)", actionID: tap))
    }
}

final class BriefingTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testClientBriefingWithEverything() {
        let followUp = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now))!
        let text = Briefing.client(name: "Dana Lee", openProjects: 2, lastContact: "5 days ago", followUp: followUp, outstanding: 200)
        XCTAssertTrue(text.hasPrefix("Dana Lee: 2 open projects, last contact 5 days ago, follow-up "))
        XCTAssertTrue(text.contains("$200.00 outstanding") || text.contains("200"))
        XCTAssertTrue(text.hasSuffix("."))
    }

    func testClientBriefingWhenQuiet() {
        let text = Briefing.client(name: "Sam", openProjects: 0, lastContact: "No contact logged", followUp: nil, outstanding: 0)
        XCTAssertEqual(text, "Sam: no open projects, no contact logged.")
        XCTAssertEqual(Briefing.client(name: "Sam", openProjects: 1, lastContact: "Today", followUp: nil, outstanding: 0),
                       "Sam: 1 open project, last contact today.")
    }

    func testTodayBriefing() {
        XCTAssertEqual(Briefing.today(overdue: 0, dueToday: 0, inbox: 0, next: []), "Nothing overdue or due today.")
        XCTAssertEqual(
            Briefing.today(overdue: 2, dueToday: 3, inbox: 4, next: ["Call Smith", "Send 1099s", "Review", "Extra"]),
            "2 overdue and 3 due today. Next: Call Smith, Send 1099s, Review. 4 items in your inbox."
        )
        XCTAssertEqual(Briefing.today(overdue: 0, dueToday: 1, inbox: 1, next: []), "1 due today. 1 item in your inbox.")
    }
}
