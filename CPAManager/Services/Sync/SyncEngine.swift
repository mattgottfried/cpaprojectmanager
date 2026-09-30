import Foundation
import SwiftData
import Observation

/// The network side of sync, kept behind a protocol so the engine is testable without Firebase.
protocol SyncBackend: AnyObject {
    /// Streams every record: the first call (`isInitial == true`) carries the whole current
    /// state, later calls carry changes. Callbacks arrive on the main actor.
    func start(
        onBatch: @escaping @MainActor ([SyncRemoteChange], _ isInitial: Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    )
    func stop()
    /// Applies all writes atomically per call; may wait (offline) until they can be sent.
    func write(upserts: [SyncEntry], deletes: [SyncKey]) async throws
}

/// Keeps the local SwiftData store and the cloud copy in step.
///
/// - Local edits: any save schedules a push. The engine diffs the store against the ledger and
///   sends only what changed (and deletions).
/// - Remote edits: applied through `SyncReconciler`; an unpushed local edit to the same record wins.
/// - Safety: never pushes before the cloud's current state is known, holds back mass deletions
///   for confirmation, and never overwrites a record's link with "none" while its parent is
///   still on the way.
@MainActor
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case stopped
        case connecting
        case syncing
        case idle
        /// Needs the user (e.g. a suspicious mass deletion).
        case attention(String)
        case error(String)
    }

    private(set) var phase: Phase = .stopped
    private(set) var lastPushDate: Date?
    private(set) var lastPullDate: Date?
    private(set) var pendingUploads = 0
    /// Files too big to travel inside a record (they stay on the device that added them).
    var oversizedFileCount: Int { oversizedKeys.count }
    private var oversizedKeys: Set<SyncKey> = []
    /// Records waiting for a parent record to arrive.
    var deferredCount: Int { deferred.count }
    private(set) var blockedDeletionCount = 0

    private let context: ModelContext
    private let backend: SyncBackend
    private let ledgerStore: SyncLedgerStore
    private var ledger: SyncLedger

    private var remoteCache: [SyncKey: SyncEntry] = [:]
    private struct Deferred { var entry: SyncEntry; var since: Date; var appliedPartially: Bool }
    private var deferred: [SyncKey: Deferred] = [:]
    private var blocked: [SyncKey] = []

    private var initialSnapshotSeen = false
    private var saveObserver: NSObjectProtocol?
    private var pushTask: Task<Void, Never>?
    private var deferredTask: Task<Void, Never>?
    private var isPushing = false
    private var pushAgain = false
    private var allowMassDeletes = false

    /// Tests turn this off and call `pushNow()` themselves.
    var automaticallySchedulesPushes = true

    /// How long a record waits for its parents before it's applied without them.
    static let parentWait: TimeInterval = 60

    init(context: ModelContext, backend: SyncBackend, ledgerStore: SyncLedgerStore) {
        self.context = context
        self.backend = backend
        self.ledgerStore = ledgerStore
        self.ledger = ledgerStore.load()
    }

    // MARK: Lifecycle

    func start() {
        guard phase == .stopped else { return }
        phase = .connecting
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.schedulePush() }
        }
        backend.start(
            onBatch: { [weak self] changes, initial in self?.receive(changes, isInitial: initial) },
            onError: { [weak self] message in self?.phase = .error(message) }
        )
    }

    func stop() {
        backend.stop()
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        saveObserver = nil
        pushTask?.cancel()
        deferredTask?.cancel()
        initialSnapshotSeen = false
        phase = .stopped
    }

    /// Push soon (foreground, "Sync Now").
    func kick() {
        schedulePush(after: 0.2)
    }

    // MARK: Receiving

    private func receive(_ changes: [SyncRemoteChange], isInitial: Bool) {
        for change in changes { remoteCache[change.key] = change.entry }
        if isInitial { initialSnapshotSeen = true }
        applyRemote(changes)
        lastPullDate = .now
        if isInitial { schedulePush(after: 0.1) }
        if phase == .connecting { phase = .idle }
    }

    private func applyRemote(_ changes: [SyncRemoteChange]) {
        let before = SyncStore.snapshot(context)
        let plan = SyncReconciler.reconcile(changes: changes, local: before.entries, ledger: ledger)

        // A newer version (or a deletion) replaces anything held back for that record.
        for change in changes { deferred[change.key] = nil }

        var upserts = plan.upserts
        let now = Date.now
        let arrivingKeys = Set(before.entries.keys).union(upserts.map(\.key))

        // Retry held-back records whose parents have arrived; after a wait, apply them without.
        var retried: [SyncKey] = []
        for (key, item) in deferred {
            let missing = SyncRelations.missingParents(of: item.entry, available: arrivingKeys)
            if missing.isEmpty {
                upserts.append(item.entry)
                retried.append(key)
            } else if !item.appliedPartially && now.timeIntervalSince(item.since) > Self.parentWait {
                upserts.append(item.entry)
                deferred[key]?.appliedPartially = true
            }
        }
        for key in retried { deferred[key] = nil }
        for entry in plan.deferred {
            deferred[entry.key] = Deferred(entry: entry, since: now, appliedPartially: false)
        }

        let failed = SyncStore.apply(upserts, to: context)
        SyncStore.delete(plan.deletes, from: context)
        try? context.save()

        let after = SyncStore.snapshot(context)

        // Records removed as a side effect of a remote deletion (cascades) aren't local deletions.
        let cascaded = Set(before.entries.keys).subtracting(after.entries.keys).subtracting(plan.deletes)
        for key in cascaded { ledger.forget(key); remoteCache[key] = nil }

        // What this device holds right after applying is what counts as "in sync"; anything
        // that later differs from it is a local edit. (The remote hash marks the cloud version
        // as seen, so the same document being delivered again is ignored.)
        for entry in upserts where !failed.contains(entry.key) {
            if let stored = after.entries[entry.key] { ledger.setLocal(entry.key, stored.hash) }
            ledger.setRemote(entry.key, entry.hash)
        }
        for (key, hash) in plan.seenRemote { ledger.setRemote(key, hash) }
        // Deleted remotely (or a resurrected local record whose ledger entry must go so it is
        // pushed again).
        for key in plan.forgotten { ledger.forget(key) }
        ledgerStore.save(ledger)

        scheduleDeferredFlush()
        if !upserts.isEmpty || !plan.deletes.isEmpty { schedulePush() }
    }

    private func scheduleDeferredFlush() {
        deferredTask?.cancel()
        guard deferred.values.contains(where: { !$0.appliedPartially }) else { return }
        deferredTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.parentWait + 1) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.applyRemote([])
        }
    }

    // MARK: Pushing

    private func schedulePush(after delay: TimeInterval = 1.5) {
        guard phase != .stopped, automaticallySchedulesPushes else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.pushNow()
        }
    }

    /// Sends local changes and deletions. Exposed for tests and "Sync Now".
    func pushNow() async {
        guard initialSnapshotSeen else { return }
        if isPushing { pushAgain = true; return }
        isPushing = true
        defer { isPushing = false }

        repeat {
            pushAgain = false
            let snapshot = SyncStore.snapshot(context)
            let plan = SyncPlanner.plan(
                local: snapshot.entries, ledger: ledger,
                skip: Set(deferred.keys), allowMassDeletes: allowMassDeletes
            )
            blocked = plan.blockedDeletes
            blockedDeletionCount = blocked.count
            if !blocked.isEmpty {
                phase = .attention("\(blocked.count) records are missing from this device. Deleting them everywhere would remove them from your other devices too.")
            }

            let slimEntries = plan.upserts.compactMap { snapshot.entries[$0] }
            // File-carrying records always go up with their files, so a later edit (a rename, a
            // signature status) never strips the file from the cloud copy. The ledger tracks
            // the slim form.
            let fileKeys = plan.upserts.filter { $0.collection == .documents || $0.collection == .expenses }
            let full = fileKeys.isEmpty ? SyncStore.Snapshot(entries: [:], oversizedFiles: []) : SyncStore.fullEntries(for: fileKeys, context: context)
            oversizedKeys.subtract(fileKeys)
            oversizedKeys.formUnion(full.oversizedFiles)
            let entries = slimEntries.map { full.entries[$0.key] ?? $0 }
            if entries.isEmpty && plan.deletes.isEmpty {
                pendingUploads = 0
                if blocked.isEmpty, phase != .stopped { phase = .idle }
                break
            }

            pendingUploads = entries.count + plan.deletes.count
            if blocked.isEmpty { phase = .syncing }
            do {
                try await sendInChunks(entries: entries, deletes: plan.deletes)
                for (slim, sent) in zip(slimEntries, entries) {
                    ledger.setLocal(slim.key, slim.hash)
                    ledger.setRemote(sent.key, sent.hash)
                }
                // What we sent is now the cloud's version (our own confirmed writes aren't
                // delivered back to us as changes).
                for sent in entries { remoteCache[sent.key] = sent }
                for key in plan.deletes { ledger.forget(key); remoteCache[key] = nil; oversizedKeys.remove(key) }
                ledgerStore.save(ledger)
                lastPushDate = .now
                pendingUploads = 0
                if blocked.isEmpty, phase != .stopped { phase = .idle }
            } catch {
                if phase != .stopped { phase = .error(error.localizedDescription) }
                break
            }
        } while pushAgain
        allowMassDeletes = false
    }

    private func sendInChunks(entries: [SyncEntry], deletes: [SyncKey]) async throws {
        let chunk = 400
        var upsertIndex = 0
        while upsertIndex < entries.count {
            let end = min(upsertIndex + chunk, entries.count)
            try await backend.write(upserts: Array(entries[upsertIndex..<end]), deletes: [])
            upsertIndex = end
        }
        var deleteIndex = 0
        while deleteIndex < deletes.count {
            let end = min(deleteIndex + chunk, deletes.count)
            try await backend.write(upserts: [], deletes: Array(deletes[deleteIndex..<end]))
            deleteIndex = end
        }
    }

    // MARK: Resolving a blocked mass deletion

    /// The user says the deletions are real: send them.
    func confirmDeletions() {
        allowMassDeletes = true
        blocked = []
        blockedDeletionCount = 0
        if case .attention = phase { phase = .idle }
        schedulePush(after: 0.1)
    }

    /// The user says they weren't intended: bring those records back from the cloud copy.
    func restoreDeletedFromCloud() {
        let keys = blocked
        blocked = []
        blockedDeletionCount = 0
        for key in keys { ledger.forget(key) }
        ledgerStore.save(ledger)
        let changes = keys.compactMap { key in remoteCache[key].map { SyncRemoteChange(key: key, entry: $0) } }
        if case .attention = phase { phase = .idle }
        applyRemote(changes)
    }
}
