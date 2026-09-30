import XCTest
import SwiftData
@testable import CPAManager

private let cal = Calendar.current
private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

final class UnbilledWorkTests: XCTestCase {
    private func job(_ title: String, complete: Bool = true, done: Date? = day(2026, 8, 1), state: String = "",
                     invoice: UUID? = nil, cents: Int = 0, billed: Bool = false) -> UnbilledJobInput {
        UnbilledJobInput(id: UUID(), title: title, clientName: "Dana", isComplete: complete, completedAt: done,
                         billingState: state, invoiceID: invoice, unbilledAmountCents: cents, unbilledHours: cents > 0 ? 2 : 0,
                         hasBilledTime: billed)
    }

    func testFindsFinishedJobsWithUnbilledTimeOrNoInvoice() {
        let now = day(2026, 9, 30)
        let found = UnbilledWork.find([
            job("unbilled time", cents: 30_000),
            job("nothing invoiced"),
            job("still open", complete: false, cents: 10_000),
            job("settled", state: "notBillable"),
            job("has invoice", invoice: UUID()),
            job("fully billed", billed: true),
            job("ancient", done: day(2024, 1, 1))
        ], now: now)
        XCTAssertEqual(found.map(\.title), ["unbilled time", "nothing invoiced"], "biggest amount first")
        XCTAssertEqual(found[0].reason, .unbilledTime)
        XCTAssertEqual(found[1].reason, .noInvoice)
        XCTAssertEqual(UnbilledWork.totalCents(found), 30_000)
    }

    func testPartiallyBilledJobWithNothingLeftIsNotListed() {
        XCTAssertTrue(UnbilledWork.find([job("done", billed: true)], now: day(2026, 9, 30)).isEmpty)
        XCTAssertEqual(UnbilledWork.find([job("more time", cents: 5_000, billed: true)], now: day(2026, 9, 30)).count, 1)
    }
}

final class BillFromJobTests: XCTestCase {
    func testLinesCombineTimeAndFees() {
        let entryID = UUID()
        let lines = BillFromJob.lines(
            entries: [BillEntryInput(id: entryID, label: "Sep 3 — Return", hours: 2.504, rate: 150)],
            fees: [BillFeeInput(name: "1040 preparation", unitPrice: 400, quantity: 1),
                   BillFeeInput(name: "State return", unitPrice: 100, quantity: 0)]
        )
        XCTAssertEqual(lines.count, 2, "zero-quantity fee dropped")
        XCTAssertEqual(lines[0].timeEntryID, entryID)
        XCTAssertEqual(lines[0].quantity, 2.5, accuracy: 0.0001)
        XCTAssertEqual(BillFromJob.totalCents(lines), 37_500 + 40_000)
    }

    func testNextInvoiceNumber() {
        XCTAssertEqual(BillFromJob.nextNumber(existing: []), 1001)
        XCTAssertEqual(BillFromJob.nextNumber(existing: [1001, 1007, 1003]), 1008)
    }
}

final class InvoiceReminderTests: XCTestCase {
    func testToneEscalatesWithDaysLate() {
        XCTAssertEqual(InvoiceReminder.tone(daysLate: 3), .friendly)
        XCTAssertEqual(InvoiceReminder.tone(daysLate: 14), .friendly)
        XCTAssertEqual(InvoiceReminder.tone(daysLate: 15), .firm)
        XCTAssertEqual(InvoiceReminder.tone(daysLate: 44), .firm)
        XCTAssertEqual(InvoiceReminder.tone(daysLate: 45), .final)
    }

    func testDaysLateNeverNegative() {
        XCTAssertEqual(InvoiceReminder.daysLate(dueDate: day(2026, 9, 30), now: day(2026, 9, 20)), 0)
        XCTAssertEqual(InvoiceReminder.daysLate(dueDate: day(2026, 9, 1), now: day(2026, 9, 21)), 20)
    }

    func testWordingMentionsTheInvoiceAndGrowsFirmer() {
        let due = day(2026, 8, 1)
        let friendly = InvoiceReminder.body(clientName: "Dana", number: "INV-1001", balance: 750, dueDate: due, firm: "Gottfried & Associates PA", tone: .friendly, daysLate: 3)
        let final = InvoiceReminder.body(clientName: "Dana", number: "INV-1001", balance: 750, dueDate: due, firm: "", tone: .final, daysLate: 60)
        XCTAssertTrue(friendly.contains("Hi Dana") && friendly.contains("INV-1001") && friendly.contains("Gottfried & Associates PA"))
        XCTAssertTrue(final.contains("60 days past due"))
        XCTAssertTrue(final.contains("final reminder"))
        XCTAssertEqual(InvoiceReminder.subject(number: "INV-1001", tone: .firm), "Past due: invoice INV-1001")
    }

