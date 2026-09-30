import Foundation
import SwiftData

// Store-facing counterparts of BillingInsightsLogic / PracticeInsightsLogic: they read
// models, hand plain values to the pure logic, and apply the result.

enum BillingService {
    /// Every job as the unbilled-work report sees it.
    static func unbilledInputs(_ projects: [Project]) -> [UnbilledJobInput] {
        projects.map { project in
            let entries = project.timeEntries ?? []
            let unbilled = entries.filter(\.isUnbilled)
            let cents = unbilled.reduce(0) { $0 + InvoiceMath.cents($1.billableAmount) }
            return UnbilledJobInput(
                id: project.id, title: project.title, clientName: project.clientName,
                isComplete: project.status.isComplete, completedAt: project.completedAt,
                billingState: project.billingStateRaw, invoiceID: project.invoiceID,
                unbilledAmountCents: cents, unbilledHours: unbilled.reduce(0) { $0 + $1.billedHours() },
                hasBilledTime: entries.contains(where: \.isBilled)
            )
        }
    }

    /// A job's unbilled, finished, billable time — the entries a "bill this job" sheet offers.
    static func unbilledEntries(for project: Project) -> [TimeEntry] {
        (project.timeEntries ?? []).filter(\.isUnbilled).sorted { $0.startedAt < $1.startedAt }
    }

    /// Makes a draft invoice for the job's client from time entries and fee-schedule items,
    /// marks the time as billed, and links the invoice to the job. Nil without a client or lines.
    @discardableResult
    static func createInvoice(
        for project: Project, entries: [TimeEntry], fees: [BillFeeInput],
        dueInDays: Int, context: ModelContext, now: Date = .now
    ) -> Invoice? {
        guard let client = project.client else { return nil }
        let inputs = entries.map {
            BillEntryInput(id: $0.id, label: "\(Format.shortDate.string(from: $0.startedAt)) — \(project.title)",
                           hours: $0.billedHours(), rate: $0.hourlyRate)
        }
        let lines = BillFromJob.lines(entries: inputs, fees: fees)
        guard !lines.isEmpty else { return nil }

        let existing = ((try? context.fetch(FetchDescriptor<Invoice>())) ?? []).map(\.number)
        let invoice = Invoice(
            number: BillFromJob.nextNumber(existing: existing),
            issueDate: now,
            dueDate: Calendar.current.date(byAdding: .day, value: dueInDays, to: now) ?? now,
            notes: project.title,
            client: client
        )
        context.insert(invoice)
        for (index, line) in lines.enumerated() {
            context.insert(InvoiceLine(detail: line.detail, quantity: line.quantity, rate: line.rate,
                                       sortIndex: index, timeEntryID: line.timeEntryID, invoice: invoice))
        }
        for entry in entries { entry.invoiceID = invoice.id }
        project.invoiceID = invoice.id
        project.billingStateRaw = BillingState.invoiced.rawValue
        try? context.save()
        return invoice
    }

    static func markSettled(_ project: Project, as state: BillingState?) {
        project.billingStateRaw = state?.rawValue ?? ""
    }

    // MARK: Profitability

    /// One `ProfitInput` per client for invoices issued and time logged since `start`.
    static func profitInputs(clients: [Client], defaultRate: Double, since start: Date?) -> [ProfitInput] {
        clients.map { client in
            let invoices = client.invoiceList.filter { invoice in
                (invoice.status == .sent || invoice.status == .paid) && (start.map { invoice.issueDate >= $0 } ?? true)
            }
            let revenue = invoices.reduce(0) { $0 + InvoiceMath.cents($1.total) }
            let entries = client.projectList.flatMap { $0.timeEntries ?? [] }
            let inPeriod = entries.filter { entry in
                !entry.isRunning && (start.map { entry.startedAt >= $0 } ?? true)
            }
            let seconds = inPeriod.reduce(0.0) { $0 + $1.durationSeconds }
            return ProfitInput(clientID: client.id, clientName: client.displayName, revenueCents: revenue,
                               hours: seconds / 3600,
                               standardRate: RateResolver.rate(clientOverride: client.hourlyRateOverride, defaultRate: defaultRate))
        }
    }
}

enum ReminderService {
    /// The reminder email for an overdue invoice, worded by how late it is. Nil when the
    /// client has no usable email address.
    static func compose(for invoice: Invoice, firm: String, now: Date = .now) -> (url: URL, tone: ReminderTone)? {
        guard let client = invoice.client else { return nil }
        let late = InvoiceReminder.daysLate(dueDate: invoice.dueDate, now: now)
        let tone = InvoiceReminder.tone(daysLate: late)
        let subject = InvoiceReminder.subject(number: invoice.displayNumber, tone: tone)
        let body = InvoiceReminder.body(clientName: client.displayName, number: invoice.displayNumber, balance: invoice.balance,
                                        dueDate: invoice.dueDate, firm: firm, tone: tone, daysLate: late)
        guard let url = MailtoBuilder.url(to: client.email, subject: subject, body: body) else { return nil }
        return (url, tone)
    }

    /// Records the reminder on the client's timeline (and clears a follow-up that was due).
    static func logSent(for invoice: Invoice, context: ModelContext, now: Date = .now) {
        guard let client = invoice.client else { return }
        context.insert(Interaction(kind: .email, summary: InvoiceReminder.logSummary(number: invoice.displayNumber),
                                   occurredAt: now, client: client))
        if ClientActivity.shouldClearFollowUp(client.followUpDate, now: now) { client.followUpDate = nil }
        try? context.save()
    }

