import Foundation
import SwiftData

enum ClientMergeService {
    /// Folds `others` into `keeper`: everything they own moves over, blank fields on the
    /// keeper are filled from them, and they're deleted. Nothing is lost.
    static func merge(_ others: [Client], into keeper: Client, context: ModelContext) {
        // Records that point at a client without being in its relationship lists.
        let expenses = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let quotes = (try? context.fetch(FetchDescriptor<Quote>())) ?? []
        let recurringInvoices = (try? context.fetch(FetchDescriptor<RecurringInvoice>())) ?? []
        let requests = (try? context.fetch(FetchDescriptor<DocumentRequest>())) ?? []

        for other in others where other.id != keeper.id {
            for project in other.projectList { project.client = keeper }
            for document in other.documents ?? [] { document.client = keeper }
            for invoice in other.invoiceList { invoice.client = keeper }
            for engagement in other.recurringEngagementList { engagement.client = keeper }
            for task in other.looseTasks ?? [] { task.client = keeper }
            for interaction in other.interactionList { interaction.client = keeper }
            for expense in expenses where expense.client?.id == other.id { expense.client = keeper }
            for quote in quotes where quote.client?.id == other.id { quote.client = keeper }
            for recurring in recurringInvoices where recurring.client?.id == other.id { recurring.client = keeper }
            for request in requests where request.client?.id == other.id { request.client = keeper }

            fillBlanks(of: keeper, from: other)
            context.delete(other)
        }
        try? context.save()
    }

    private static func fillBlanks(of keeper: Client, from other: Client) {
        if keeper.company.isEmpty { keeper.company = other.company }
        if keeper.email.isEmpty { keeper.email = other.email }
        if keeper.phone.isEmpty { keeper.phone = other.phone }
        if keeper.qboCustomerId.isEmpty { keeper.qboCustomerId = other.qboCustomerId }
        if keeper.driveFolderID.isEmpty { keeper.driveFolderID = other.driveFolderID; keeper.driveFolderName = other.driveFolderName }
        if keeper.hourlyRateOverride == 0 { keeper.hourlyRateOverride = other.hourlyRateOverride }
        if keeper.birthday == nil { keeper.birthday = other.birthday }
        if keeper.anniversary == nil { keeper.anniversary = other.anniversary }
        if !other.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, other.notes != keeper.notes {
            keeper.notes = keeper.notes.isEmpty ? other.notes : keeper.notes + "\n\n" + other.notes
        }
        keeper.tags = TagSet.parse(TagSet.encode(keeper.tags + other.tags))
        keeper.extensionYears = keeper.extensionYears.union(other.extensionYears)
        if let theirs = other.followUpDate {
            keeper.followUpDate = keeper.followUpDate.map { min($0, theirs) } ?? theirs
        }
        if other.createdAt < keeper.createdAt { keeper.createdAt = other.createdAt }
    }
}