    func testFindsTheLastLoggedReminderForThatInvoice() {
        let entries: [(summary: String, date: Date)] = [
            (InvoiceReminder.logSummary(number: "INV-1"), day(2026, 8, 1)),
            (InvoiceReminder.logSummary(number: "INV-1"), day(2026, 9, 1)),
            (InvoiceReminder.logSummary(number: "INV-2"), day(2026, 9, 15)),
            ("Called about something", day(2026, 9, 20))
        ]
        XCTAssertEqual(InvoiceReminder.lastReminder(number: "INV-1", in: entries), day(2026, 9, 1))
        XCTAssertNil(InvoiceReminder.lastReminder(number: "INV-3", in: entries))
    }
}

final class ProfitabilityTests: XCTestCase {
    private func input(_ name: String, revenue: Int, hours: Double, standard: Double = 150) -> ProfitInput {
        ProfitInput(clientID: UUID(), clientName: name, revenueCents: revenue, hours: hours, standardRate: standard)
    }

    func testLowestEffectiveRateFirstAndNoTimeLast() {
        let rows = Profitability.rows([
            input("Good", revenue: 60_000, hours: 4),       // $150/hr
            input("Poor", revenue: 30_000, hours: 6),       // $50/hr
            input("Flat fee no time", revenue: 50_000, hours: 0),
            input("Nothing", revenue: 0, hours: 0)
        ])
        XCTAssertEqual(rows.map(\.clientName), ["Poor", "Good", "Flat fee no time"], "empty client dropped")
        XCTAssertEqual(rows[0].effectiveRate ?? 0, 50, accuracy: 0.001)
        XCTAssertTrue(rows[0].isBelowStandard)
        XCTAssertFalse(rows[1].isBelowStandard)
        XCTAssertNil(rows[2].effectiveRate)
        XCTAssertEqual(Profitability.overallRate(rows) ?? 0, 90, accuracy: 0.001, "$900 over 10 hours")
    }
}

final class ClientHealthTests: XCTestCase {
    private func input(lastContact: Date? = day(2026, 9, 25), followUp: Date? = nil, jobs: Int = 1, tasks: Int = 2,
                       overdueTasks: Int = 0, owed: Int = 0, overdueOwed: Int = 0) -> ClientHealthInput {
        ClientHealthInput(lastContactedAt: lastContact, followUpDate: followUp, openJobCount: jobs, openTaskCount: tasks,
                          overdueTaskCount: overdueTasks, balanceOwedCents: owed, overdueBalanceCents: overdueOwed,
                          nextDeadlineTitle: nil, nextDeadlineDate: nil)
    }
    private let now = day(2026, 9, 30)

    func testHealthyClient() {
        let health = ClientHealthLogic.assess(input(), now: now)
        XCTAssertEqual(health.level, .good)
        XCTAssertTrue(health.reasons.isEmpty)
    }

    func testOverdueMoneyOrTasksIsAtRisk() {
        XCTAssertEqual(ClientHealthLogic.assess(input(owed: 5_000, overdueOwed: 5_000), now: now).level, .atRisk)
        let tasks = ClientHealthLogic.assess(input(overdueTasks: 2), now: now)
        XCTAssertEqual(tasks.level, .atRisk)
        XCTAssertTrue(tasks.reasons.contains("2 overdue tasks"))
    }

    func testQuietWithOpenWorkIsWatchButQuietWithNothingOpenIsFine() {
        let quiet = ClientHealthLogic.assess(input(lastContact: day(2026, 8, 1)), now: now)
        XCTAssertEqual(quiet.level, .watch)
        XCTAssertTrue(quiet.reasons.contains { $0.hasPrefix("No contact in") })
        XCTAssertEqual(ClientHealthLogic.assess(input(lastContact: day(2026, 8, 1), jobs: 0, tasks: 0), now: now).level, .good)
    }

    func testDueFollowUpAndOutstandingBalanceAreWatchItems() {
        XCTAssertEqual(ClientHealthLogic.assess(input(followUp: day(2026, 9, 29)), now: now).reasons, ["Follow-up due"])
        XCTAssertEqual(ClientHealthLogic.assess(input(followUp: day(2026, 10, 5)), now: now).level, .good)
        XCTAssertEqual(ClientHealthLogic.assess(input(owed: 100), now: now).reasons, ["Balance outstanding"])
    }
}

final class ExtensionTrackerTests: XCTestCase {
    private func client(_ name: String, entity: EntityType = .individual1040, active: Bool = true,
                        extended: Set<Int> = [], done: Bool = false) -> ExtClientInput {
        ExtClientInput(id: UUID(), name: name, entity: entity, isActive: active, extensionYears: extended,
                       returnIsDone: done, returnStageLabel: nil)
    }

