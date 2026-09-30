import Foundation
import CryptoKit

// Pure building blocks for cloud sync (Firestore). Nothing here touches SwiftData or the
// network, so all of it is unit-tested with plain values.
//
// Model: every synced record is one JSON document (the same `BackupFile` record structs the
// backup uses). Each device keeps a "ledger" — the hash of every record as of its last sync —
// so it can tell what changed locally (hash != ledger), what was deleted locally (in the
// ledger, gone from the store) and which remote changes are genuinely new.

// MARK: - Keys & entries

enum SyncCollection: String, CaseIterable {
    case clients, projects, tasks, timeEntries, documents, templates, templateTasks, engagements
    case invoices, invoiceLines, payments, inbox, interactions, savedFilters, documentRequests
    case recurringInvoices, expenses, pipelines, letterTemplates, emailTemplates, feeItems, quotes
}

struct SyncKey: Hashable {
    var collection: SyncCollection
    var id: UUID

    /// Firestore document id, e.g. "clients~3F2A…".
    var documentID: String { "\(collection.rawValue)~\(id.uuidString)" }

    init(_ collection: SyncCollection, _ id: UUID) {
        self.collection = collection
        self.id = id
    }

    init?(documentID: String) {
        let parts = documentID.split(separator: "~", maxSplits: 1).map(String.init)
        guard parts.count == 2, let collection = SyncCollection(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        self.init(collection, id)
    }
}

/// One record as JSON text plus its hash. The JSON text is what is stored in the cloud, so
/// two devices holding the same version hold byte-identical text.
struct SyncEntry: Equatable {
    var key: SyncKey
    var json: String
    var hash: String

    init(key: SyncKey, json: String) {
        self.key = key
        self.json = json
        self.hash = SyncHash.hash(json)
    }
}

enum SyncHash {
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Codec (BackupFile <-> entries)

protocol SyncIdentifiable {
    var id: UUID { get }
}

extension BackupFile.ClientRecord: SyncIdentifiable {}
extension BackupFile.ProjectRecord: SyncIdentifiable {}
extension BackupFile.TaskRecord: SyncIdentifiable {}
extension BackupFile.TimeRecord: SyncIdentifiable {}
extension BackupFile.DocumentRecord: SyncIdentifiable {}
extension BackupFile.TemplateRecord: SyncIdentifiable {}
extension BackupFile.TemplateTaskRecord: SyncIdentifiable {}
extension BackupFile.EngagementRecord: SyncIdentifiable {}
extension BackupFile.InvoiceRecord: SyncIdentifiable {}
extension BackupFile.InvoiceLineRecord: SyncIdentifiable {}
extension BackupFile.PaymentRecord: SyncIdentifiable {}
extension BackupFile.InboxRecord: SyncIdentifiable {}
extension BackupFile.InteractionRecord: SyncIdentifiable {}
extension BackupFile.SavedFilterRecord: SyncIdentifiable {}
extension BackupFile.DocumentRequestRecord: SyncIdentifiable {}
extension BackupFile.RecurringInvoiceRecord: SyncIdentifiable {}
extension BackupFile.ExpenseRecord: SyncIdentifiable {}
extension BackupFile.PipelineRecord: SyncIdentifiable {}
extension BackupFile.LetterTemplateRecord: SyncIdentifiable {}
extension BackupFile.EmailTemplateRecord: SyncIdentifiable {}
extension BackupFile.FeeItemRecord: SyncIdentifiable {}
extension BackupFile.QuoteRecord: SyncIdentifiable {}

enum SyncCodec {
    /// Firestore documents are capped at 1 MiB; leave headroom for field names.
    static let maxDocumentBytes = 800_000

    struct Result {
        var entries: [SyncKey: SyncEntry] = [:]
        /// Records whose attached file was too big to sync (the record itself still syncs).
        var oversizedFiles: [SyncKey] = []
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: Encode

