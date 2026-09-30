import XCTest
import SwiftData
@testable import CPAManager

final class BillingLogicTests: XCTestCase {
    func testQuoteMathUsesIntegerCents() {
        let lines = [
            QuoteLine(detail: "Prep", quantity: 1, rate: 450),
            QuoteLine(detail: "Advice", quantity: 2.5, rate: 150.10),   // 375.25
            QuoteLine(detail: "  ", quantity: 1, rate: 999),             // blank -> ignored by cleaned()
        ]
        XCTAssertEqual(QuoteMath.lineCents(lines[1]), 37525)
        XCTAssertEqual(QuoteMath.totalCents(QuoteMath.cleaned(lines)), 82525)
        XCTAssertEqual(QuoteMath.total(QuoteMath.cleaned(lines)), 825.25, accuracy: 0.0001)
        XCTAssertEqual(QuoteMath.cleaned(lines).count, 2)
    }

    func testNumbering() {
        XCTAssertEqual(QuoteMath.nextNumber(existing: []), 1001)
        XCTAssertEqual(QuoteMath.nextNumber(existing: [1001, 1007, 1003]), 1008)
        XCTAssertEqual(QuoteMath.displayNumber(1008), "Q-1008")
    }

    func testExpiryOnlyForSentQuotes() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let today = cal.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 1))!
        XCTAssertTrue(QuoteMath.isExpired(validUntil: yesterday, status: .sent, now: now, calendar: cal))
        XCTAssertFalse(QuoteMath.isExpired(validUntil: today, status: .sent, now: now, calendar: cal), "valid through the end of that day")
        XCTAssertFalse(QuoteMath.isExpired(validUntil: yesterday, status: .accepted, now: now, calendar: cal))
        XCTAssertFalse(QuoteMath.isExpired(validUntil: nil, status: .sent, now: now, calendar: cal))
    }

    func testRateResolver() {
        XCTAssertEqual(RateResolver.rate(clientOverride: 0, defaultRate: 150), 150)
        XCTAssertEqual(RateResolver.rate(clientOverride: 200, defaultRate: 150), 200)
        XCTAssertEqual(RateResolver.rate(clientOverride: -5, defaultRate: 150), 150)
    }

    func testQuoteTextListsLinesTotalAndValidity() {
        let text = QuoteText.body(
            number: 1002, clientName: "Dana", firmName: "GP CPA",
            date: Date(timeIntervalSince1970: 0), validUntil: Date(timeIntervalSince1970: 86_400),
            lines: [QuoteLine(detail: "Prep", quantity: 1, rate: 450), QuoteLine(detail: "Advice", quantity: 2, rate: 100)],
            notes: "Net 14.", formatDate: { _ in "DATE" }, formatMoney: { String(format: "$%.2f", $0) }
        )
        XCTAssertTrue(text.contains("Quote Q-1002"))
        XCTAssertTrue(text.contains("• Prep — $450.00"))
        XCTAssertTrue(text.contains("• Advice (2 × $100.00) — $200.00"))
        XCTAssertTrue(text.contains("Total: $650.00"))
        XCTAssertTrue(text.contains("Valid until DATE."))
        XCTAssertTrue(text.contains("Net 14."))
    }
}

@MainActor
final class QuoteServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testConvertCreatesNumberedDraftInvoiceOnce() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        context.insert(Invoice(number: 1040, client: client))
        let quote = Quote(number: 1001, client: client, lines: [
            QuoteLine(detail: "Prep", quantity: 1, rate: 450),
            QuoteLine(detail: "", quantity: 1, rate: 5),
        ])
        context.insert(quote)

        let invoice = try XCTUnwrap(QuoteService.convertToInvoice(quote, context: context))
        XCTAssertEqual(invoice.number, 1041)
        XCTAssertEqual(invoice.status, .draft)
        XCTAssertEqual(invoice.lineList.count, 1, "blank lines are dropped")
        XCTAssertEqual(invoice.total, 450)
        XCTAssertEqual(quote.status, .accepted)
        XCTAssertEqual(quote.invoiceID, invoice.id)
        XCTAssertNil(QuoteService.convertToInvoice(quote, context: context), "second conversion is refused")
    }

    func testConvertRefusesQuotesWithoutClientOrLines() throws {
        let context = try makeContext()
        let noClient = Quote(number: 1, client: nil, lines: [QuoteLine(detail: "x", quantity: 1, rate: 1)])
        context.insert(noClient)
        XCTAssertNil(QuoteService.convertToInvoice(noClient, context: context))
        let client = Client(name: "A")
        context.insert(client)
        let empty = Quote(number: 2, client: client, lines: [])
        context.insert(empty)
        XCTAssertNil(QuoteService.convertToInvoice(empty, context: context))
    }

    func testQuoteLinesRoundTripThroughStorage() throws {
        let quote = Quote(number: 5, lines: [QuoteLine(detail: "A", quantity: 2, rate: 10.5)])
        XCTAssertEqual(quote.lines.count, 1)
        XCTAssertEqual(quote.lines[0].detail, "A")
        XCTAssertEqual(quote.total, 21)
    }
}