    func testRowsAreGroupedAndOrderedByUrgency() {
        let rows = ExtensionTracker.rows([
            client("Zed"), client("Amy"),
            client("Ext", extended: [2025]),
            client("Filed", done: true),
            client("Inactive", active: false),
            client("Other", entity: .other),
            client("Partnership", entity: .partnership1065)   // due Mar 15: earlier than 1040s
        ], taxYear: 2025, now: day(2026, 3, 1))
        XCTAssertEqual(rows.map(\.name), ["Partnership", "Amy", "Zed", "Ext", "Filed"])
        XCTAssertEqual(rows.map(\.state), [.needsDecision, .needsDecision, .needsDecision, .extended, .done])
    }

    func testDatesComeFromTheTaxCalendar() {
        let rows = ExtensionTracker.rows([client("Amy")], taxYear: 2025, now: day(2026, 3, 1))
        XCTAssertEqual(rows[0].originalDue, TaxCalendar.dueDate(form: .f1040, taxYear: 2025, extended: false))
        XCTAssertEqual(rows[0].extendedDue, TaxCalendar.dueDate(form: .f1040, taxYear: 2025, extended: true))
        XCTAssertEqual(rows[0].formLabel, "Form 1040")
    }

    func testUrgencyWording() {
        var row = ExtensionTracker.rows([client("Amy")], taxYear: 2025, now: day(2026, 4, 10))[0]
        XCTAssertEqual(row.daysToOriginal, 5)
        XCTAssertEqual(ExtensionTracker.urgency(for: row), "Due in 5 days")
        row = ExtensionTracker.rows([client("Amy")], taxYear: 2025, now: day(2026, 4, 20))[0]
        XCTAssertEqual(ExtensionTracker.urgency(for: row), "Past the original due date")
        row = ExtensionTracker.rows([client("Amy", extended: [2025])], taxYear: 2025, now: day(2026, 4, 10))[0]
        XCTAssertNil(ExtensionTracker.urgency(for: row))
    }
}

final class CarryoverTests: XCTestCase {
    func testPriorJobIsTheMostRecentEarlierOneForThatClientAndService() {
        let client = UUID(), other = UUID()
        let a = CarryJobInput(id: UUID(), clientID: client, serviceTypeRaw: "taxReturn", taxYear: 2023)
        let b = CarryJobInput(id: UUID(), clientID: client, serviceTypeRaw: "taxReturn", taxYear: 2024)
        let c = CarryJobInput(id: UUID(), clientID: client, serviceTypeRaw: "bookkeeping", taxYear: 2024)
        let d = CarryJobInput(id: UUID(), clientID: other, serviceTypeRaw: "taxReturn", taxYear: 2024)
        let future = CarryJobInput(id: UUID(), clientID: client, serviceTypeRaw: "taxReturn", taxYear: 2025)
        XCTAssertEqual(Carryover.priorJob(for: client, serviceTypeRaw: "taxReturn", taxYear: 2025, in: [a, b, c, d, future])?.id, b.id)
        XCTAssertNil(Carryover.priorJob(for: client, serviceTypeRaw: "taxReturn", taxYear: 2023, in: [a, b]))
    }

    func testExtraTasksSkipTemplateStepsAndBumpTheYear() {
        let extras = Carryover.extraTasks(
            prior: ["Collect W-2", "Ask about rental property", "2024 estimate letter", "collect w-2", "  "],
            templateTitles: ["Collect W-2"], priorYear: 2024, newYear: 2025
        )
        XCTAssertEqual(extras, ["Ask about rental property", "2025 estimate letter"])
    }

    func testPriorFeePrefersTheJobsOwnInvoice() {
        let own = UUID(), other = UUID()
        XCTAssertEqual(Carryover.priorFeeCents(invoiceID: own, timeInvoiceIDs: [other], totals: [own: 50_000, other: 9_000]), 50_000)
        XCTAssertEqual(Carryover.priorFeeCents(invoiceID: nil, timeInvoiceIDs: [other, other], totals: [other: 9_000]), 9_000, "each invoice counted once")
        XCTAssertNil(Carryover.priorFeeCents(invoiceID: nil, timeInvoiceIDs: [], totals: [:]))
    }
}

@MainActor
final class PracticeInsightsServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testCreatingAnInvoiceFromAJobBillsTheTimeAndLinksTheJob() throws {
        let context = try makeContext()
        let client = Client(name: "Dana", email: "dana@example.com")
        context.insert(client)
        let project = Project(title: "Return", serviceType: .taxReturn, client: client)
        context.insert(project)
        let entry = TimeEntry(startedAt: day(2026, 9, 1), endedAt: day(2026, 9, 1).addingTimeInterval(3600), hourlyRate: 200, project: project)
        context.insert(entry)