    static func encode(_ file: BackupFile) -> Result {
        var result = Result()
        let encoder = BackupService.encoder()

        func add<R: Encodable & SyncIdentifiable>(_ collection: SyncCollection, _ records: [R], strip: ((R) -> R)? = nil) {
            for record in records {
                var json = (try? encoder.encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                var key = SyncKey(collection, record.id)
                if json.utf8.count > maxDocumentBytes, let strip {
                    // Too big for one document: sync everything except the attached file.
                    let slim = strip(record)
                    json = (try? encoder.encode(slim)).flatMap { String(data: $0, encoding: .utf8) } ?? json
                    result.oversizedFiles.append(key)
                }
                if json.isEmpty { continue }
                key = SyncKey(collection, record.id)
                result.entries[key] = SyncEntry(key: key, json: json)
            }
        }

        add(.clients, file.clients)
        add(.projects, file.projects)
        add(.tasks, file.tasks)
        add(.timeEntries, file.timeEntries)
        add(.documents, file.documents) { var r = $0; r.data = nil; return r }
        add(.templates, file.templates)
        add(.templateTasks, file.templateTasks)
        add(.engagements, file.engagements)
        add(.invoices, file.invoices)
        add(.invoiceLines, file.invoiceLines)
        add(.payments, file.payments)
        add(.inbox, file.inbox)
        add(.interactions, file.interactions)
        add(.savedFilters, file.savedFilters)
        add(.documentRequests, file.documentRequests)
        add(.recurringInvoices, file.recurringInvoices)
        add(.expenses, file.expenses) { var r = $0; r.receiptData = nil; return r }
        add(.pipelines, file.pipelines ?? [])
        add(.letterTemplates, file.letterTemplates ?? [])
        add(.emailTemplates, file.emailTemplates ?? [])
        add(.feeItems, file.feeItems ?? [])
        add(.quotes, file.quotes ?? [])
        return result
    }

    // MARK: Decode

    /// Builds a (partial) backup containing just these entries. Entries that fail to decode
    /// are returned in `failed` instead of aborting the whole batch.
    static func decode(_ entries: [SyncEntry]) -> (file: BackupFile, failed: [SyncKey]) {
        var file = BackupFile()
        var failed: [SyncKey] = []
        let decoder = decoder()

        func take<R: Decodable>(_ type: R.Type, _ entry: SyncEntry, into array: inout [R]) {
            if let record = try? decoder.decode(R.self, from: Data(entry.json.utf8)) {
                array.append(record)
            } else {
                failed.append(entry.key)
            }
        }

        var pipelines: [BackupFile.PipelineRecord] = []
        var letters: [BackupFile.LetterTemplateRecord] = []
        var emails: [BackupFile.EmailTemplateRecord] = []
        var fees: [BackupFile.FeeItemRecord] = []
        var quotes: [BackupFile.QuoteRecord] = []

        for entry in entries {
            switch entry.key.collection {
            case .clients:           take(BackupFile.ClientRecord.self, entry, into: &file.clients)
            case .projects:          take(BackupFile.ProjectRecord.self, entry, into: &file.projects)
            case .tasks:             take(BackupFile.TaskRecord.self, entry, into: &file.tasks)
            case .timeEntries:       take(BackupFile.TimeRecord.self, entry, into: &file.timeEntries)
            case .documents:         take(BackupFile.DocumentRecord.self, entry, into: &file.documents)
            case .templates:         take(BackupFile.TemplateRecord.self, entry, into: &file.templates)
            case .templateTasks:     take(BackupFile.TemplateTaskRecord.self, entry, into: &file.templateTasks)
            case .engagements:       take(BackupFile.EngagementRecord.self, entry, into: &file.engagements)
            case .invoices:          take(BackupFile.InvoiceRecord.self, entry, into: &file.invoices)
            case .invoiceLines:      take(BackupFile.InvoiceLineRecord.self, entry, into: &file.invoiceLines)
            case .payments:          take(BackupFile.PaymentRecord.self, entry, into: &file.payments)
            case .inbox:             take(BackupFile.InboxRecord.self, entry, into: &file.inbox)
            case .interactions:      take(BackupFile.InteractionRecord.self, entry, into: &file.interactions)
            case .savedFilters:      take(BackupFile.SavedFilterRecord.self, entry, into: &file.savedFilters)
            case .documentRequests:  take(BackupFile.DocumentRequestRecord.self, entry, into: &file.documentRequests)
            case .recurringInvoices: take(BackupFile.RecurringInvoiceRecord.self, entry, into: &file.recurringInvoices)
            case .expenses:          take(BackupFile.ExpenseRecord.self, entry, into: &file.expenses)
            case .pipelines:         take(BackupFile.PipelineRecord.self, entry, into: &pipelines)
            case .letterTemplates:   take(BackupFile.LetterTemplateRecord.self, entry, into: &letters)
            case .emailTemplates:    take(BackupFile.EmailTemplateRecord.self, entry, into: &emails)
            case .feeItems:          take(BackupFile.FeeItemRecord.self, entry, into: &fees)
            case .quotes:            take(BackupFile.QuoteRecord.self, entry, into: &quotes)
            }
        }
        file.pipelines = pipelines
        file.letterTemplates = letters
        file.emailTemplates = emails
        file.feeItems = fees
        file.quotes = quotes
        return (file, failed)
    }
}

// MARK: - Relationships (for "parent hasn't arrived yet")

enum SyncRelations {
    /// JSON field → the collection it points at, for real relationships only (not plain
    /// UUID fields like `blockedByID` or `pipelineID`).
    static let parents: [SyncCollection: [(field: String, target: SyncCollection)]] = [
        .projects: [("clientID", .clients)],
        .tasks: [("projectID", .projects), ("clientID", .clients)],
        .timeEntries: [("projectID", .projects)],
        .documents: [("clientID", .clients), ("projectID", .projects)],
        .templateTasks: [("templateID", .templates)],
        .engagements: [("clientID", .clients), ("templateID", .templates)],
        .invoices: [("clientID", .clients)],
        .invoiceLines: [("invoiceID", .invoices)],
        .payments: [("invoiceID", .invoices)],
        .inbox: [("clientID", .clients)],
        .interactions: [("clientID", .clients)],
        .documentRequests: [("clientID", .clients), ("projectID", .projects)],
        .recurringInvoices: [("clientID", .clients)],
        .expenses: [("clientID", .clients)],
        .quotes: [("clientID", .clients)],
    ]

