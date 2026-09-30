import Foundation
import SwiftData

/// Reads the SwiftData store into sync entries and applies remote changes to it.
@MainActor
enum SyncStore {
    struct Snapshot {
        var entries: [SyncKey: SyncEntry]
        var oversizedFiles: [SyncKey]
    }

    /// The whole store as entries. Attached files are left out (they never change once
    /// added, and encoding megabytes of PDFs on every save would be wasteful) — see `fullEntries`.
    static func snapshot(_ context: ModelContext) -> Snapshot {
        let result = SyncCodec.encode(BackupService.export(context: context, includeFiles: false))
        return Snapshot(entries: result.entries, oversizedFiles: result.oversizedFiles)
    }

    /// The given records *with* their attached files, as they should be sent to the cloud.
    /// Files too large for one document are dropped (the record still syncs).
    static func fullEntries(for keys: [SyncKey], context: ModelContext) -> Snapshot {
        let wanted = Set(keys)
        let result = SyncCodec.encode(BackupService.export(context: context, includeFiles: true))
        return Snapshot(
            entries: result.entries.filter { wanted.contains($0.key) },
            oversizedFiles: result.oversizedFiles.filter { wanted.contains($0) }
        )
    }

    /// Inserts or updates the given records (parents before children, links resolved
    /// together) and saves. Returns the keys that couldn't be decoded.
    @discardableResult
    static func apply(_ entries: [SyncEntry], to context: ModelContext) -> [SyncKey] {
        guard !entries.isEmpty else { return [] }
        let decoded = SyncCodec.decode(entries)
        BackupService.restore(decoded.file, into: context, overwrite: true)
        return decoded.failed
    }

    static func delete(_ keys: [SyncKey], from context: ModelContext) {
        for key in keys { delete(key, from: context) }
        try? context.save()
    }

    private static func delete(_ key: SyncKey, from context: ModelContext) {
        func remove<T: PersistentModel>(_ type: T.Type, id: KeyPath<T, UUID>) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for model in all where model[keyPath: id] == key.id { context.delete(model) }
        }
        switch key.collection {
        case .clients:           remove(Client.self, id: \.id)
        case .projects:          remove(Project.self, id: \.id)
        case .tasks:             remove(TaskItem.self, id: \.id)
        case .timeEntries:       remove(TimeEntry.self, id: \.id)
        case .documents:         remove(Document.self, id: \.id)
        case .templates:         remove(WorkflowTemplate.self, id: \.id)
        case .templateTasks:     remove(TemplateTask.self, id: \.id)
        case .engagements:       remove(RecurringEngagement.self, id: \.id)
        case .invoices:          remove(Invoice.self, id: \.id)
        case .invoiceLines:      remove(InvoiceLine.self, id: \.id)
        case .payments:          remove(Payment.self, id: \.id)
        case .inbox:             remove(InboxItem.self, id: \.id)
        case .interactions:      remove(Interaction.self, id: \.id)
        case .savedFilters:      remove(SavedClientFilter.self, id: \.id)
        case .documentRequests:  remove(DocumentRequest.self, id: \.id)
        case .recurringInvoices: remove(RecurringInvoice.self, id: \.id)
        case .expenses:          remove(Expense.self, id: \.id)
        case .pipelines:         remove(Pipeline.self, id: \.id)
        case .letterTemplates:   remove(LetterTemplate.self, id: \.id)
        case .emailTemplates:    remove(EmailTemplate.self, id: \.id)
        case .feeItems:          remove(FeeItem.self, id: \.id)
        case .quotes:            remove(Quote.self, id: \.id)
        }
    }
}

// MARK: - Ledger persistence

protocol SyncLedgerStore: AnyObject {
    func load() -> SyncLedger
    func save(_ ledger: SyncLedger)
}

final class MemoryLedgerStore: SyncLedgerStore {
    private var ledger = SyncLedger()
    func load() -> SyncLedger { ledger }
    func save(_ ledger: SyncLedger) { self.ledger = ledger }
}

/// One JSON file per signed-in account, next to the app's other private data.
final class FileLedgerStore: SyncLedgerStore {
    private let url: URL

    init(userID: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("CPAManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("sync-ledger-\(userID).json")
    }

    func load() -> SyncLedger {
        guard let data = try? Data(contentsOf: url), let ledger = try? JSONDecoder().decode(SyncLedger.self, from: data) else {
            return SyncLedger()
        }
        return ledger
    }

    func save(_ ledger: SyncLedger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
