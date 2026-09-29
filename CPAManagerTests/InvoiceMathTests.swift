import XCTest
@testable import CPAManager

final class InvoiceMathTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testBalanceIgnoresFloatDust() {
        XCTAssertEqual(InvoiceMath.balance(total: 0.3, payments: [0.1, 0.2]), 0)
        XCTAssertEqual(InvoiceMath.balance(total: 1250, payments: [500]), 750)
        XCTAssertEqual(InvoiceMath.balance(total: 100, payments: [150]), 0, "overpayment never goes negative")
    }

    func testPaidInFull() {
        XCTAssertTrue(InvoiceMath.isPaidInFull(total: 300, payments: [100, 200]))
        XCTAssertFalse(InvoiceMath.isPaidInFull(total: 300, payments: [100]))
        XCTAssertFalse(InvoiceMath.isPaidInFull(total: 0, payments: []), "a $0 invoice isn't 'paid'")
    }

    func testOverdueOnlyForSentInvoicesWithABalance() {
        let now = date(2026, 9, 30)
        let past = date(2026, 9, 1)
        XCTAssertTrue(InvoiceMath.isOverdue(status: .sent, dueDate: past, balance: 50, now: now, calendar: calendar))
        XCTAssertFalse(InvoiceMath.isOverdue(status: .draft, dueDate: past, balance: 50, now: now, calendar: calendar))
        XCTAssertFalse(InvoiceMath.isOverdue(status: .paid, dueDate: past, balance: 0, now: now, calendar: calendar))
        XCTAssertFalse(InvoiceMath.isOverdue(status: .sent, dueDate: past, balance: 0, now: now, calendar: calendar))
        XCTAssertFalse(InvoiceMath.isOverdue(status: .sent, dueDate: date(2026, 9, 30), balance: 50, now: now, calendar: calendar), "due today isn't late yet")
    }

    func testAgingBuckets() {
        let now = date(2026, 9, 30)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 10, 5), now: now, calendar: calendar), .current)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 9, 30), now: now, calendar: calendar), .current)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 9, 20), now: now, calendar: calendar), .days1to30)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 8, 15), now: now, calendar: calendar), .days31to60)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 7, 20), now: now, calendar: calendar), .days61to90)
        XCTAssertEqual(InvoiceMath.agingBucket(dueDate: date(2026, 5, 1), now: now, calendar: calendar), .over90)
    }

    func testUnrecordedQuickBooksPayment() {
        XCTAssertEqual(InvoiceMath.unrecordedQBOPayment(qboTotal: 1000, qboBalance: 0, locallyPaid: 0), 1000)
        XCTAssertEqual(InvoiceMath.unrecordedQBOPayment(qboTotal: 1000, qboBalance: 400, locallyPaid: 200), 400)
        XCTAssertNil(InvoiceMath.unrecordedQBOPayment(qboTotal: 1000, qboBalance: 400, locallyPaid: 600))
        XCTAssertNil(InvoiceMath.unrecordedQBOPayment(qboTotal: 1000, qboBalance: 1000, locallyPaid: 0))
    }

    func testReminderEmail() throws {
        let body = InvoiceMath.reminderBody(clientName: "Dana", number: "INV-0042", balance: 750, dueDate: date(2026, 9, 1), firm: "Gottfried CPA")
        XCTAssertTrue(body.contains("INV-0042"))
        XCTAssertTrue(body.contains("Hi Dana"))
        XCTAssertTrue(body.hasSuffix("Gottfried CPA"))

        let url = try XCTUnwrap(InvoiceMath.reminderURL(to: "dana@acme.com", subject: "Invoice INV-0042", body: "Hi & thanks"))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:dana@acme.com?"))
        XCTAssertTrue(url.absoluteString.contains("subject=Invoice"))
    }

    func testDecodesQuickBooksBalanceResponse() throws {
        let json = #"{"QueryResponse":{"Invoice":[{"Id":"145","Balance":250.5,"TotalAmt":1000}]}}"#
        let decoded = try JSONDecoder().decode(QBOInvoiceBalanceResponse.self, from: Data(json.utf8))
        let row = try XCTUnwrap(decoded.QueryResponse.Invoice?.first)
        XCTAssertEqual(row.Id, "145")
        XCTAssertEqual(row.Balance, 250.5)
        XCTAssertEqual(row.TotalAmt, 1000)
    }
}