    /// Keys this record points at.
    static func parentKeys(of entry: SyncEntry) -> [SyncKey] {
        guard let specs = parents[entry.key.collection],
              let object = (try? JSONSerialization.jsonObject(with: Data(entry.json.utf8))) as? [String: Any] else { return [] }
        return specs.compactMap { spec in
            guard let raw = object[spec.field] as? String, let id = UUID(uuidString: raw) else { return nil }
            return SyncKey(spec.target, id)
        }
    }

    /// Parents that are neither in `available` nor about to be.
    static func missingParents(of entry: SyncEntry, available: Set<SyncKey>) -> [SyncKey] {
        parentKeys(of: entry).filter { !available.contains($0) }
    }
}

// MARK: - Ledger

struct SyncLedger: Codable, Equatable {
    /// Hash of each record as this device last saw it in sync (document id → hash).
    var local: [String: String] = [:]
    /// Hash of the cloud version this device last applied or pushed.
    var remote: [String: String] = [:]

    func localHash(_ key: SyncKey) -> String? { local[key.documentID] }
    func remoteHash(_ key: SyncKey) -> String? { remote[key.documentID] }
    mutating func setLocal(_ key: SyncKey, _ hash: String) { local[key.documentID] = hash }
    mutating func setRemote(_ key: SyncKey, _ hash: String) { remote[key.documentID] = hash }
    mutating func forget(_ key: SyncKey) { local[key.documentID] = nil; remote[key.documentID] = nil }

    var localKeys: Set<SyncKey> { Set(local.keys.compactMap(SyncKey.init(documentID:))) }
}

// MARK: - Push planning

struct SyncPushPlan: Equatable {
    var upserts: [SyncKey] = []
    var deletes: [SyncKey] = []
    /// Deletions were found but look like a wipe, not a cleanup — held back for confirmation.
    var blockedDeletes: [SyncKey] = []
}

enum SyncPlanner {
    static let minimumForGuard = 10
    static let maxDeleteFraction = 0.3

