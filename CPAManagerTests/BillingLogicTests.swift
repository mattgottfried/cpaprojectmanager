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

final class TaskDependencyTests: XCTestCase {
    func testBlockedWhileBlockerOpen() {
        let a = UUID(), b = UUID()
        XCTAssertTrue(TaskDependencies.isBlocked(blockedByID: b, openTaskIDs: [a, b]))
        XCTAssertFalse(TaskDependencies.isBlocked(blockedByID: b, openTaskIDs: [a]), "done or deleted blocker unblocks")
        XCTAssertFalse(TaskDependencies.isBlocked(blockedByID: nil, openTaskIDs: [a, b]))
    }

    func testCycleDetection() {
        let a = UUID(), b = UUID(), c = UUID()
        // b waits on c; c waits on a.
        let map = [b: c, c: a]
        XCTAssertTrue(TaskDependencies.wouldCreateCycle(taskID: a, newBlockerID: b, blockedBy: map), "a<-b<-c<-a")
        XCTAssertTrue(TaskDependencies.wouldCreateCycle(taskID: a, newBlockerID: a, blockedBy: map), "self")
        XCTAssertFalse(TaskDependencies.wouldCreateCycle(taskID: b, newBlockerID: a, blockedBy: map))
        // A pre-existing loop elsewhere must not hang the check.
        let x = UUID(), y = UUID()
        XCTAssertFalse(TaskDependencies.wouldCreateCycle(taskID: a, newBlockerID: x, blockedBy: [x: y, y: x]))
    }

    func testCandidateBlockersExcludeSelfAndCycles() {
        let a = UUID(), b = UUID(), c = UUID()
        let result = TaskDependencies.candidateBlockers(taskID: a, openTaskIDs: [a, b, c], blockedBy: [b: a])
        XCTAssertEqual(result, [c], "b already waits on a, so a can't wait on b")
    }

    func testChecklistHelpers() {
        var list = TaskChecklist.adding("  call bank ", to: "")
        list = TaskChecklist.adding("send letter", to: list)
        XCTAssertEqual(list, "- [ ] call bank\n- [ ] send letter")
        XCTAssertEqual(TaskChecklist.adding("   ", to: list), list)
        XCTAssertEqual(TaskChecklist.summary(list), "0/2")
        XCTAssertNil(TaskChecklist.summary("just notes"))
        XCTAssertFalse(TaskChecklist.isComplete(list))
        list = MarkdownBlocks.toggleCheckbox(in: list, lineIndex: 0)
        list = MarkdownBlocks.toggleCheckbox(in: list, lineIndex: 1)
        XCTAssertTrue(TaskChecklist.isComplete(list))
        XCTAssertEqual(TaskChecklist.summary(list), "2/2")
    }

    func testPlannerHidesBlockedItemsAndCountsThem() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let open = PlannerItem(id: UUID(), dueDate: today, snoozedUntil: nil, isDone: false, isNextAction: false)
        let blocked = PlannerItem(id: UUID(), dueDate: today, snoozedUntil: nil, isDone: false, isNextAction: false, isBlocked: true)
        let plan = TodayPlanner.plan([open, blocked], now: today)
        XCTAssertEqual(plan.blockedCount, 1)
        XCTAssertEqual(plan.ids(.today), [open.id])
        XCTAssertEqual(plan.snoozedCount, 0)
    }
}

final class SignatureAndUploadLinkTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: d, hour: 10))! }

    func testAwaitingRespectsChaseDaysStatusAndOrder() {
        let docs = [
            SignatureCandidate(id: UUID(), title: "New", clientID: nil, clientName: "A", statusRaw: "sent", sentAt: day(9)),
            SignatureCandidate(id: UUID(), title: "Old", clientID: nil, clientName: "B", statusRaw: "sent", sentAt: day(1)),
            SignatureCandidate(id: UUID(), title: "Signed", clientID: nil, clientName: "C", statusRaw: "signed", sentAt: day(1)),
            SignatureCandidate(id: UUID(), title: "Untracked", clientID: nil, clientName: "D", statusRaw: "", sentAt: nil),
            SignatureCandidate(id: UUID(), title: "Missing date", clientID: nil, clientName: "E", statusRaw: "sent", sentAt: nil),
        ]
        let result = SignatureTracking.awaiting(docs, chaseDays: 3, now: day(10), calendar: calendar)
        XCTAssertEqual(result.map(\.title), ["Old"], "New has waited 1 day, under the 3-day nudge")
        XCTAssertEqual(result.first?.daysWaiting, 9)
        let sooner = SignatureTracking.awaiting(docs, chaseDays: 1, now: day(10), calendar: calendar)
        XCTAssertEqual(sooner.map(\.title), ["Old", "New"])
    }

    func testUploadLinkNormalization() {
        XCTAssertEqual(UploadLink.normalized("https://www.encyro.com/mrgcpa"), "https://www.encyro.com/mrgcpa")
        XCTAssertEqual(UploadLink.normalized("  www.encyro.com/mrgcpa \n"), "https://www.encyro.com/mrgcpa")
        XCTAssertEqual(UploadLink.normalized(""), "")
        XCTAssertEqual(UploadLink.normalized("not a link"), "")
        XCTAssertEqual(UploadLink.normalized("ftp://files.example.com"), "")
        XCTAssertEqual(UploadLink.normalized("localhost"), "")
    }

    func testMergeFieldAndChaseEmailUseTheLink() {
        let values = MergeFields.values(clientName: "Dana Reyes", company: "", email: "", firmName: "GP", uploadLink: "https://x.com/u")
        XCTAssertEqual(MergeFields.render("Upload: {uploadlink}", values: values), "Upload: https://x.com/u")
        let blank = MergeFields.values(clientName: "Dana", company: "", email: "", firmName: "GP")
        XCTAssertTrue(MergeFields.render("{uploadlink}", values: blank).contains("Settings"))

        let with = DocumentChecklist.requestEmailBody(clientName: "Dana", items: ["W-2"], dueDate: nil, firm: "GP", uploadLink: "https://x.com/u")
        XCTAssertTrue(with.contains("https://x.com/u"))
        XCTAssertFalse(with.contains("reply to this email"))
        let without = DocumentChecklist.requestEmailBody(clientName: "Dana", items: ["W-2"], dueDate: nil, firm: "GP")
        XCTAssertTrue(without.contains("reply to this email"))
    }
}