        let invoice = try XCTUnwrap(BillingService.createInvoice(
            for: project, entries: [entry],
            fees: [BillFeeInput(name: "State return", unitPrice: 100, quantity: 1)],
            dueInDays: 30, context: context, now: day(2026, 9, 30)))
        XCTAssertEqual(invoice.number, 1001)
        XCTAssertEqual(invoice.lineList.count, 2)
        XCTAssertEqual(entry.invoiceID, invoice.id)
        XCTAssertEqual(project.invoiceID, invoice.id)
        XCTAssertEqual(project.billingStateRaw, "invoiced")
        XCTAssertNil(BillingService.createInvoice(for: project, entries: [], fees: [], dueInDays: 30, context: context),
                     "nothing to bill")
    }

    func testMarkingAnExtensionMovesTheOpenReturnAndLogsIt() throws {
        let context = try makeContext()
        let client = Client(name: "Dana", entityType: .individual1040)
        context.insert(client)
        let open = Project(title: "2025 return", serviceType: .taxReturn, dueDate: day(2026, 4, 15), taxYear: 2025, client: client)
        let done = Project(title: "2025 done", status: .complete, serviceType: .taxReturn, dueDate: day(2026, 4, 15), taxYear: 2025, client: client)
        context.insert(open); context.insert(done)

        ExtensionService.markExtended(client, taxYear: 2025, context: context)
        let extended = TaxCalendar.dueDate(form: .f1040, taxYear: 2025, extended: true)
        XCTAssertEqual(open.dueDate, extended)
        XCTAssertEqual(done.dueDate, day(2026, 4, 15), "finished returns keep their date")
        XCTAssertTrue(client.extensionYears.contains(2025))
        XCTAssertEqual(client.interactionList.count, 1)

        ExtensionService.clearExtension(client, taxYear: 2025, context: context)
        XCTAssertEqual(open.dueDate, TaxCalendar.dueDate(form: .f1040, taxYear: 2025, extended: false))
        XCTAssertFalse(client.extensionYears.contains(2025))
    }

    func testReminderNeedsAnEmailAndIsLoggedOnTheClient() throws {
        let context = try makeContext()
        let client = Client(name: "Dana", email: "dana@example.com")
        context.insert(client)
        let invoice = Invoice(number: 1001, issueDate: day(2026, 8, 1), dueDate: day(2026, 8, 15), status: .sent, client: client)
        context.insert(invoice)
        context.insert(InvoiceLine(detail: "Work", quantity: 1, rate: 500, invoice: invoice))

        let reminder = try XCTUnwrap(ReminderService.compose(for: invoice, firm: "Gottfried & Associates PA", now: day(2026, 9, 30)))
        XCTAssertEqual(reminder.tone, .final, "46 days late")
        XCTAssertTrue(reminder.url.absoluteString.contains("%26"), "ampersand in the firm name is encoded")
        XCTAssertNil(ReminderService.lastReminded(invoice))
        ReminderService.logSent(for: invoice, context: context, now: day(2026, 9, 30))
        XCTAssertEqual(ReminderService.lastReminded(invoice), day(2026, 9, 30))

        client.email = ""
        XCTAssertNil(ReminderService.compose(for: invoice, firm: "", now: day(2026, 9, 30)))
    }

    func testProjectBillingFieldsSurviveABackupRoundTrip() throws {
        let context = try makeContext()
        let project = Project(title: "P")
        project.invoiceID = UUID()
        project.billingStateRaw = "notBillable"
        context.insert(project)
        let file = BackupService.export(context: context)
        let record = try XCTUnwrap(file.projects.first)
        XCTAssertEqual(record.invoiceID, project.invoiceID)
        XCTAssertEqual(record.billingStateRaw, "notBillable")
    }

    func testClientHealthServiceCountsOpenWorkAndOverdueMoney() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        let project = Project(title: "Return", client: client)
        context.insert(project)
        context.insert(TaskItem(title: "Late", dueDate: day(2026, 9, 1), project: project))
        context.insert(TaskItem(title: "Upcoming", dueDate: day(2026, 10, 10), project: project))
        let invoice = Invoice(number: 1001, dueDate: day(2026, 8, 1), status: .sent, client: client)
        context.insert(invoice)
        context.insert(InvoiceLine(detail: "Work", quantity: 1, rate: 300, invoice: invoice))

        let result = ClientHealthService.assess(client, quietDays: 14, now: day(2026, 9, 30))
        XCTAssertEqual(result.input.openJobCount, 1)
        XCTAssertEqual(result.input.openTaskCount, 2)
        XCTAssertEqual(result.input.overdueTaskCount, 1)
        XCTAssertEqual(result.input.overdueBalanceCents, 30_000)
        XCTAssertEqual(result.input.nextDeadlineTitle, "Upcoming")
        XCTAssertEqual(result.health.level, .atRisk)
    }
}
