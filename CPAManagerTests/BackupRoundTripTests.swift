import XCTest
import SwiftData
@testable import CPAManager

@MainActor
final class BackupRoundTripTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config)
    }

    private func seed(_ context: ModelContext) {
        let client = Client(name: "Dana Lee", company: "Acme", email: "dana@acme.com")
        client.tags = ["referral", "s-corp"]
        client.leadStage = .contacted
        client.leadValue = 4200
        client.extensionYears = [2025]
        context.insert(client)

        let project = Project(title: "Lee 2025 Form 1040", client: client)
        context.insert(project)

        let task = TaskItem(title: "Send engagement letter", dueDate: .now, project: project)
        task.repeatRule = .weekly
        context.insert(task)

        let invoice = Invoice(number: 1042, dueDate: .now, status: .sent, client: client)
        context.insert(invoice)
        context.insert(InvoiceLine(detail: "Tax preparation", quantity: 2, rate: 150, invoice: invoice))
        invoice.recordPayment(100, method: .check, note: "Check 118")

        context.insert(Interaction(kind: .call, summary: "Discussed extension", client: client))
        context.insert(DocumentRequest(title: "W-2s", client: client))

        let expense = Expense(amount: 49.99, category: .software, vendor: "Adobe")
        expense.receiptData = Data([1, 2, 3, 4])
        expense.receiptExtension = "png"
        context.insert(expense)

        context.insert(RecurringInvoice(name: "Retainer", lines: [RecurringInvoiceLine(detail: "Monthly fee", quantity: 1, rate: 500)], client: client))
        context.insert(InboxItem(text: "Call the county about the notice"))
        context.insert(Document(filename: "Statement", fileExtension: "pdf", data: Data([9, 9, 9]), client: client))

        // Batch 5
        client.birthday = Date(timeIntervalSince1970: 500_000_000)
        client.anniversary = Date(timeIntervalSince1970: 1_500_000_000)
        client.birthdayAckYear = 2026
        let pipeline = Pipeline(definition: PipelineStarters.bookkeeping)
        context.insert(pipeline)
        project.pipelineID = pipeline.id
        project.stageKey = pipeline.stages[1].id
        let template = WorkflowTemplate(name: "Monthly close", detail: "")
        template.pipelineID = pipeline.id
        template.startStageKey = pipeline.stages[0].id
        context.insert(template)
        let engagement = RecurringEngagement(name: "Books", client: client, template: template)
        engagement.endDate = Date(timeIntervalSince1970: 1_800_000_000)
        engagement.namingPattern = "{client} {month}"
        context.insert(engagement)
        context.insert(LetterTemplate(name: "Engagement", kind: .engagement, body: "Dear {firstname}"))

        // Batch 6
        client.hourlyRateOverride = 225
        client.isFlatFee = true
        task.checklist = "- [x] a\n- [ ] b"
        task.waitingOn = "W-2"
        let blocker = TaskItem(title: "Blocker", project: project)
        context.insert(blocker)
        task.blockedByID = blocker.id
        context.insert(FeeItem(name: "1040", unitPrice: 450))
        let quote = Quote(number: 1001, client: client, lines: [QuoteLine(detail: "Prep", quantity: 1, rate: 450)])
        quote.status = .sent
        context.insert(quote)
        let signed = Document(filename: "Letter", fileExtension: "pdf", data: Data([7]), client: client)
        signed.signatureStatus = .sent
        signed.signatureSentAt = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(signed)
        context.insert(EmailTemplate(name: "Follow-up", subject: "Hi", body: "Checking in"))
        try? context.save()
    }

    private func counts(_ context: ModelContext) -> [String: Int] {
        func n<T: PersistentModel>(_ t: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? -1 }
        return [
            "clients": n(Client.self), "projects": n(Project.self), "tasks": n(TaskItem.self),
            "invoices": n(Invoice.self), "lines": n(InvoiceLine.self), "payments": n(Payment.self),
            "interactions": n(Interaction.self), "requests": n(DocumentRequest.self), "expenses": n(Expense.self),
            "recurring": n(RecurringInvoice.self), "inbox": n(InboxItem.self), "documents": n(Document.self),
            "pipelines": n(Pipeline.self), "letters": n(LetterTemplate.self), "emails": n(EmailTemplate.self),
            "engagements": n(RecurringEngagement.self), "templates": n(WorkflowTemplate.self),
            "fees": n(FeeItem.self), "quotes": n(Quote.self),
        ]
    }

    func testExportRestoreIntoEmptyStoreRebuildsEverythingAndLinks() throws {
        let source = try makeContainer().mainContext
        seed(source)
        let data = try BackupService.exportData(context: source)

        let file = try BackupService.decode(data)
        XCTAssertEqual(file.version, BackupFile.currentVersion)

        let target = try makeContainer().mainContext
        let result = BackupService.restore(file, into: target)
        XCTAssertEqual(result.inserted, file.totalRecords)
        XCTAssertEqual(result.skippedExisting, 0)
        XCTAssertEqual(counts(target), counts(source))

        // Relationships and computed values survive.
        let client = try XCTUnwrap(try target.fetch(FetchDescriptor<Client>()).first)
        XCTAssertEqual(client.displayName, "Dana Lee")
        XCTAssertEqual(client.tags, ["referral", "s-corp"])
        XCTAssertEqual(client.leadStage, .contacted)
        XCTAssertEqual(client.extensionYears, [2025])
        XCTAssertEqual(client.projectList.count, 1)
        XCTAssertEqual(client.invoiceList.first?.amountPaid, 100)
        XCTAssertEqual(client.invoiceList.first?.balance, 200)
        XCTAssertEqual(client.interactionList.count, 1)
        XCTAssertEqual(client.documentRequestList.count, 1)
        XCTAssertEqual(client.birthdayAckYear, 2026)
        XCTAssertEqual(client.birthday, Date(timeIntervalSince1970: 500_000_000))
        let restoredPipeline = try XCTUnwrap(try target.fetch(FetchDescriptor<Pipeline>()).first)
        XCTAssertEqual(restoredPipeline.stages, PipelineStarters.bookkeeping.stages)
        let restoredProject = try XCTUnwrap(try target.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(restoredProject.pipelineID, restoredPipeline.id)
        XCTAssertEqual(restoredProject.stageKey, restoredPipeline.stages[1].id)
        let restoredTemplate = try XCTUnwrap(try target.fetch(FetchDescriptor<WorkflowTemplate>()).first)
        XCTAssertEqual(restoredTemplate.startStageKey, restoredPipeline.stages[0].id)
        let restoredEngagement = try XCTUnwrap(try target.fetch(FetchDescriptor<RecurringEngagement>()).first)
        XCTAssertEqual(restoredEngagement.namingPattern, "{client} {month}")
        XCTAssertNotNil(restoredEngagement.endDate)
        XCTAssertEqual(client.hourlyRateOverride, 225)
        XCTAssertTrue(client.isFlatFee)
        let restoredTask = try XCTUnwrap(try target.fetch(FetchDescriptor<TaskItem>()).first { $0.title == "Send engagement letter" })
        XCTAssertEqual(restoredTask.checklist, "- [x] a\n- [ ] b")
        XCTAssertEqual(restoredTask.waitingOn, "W-2")
        XCTAssertNotNil(restoredTask.blockedByID)
        let restoredQuote = try XCTUnwrap(try target.fetch(FetchDescriptor<Quote>()).first)
        XCTAssertEqual(restoredQuote.total, 450)
        XCTAssertEqual(restoredQuote.status, .sent)
        XCTAssertEqual(restoredQuote.client?.id, client.id)
        let restoredLetter = try XCTUnwrap(try target.fetch(FetchDescriptor<Document>()).first { $0.filename == "Letter" })
        XCTAssertEqual(restoredLetter.signatureStatus, .sent)
        let expense = try XCTUnwrap(try target.fetch(FetchDescriptor<Expense>()).first)
        XCTAssertEqual(expense.receiptData, Data([1, 2, 3, 4]))
        let recurring = try XCTUnwrap(try target.fetch(FetchDescriptor<RecurringInvoice>()).first)
        XCTAssertEqual(recurring.total, 500)
    }

    func testRestoreIsAMergeAndIdempotent() throws {
        let source = try makeContainer().mainContext
        seed(source)
        let file = try BackupService.decode(try BackupService.exportData(context: source))

        // Restoring into the same store adds nothing.
        let again = BackupService.restore(file, into: source)
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(again.skippedExisting, file.totalRecords)
        XCTAssertEqual(counts(source)["clients"], 1)

        // Restoring twice into a new store adds nothing the second time.
        let target = try makeContainer().mainContext
        BackupService.restore(file, into: target)
        XCTAssertEqual(BackupService.restore(file, into: target).inserted, 0)
    }

    func testBackupFromBeforeBatch5StillDecodes() throws {
        // A minimal older backup: no new collections, no new fields on existing records.
        let json = """
        {"version":1,"createdAt":"2026-01-01T00:00:00Z",
         "clients":[{"id":"11111111-1111-1111-1111-111111111111","name":"Old Client","company":"","entityTypeRaw":"individual1040",
           "statusRaw":"active","email":"","phone":"","notes":"","createdAt":"2025-01-01T00:00:00Z","qboCustomerId":"",
           "tagsRaw":"","leadStageRaw":"","leadValue":0,"extensionYearsRaw":""}],
         "projects":[],"tasks":[],"timeEntries":[],"documents":[],"templates":[],"templateTasks":[],"engagements":[],
         "invoices":[],"invoiceLines":[],"payments":[],"inbox":[],"interactions":[],"savedFilters":[],
         "documentRequests":[],"recurringInvoices":[],"expenses":[]}
        """
        let file = try BackupService.decode(Data(json.utf8))
        XCTAssertEqual(file.clients.count, 1)
        XCTAssertNil(file.pipelines)
        let context = try makeContainer().mainContext
        XCTAssertEqual(BackupService.restore(file, into: context).inserted, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Client>()).first?.birthdayAckYear, 0)
    }

    func testBackupWithoutFilesOmitsBinaryPayloads() throws {
        let source = try makeContainer().mainContext
        seed(source)
        let light = BackupService.export(context: source, includeFiles: false)
        XCTAssertNil(light.documents.first?.data)
        XCTAssertNil(light.expenses.first?.receiptData)
        let full = BackupService.export(context: source, includeFiles: true)
        XCTAssertEqual(full.documents.first?.data, Data([9, 9, 9]))
    }

    func testDecodeRejectsGarbageAndNewerVersions() throws {
        XCTAssertThrowsError(try BackupService.decode(Data("not json".utf8)))
        var file = BackupFile()
        file.version = BackupFile.currentVersion + 1
        let data = try BackupService.encoder().encode(file)
        XCTAssertThrowsError(try BackupService.decode(data))
    }

    func testCSVExportFromStoreEscapesAndIncludesRows() throws {
        let context = try makeContainer().mainContext
        seed(context)
        let clients = ExportService.csv(.clients, context: context)
        XCTAssertTrue(clients.hasPrefix("Name,Company,Entity type"))
        XCTAssertTrue(clients.contains("Dana Lee"))
        XCTAssertTrue(clients.contains("referral; s-corp"))
        let payments = ExportService.csv(.payments, context: context)
        XCTAssertTrue(payments.contains("100.00"))
        XCTAssertTrue(payments.contains("Check"))
        let expenses = ExportService.csv(.expenses, context: context)
        XCTAssertTrue(expenses.contains("Adobe"))
    }
}