final class TaxSeasonTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    func testAutomaticWindows() {
        XCTAssertTrue(TaxSeason.isActive(mode: .auto, now: date(2026, 1, 2), calendar: calendar))
        XCTAssertTrue(TaxSeason.isActive(mode: .auto, now: date(2026, 4, 20), calendar: calendar))
        XCTAssertFalse(TaxSeason.isActive(mode: .auto, now: date(2026, 4, 21), calendar: calendar))
        XCTAssertFalse(TaxSeason.isActive(mode: .auto, now: date(2026, 7, 1), calendar: calendar))
        XCTAssertTrue(TaxSeason.isActive(mode: .auto, now: date(2026, 10, 10), calendar: calendar))
        XCTAssertFalse(TaxSeason.isActive(mode: .auto, now: date(2026, 11, 1), calendar: calendar))
        XCTAssertTrue(TaxSeason.isActive(mode: .on, now: date(2026, 7, 1), calendar: calendar))
        XCTAssertFalse(TaxSeason.isActive(mode: .off, now: date(2026, 2, 1), calendar: calendar))
    }

    func testWorkingYearAndNextDeadline() {
        XCTAssertEqual(TaxSeason.workingTaxYear(now: date(2026, 3, 1), calendar: calendar), 2025)
        // 2026-04-15 is a Wednesday.
        XCTAssertEqual(TaxSeason.nextDeadline(now: date(2026, 3, 1), calendar: calendar), calendar.startOfDay(for: date(2026, 4, 15)))
        // After April, the next one is Oct 15 (a Thursday in 2026).
        XCTAssertEqual(TaxSeason.nextDeadline(now: date(2026, 5, 1), calendar: calendar), calendar.startOfDay(for: date(2026, 10, 15)))
        // After October, roll to next April.
        let after = TaxSeason.nextDeadline(now: date(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(calendar.component(.year, from: after), 2027)
        XCTAssertEqual(calendar.component(.month, from: after), 4)
    }

    func testSummaryCountsOnlyThisYearsOpenReturns() {
        let projects = [
            SeasonProject(statusRaw: "awaitingDocs", taxYear: 2025, isTaxReturn: true),
            SeasonProject(statusRaw: "awaitingDocs", taxYear: 2025, isTaxReturn: true),
            SeasonProject(statusRaw: "inProgress", taxYear: 2025, isTaxReturn: true),
            SeasonProject(statusRaw: "complete", taxYear: 2025, isTaxReturn: true),
            SeasonProject(statusRaw: "inProgress", taxYear: 2024, isTaxReturn: true),
            SeasonProject(statusRaw: "inProgress", taxYear: 2025, isTaxReturn: false),
        ]
        let clients = [
            SeasonClient(isActive: true, extensionYears: [], hasReturnForYear: true),
            SeasonClient(isActive: true, extensionYears: [], hasReturnForYear: false),
            SeasonClient(isActive: true, extensionYears: [2025], hasReturnForYear: false),
            SeasonClient(isActive: false, extensionYears: [], hasReturnForYear: false),
        ]
        let s = TaxSeason.summary(projects: projects, clients: clients, documentsOutstanding: 7, now: date(2026, 3, 1), calendar: calendar)
        XCTAssertEqual(s.taxYear, 2025)
        XCTAssertEqual(s.openReturns, 3)
        XCTAssertEqual(s.stages.map { $0.count }, [2, 1])
        XCTAssertEqual(s.stages.map { $0.status }, [.notStarted, .inProgress], "old Awaiting Docs counts as Not Started; ordered by stage")
        XCTAssertEqual(s.noReturnStarted, 1, "inactive and extended clients don't count")
        XCTAssertEqual(s.onExtension, 1)
        XCTAssertEqual(s.documentsOutstanding, 7)
        XCTAssertEqual(s.daysToDeadline, 45)
    }
}

final class DataHealthTests: XCTestCase {
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func testDuplicateInvoiceNumbersAreRenumberedOldestKept() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let invoices = [
            HealthInvoice(id: b, number: 1005, createdAt: t(200), isSyncedToQuickBooks: false),
            HealthInvoice(id: a, number: 1005, createdAt: t(100), isSyncedToQuickBooks: false),
            HealthInvoice(id: c, number: 1005, createdAt: t(300), isSyncedToQuickBooks: true),
            HealthInvoice(id: d, number: 1006, createdAt: t(50), isSyncedToQuickBooks: false),
        ]
        let report = DataHealth.report(invoices: invoices, templates: [], clients: [], runningTimers: [])
        XCTAssertEqual(report.duplicateInvoiceNumbers, [1005])
        XCTAssertEqual(report.renumbers, [InvoiceRenumber(id: b, newNumber: 1007)], "a keeps 1005; b is renumbered past the max")
        XCTAssertEqual(report.unfixableInvoiceIDs, [c], "QuickBooks-synced copies aren't touched")
        XCTAssertFalse(report.isHealthy)
    }

    func testNoDuplicatesIsHealthy() {
        let invoices = [HealthInvoice(id: UUID(), number: 1, createdAt: t(1), isSyncedToQuickBooks: false),
                        HealthInvoice(id: UUID(), number: 2, createdAt: t(2), isSyncedToQuickBooks: false)]
        XCTAssertTrue(DataHealth.report(invoices: invoices, templates: [], clients: [], runningTimers: []).isHealthy)
    }

    func testDuplicateTemplatesKeepReferencedOrOldest() {
        let old = UUID(), newer = UUID(), used = UUID(), different = UUID()
        let templates = [
            HealthTemplate(id: newer, name: "1040", taskTitles: ["A", "B"], createdAt: t(200), isReferenced: false),
            HealthTemplate(id: old, name: "1040", taskTitles: ["A", "B"], createdAt: t(100), isReferenced: false),
            HealthTemplate(id: used, name: "Payroll", taskTitles: ["X"], createdAt: t(300), isReferenced: true),
            HealthTemplate(id: UUID(), name: "payroll", taskTitles: ["X"], createdAt: t(50), isReferenced: false),
            HealthTemplate(id: different, name: "1040", taskTitles: ["A"], createdAt: t(1), isReferenced: false),
        ]
        let report = DataHealth.report(invoices: [], templates: templates, clients: [], runningTimers: [])
        XCTAssertTrue(report.duplicateTemplateIDs.contains(newer))
        XCTAssertFalse(report.duplicateTemplateIDs.contains(old))
        XCTAssertFalse(report.duplicateTemplateIDs.contains(used), "a template in use is never removed")
        XCTAssertFalse(report.duplicateTemplateIDs.contains(different), "different steps = a different template")
        XCTAssertEqual(report.duplicateTemplateIDs.count, 2, "newer 1040 and the unreferenced payroll copy")
    }

    func testDuplicateClientEmailsAndStaleTimers() {
        let a = UUID(), b = UUID(), c = UUID()
        let clients = [
            HealthClient(id: a, name: "A", email: "Dana@X.com"),
            HealthClient(id: b, name: "B", email: " dana@x.com "),
            HealthClient(id: c, name: "C", email: ""),
            HealthClient(id: UUID(), name: "D", email: ""),
        ]
        let now = t(1_000_000)
        let fresh = HealthTimer(id: UUID(), startedAt: now.addingTimeInterval(-3600))
        let stale = HealthTimer(id: UUID(), startedAt: now.addingTimeInterval(-20 * 3600))
        let report = DataHealth.report(invoices: [], templates: [], clients: clients, runningTimers: [fresh, stale], now: now)
        XCTAssertEqual(Set(report.duplicateClientIDs), [a, b], "blank emails are never duplicates")
        XCTAssertEqual(report.staleTimerIDs, [stale.id])
    }
}