    /// What to send to the cloud: records whose hash differs from the ledger (new or edited),
    /// and ledger records that no longer exist locally (deleted). `skip` holds records that
    /// must not be pushed right now (their links haven't resolved yet).
    static func plan(
        local: [SyncKey: SyncEntry],
        ledger: SyncLedger,
        skip: Set<SyncKey> = [],
        allowMassDeletes: Bool = false
    ) -> SyncPushPlan {
        var plan = SyncPushPlan()
        for (key, entry) in local where !skip.contains(key) {
            if ledger.localHash(key) != entry.hash { plan.upserts.append(key) }
        }
        let gone = ledger.localKeys.filter { local[$0] == nil && !skip.contains($0) }
        let looksLikeWipe = gone.count >= minimumForGuard
            && Double(gone.count) > maxDeleteFraction * Double(max(1, ledger.local.count))
        if looksLikeWipe && !allowMassDeletes {
            plan.blockedDeletes = Array(gone)
        } else {
            plan.deletes = Array(gone)
        }
        // Deterministic order (helps tests and keeps batches stable).
        plan.upserts.sort { $0.documentID < $1.documentID }
        plan.deletes.sort { $0.documentID < $1.documentID }
        plan.blockedDeletes.sort { $0.documentID < $1.documentID }
        return plan
    }
}

// MARK: - Applying remote changes

struct SyncRemoteChange: Equatable {
    var key: SyncKey
    /// nil = the document was deleted.
    var entry: SyncEntry?
}

struct SyncApplyPlan: Equatable {
    var upserts: [SyncEntry] = []
    var deletes: [SyncKey] = []
    /// Upserts held until their parent records arrive.
    var deferred: [SyncEntry] = []
    /// Remote versions we've now accounted for (recorded in the ledger).
    var seenRemote: [SyncKey: String] = [:]
    /// Deleted remotely; drop from the ledger.
    var forgotten: [SyncKey] = []
    /// Local edits that must be pushed back (they beat the remote change).
    var repush: [SyncKey] = []
}

enum SyncReconciler {
    /// Decides what to do with a batch of remote changes.
    /// - Local edits that haven't been pushed yet win over an incoming change to the same
    ///   record (they'll overwrite the cloud copy on the next push) — nothing typed on this
    ///   device is silently replaced.
    static func reconcile(
        changes: [SyncRemoteChange],
        local: [SyncKey: SyncEntry],
        ledger: SyncLedger
    ) -> SyncApplyPlan {
        var plan = SyncApplyPlan()

        func isDirty(_ key: SyncKey) -> Bool {
            guard let entry = local[key], let synced = ledger.localHash(key) else { return false }
            return entry.hash != synced
        }

        var incoming: [SyncEntry] = []
        for change in changes {
            let key = change.key
            if let entry = change.entry {
                if ledger.remoteHash(key) == entry.hash { continue }        // already accounted for
                if isDirty(key) {
                    plan.seenRemote[key] = entry.hash                       // don't revisit; our edit will overwrite
                    plan.repush.append(key)
                } else {
                    incoming.append(entry)
                    plan.seenRemote[key] = entry.hash
                }
            } else {
                if local[key] == nil {
                    plan.forgotten.append(key)
                } else if isDirty(key) {
                    plan.forgotten.append(key)                              // resurrect: push our version again
                    plan.repush.append(key)
                } else {
                    plan.deletes.append(key)
                    plan.forgotten.append(key)
                }
            }
        }

        // Hold back records whose parents aren't here (or in this batch) yet.
        let available = Set(local.keys).union(incoming.map(\.key))
        for entry in incoming {
            if SyncRelations.missingParents(of: entry, available: available).isEmpty {
                plan.upserts.append(entry)
            } else {
                // Not applied yet, so don't record it as seen — after a restart it must be
                // looked at again.
                plan.deferred.append(entry)
                plan.seenRemote[entry.key] = nil
            }
        }
        plan.upserts.sort { $0.key.documentID < $1.key.documentID }
        return plan
    }
}
