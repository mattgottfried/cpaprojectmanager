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
        try? context.save()
    }

    private func counts(_ context: ModelContext) -> [String: Int] {
        func n<T: PersistentModel>(_ t: T.Type) -> Int { (try? context.fetchCount(FetchDescriptor<T>())) ?? -1 }
        return [
            "clients": n(Client.self), "projects": n(Project.self), "tasks": n(TaskItem.self),
            "invoices": n(Invoice.self), "lines": n(InvoiceLine.self), "payments": n(Payment.self),
            "interactions": n(Interaction.self), "requests": n(DocumentRequest.self), "expenses": n(Expense.self),
            "recurring": n(RecurringInvoice.self), "inbox": n(InboxItem.self), "documents": n(Document.self),
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