    static func lastReminded(_ invoice: Invoice) -> Date? {
        let entries = (invoice.client?.interactionList ?? []).map { (summary: $0.summary, date: $0.occurredAt) }
        return InvoiceReminder.lastReminder(number: invoice.displayNumber, in: entries)
    }
}

enum ExtensionService {
    /// The tracker's input for every client, for `taxYear`.
    static func inputs(clients: [Client], taxYear: Int, pipelines: [Pipeline]) -> [ExtClientInput] {
        clients.map { client in
            let returns = client.projectList.filter { $0.serviceType == .taxReturn && $0.taxYear == taxYear }
            let stage = returns.first.map { PipelineEngine.info(for: $0, in: pipelines).name }
            return ExtClientInput(
                id: client.id, name: client.displayName, entity: client.entityType, isActive: client.status == .active,
                extensionYears: client.extensionYears,
                returnIsDone: !returns.isEmpty && returns.allSatisfy { $0.status.isComplete || $0.status == .filed },
                returnStageLabel: stage
            )
        }
    }

    /// Marks the extension filed, moves the year's open return to the extended due date,
    /// and logs it on the client's timeline.
    static func markExtended(_ client: Client, taxYear: Int, context: ModelContext, now: Date = .now) {
        guard let form = TaxCalendar.form(for: client.entityType) else { return }
        let extended = TaxCalendar.dueDate(form: form, taxYear: taxYear, extended: true)
        var years = client.extensionYears
        years.insert(taxYear)
        client.extensionYears = years
        for project in client.projectList where project.serviceType == .taxReturn && project.taxYear == taxYear && !project.status.isComplete {
            project.dueDate = extended
        }
        context.insert(Interaction(kind: .note,
                                   summary: ExtensionTracker.logSummary(formLabel: form.label, taxYear: taxYear, extendedDue: extended),
                                   occurredAt: now, client: client))
        try? context.save()
    }

    /// Takes the extension back and returns open returns to the original due date.
    static func clearExtension(_ client: Client, taxYear: Int, context: ModelContext) {
        guard let form = TaxCalendar.form(for: client.entityType) else { return }
        let original = TaxCalendar.dueDate(form: form, taxYear: taxYear, extended: false)
        var years = client.extensionYears
        years.remove(taxYear)
        client.extensionYears = years
        for project in client.projectList where project.serviceType == .taxReturn && project.taxYear == taxYear && !project.status.isComplete {
            project.dueDate = original
        }
        try? context.save()
    }
}

enum ClientHealthService {
    static func assess(_ client: Client, quietDays: Int, now: Date = .now) -> (health: ClientHealth, input: ClientHealthInput) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let openJobs = client.openProjects
        let openTasks = openJobs.flatMap { $0.taskList }.filter { !$0.isDone } + (client.looseTasks ?? []).filter { !$0.isDone }
        let overdueTasks = openTasks.filter { ($0.dueDate.map { cal.startOfDay(for: $0) < today }) ?? false }
        let sent = client.invoiceList.filter { $0.status == .sent }
        let owed = sent.reduce(0) { $0 + InvoiceMath.cents($1.balance) }
        let overdue = sent.filter(\.isOverdue).reduce(0) { $0 + InvoiceMath.cents($1.balance) }

        var upcoming: [(title: String, date: Date)] = []
        for job in openJobs { if let due = job.dueDate { upcoming.append((job.title, due)) } }
        for task in openTasks { if let due = task.dueDate { upcoming.append((task.title, due)) } }
        let next = upcoming.filter { cal.startOfDay(for: $0.date) >= today }.min { $0.date < $1.date }

        let input = ClientHealthInput(
            lastContactedAt: client.lastContactedAt, followUpDate: client.followUpDate,
            openJobCount: openJobs.count, openTaskCount: openTasks.count, overdueTaskCount: overdueTasks.count,
            balanceOwedCents: owed, overdueBalanceCents: overdue,
            nextDeadlineTitle: next?.title, nextDeadlineDate: next?.date
        )
        return (ClientHealthLogic.assess(input, quietDays: quietDays, now: now), input)
    }
}

enum CarryoverService {
    /// Last year's job for the same client and service, if one exists.
    static func priorJob(for client: Client, serviceType: ServiceType, taxYear: Int) -> Project? {
        let jobs = client.projectList
        let inputs = jobs.map { CarryJobInput(id: $0.id, clientID: client.id, serviceTypeRaw: $0.serviceTypeRaw, taxYear: $0.taxYear) }
        guard let prior = Carryover.priorJob(for: client.id, serviceTypeRaw: serviceType.rawValue, taxYear: taxYear, in: inputs) else { return nil }
        return jobs.first { $0.id == prior.id }
    }

    /// What last year's job billed, in cents.
    static func priorFeeCents(_ prior: Project) -> Int? {
        let invoices = prior.client?.invoiceList ?? []
        let totals = Dictionary(invoices.map { ($0.id, InvoiceMath.cents($0.total)) }, uniquingKeysWith: { first, _ in first })
        let timeInvoiceIDs = (prior.timeEntries ?? []).compactMap(\.invoiceID)
        return Carryover.priorFeeCents(invoiceID: prior.invoiceID, timeInvoiceIDs: timeInvoiceIDs, totals: totals)
    }

    /// Steps last year's job had that this year's template doesn't create.
    static func extraTasks(from prior: Project, newTemplate: WorkflowTemplate?, newYear: Int) -> [String] {
        Carryover.extraTasks(
            prior: prior.taskList.map(\.title),
            templateTitles: (newTemplate?.taskList ?? []).map(\.title),
            priorYear: prior.taxYear, newYear: newYear
        )
    }
}
