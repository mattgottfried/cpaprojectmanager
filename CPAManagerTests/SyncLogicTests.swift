import XCTest
@testable import CPAManager

final class SyncLogicTests: XCTestCase {
    private func entry(_ collection: SyncCollection, _ json: String, id: UUID = UUID()) -> SyncEntry {
        SyncEntry(key: SyncKey(collection, id), json: json)
    }

    func testKeyRoundTripsThroughDocumentID() {
        let id = UUID()
        let key = SyncKey(.invoiceLines, id)
        XCTAssertEqual(key.documentID, "invoiceLines~\(id.uuidString)")
        XCTAssertEqual(SyncKey(documentID: key.documentID), key)
        XCTAssertNil(SyncKey(documentID: "nonsense"))
        XCTAssertNil(SyncKey(documentID: "unknown~\(id.uuidString)"))
        XCTAssertNil(SyncKey(documentID: "clients~not-a-uuid"))
    }

    func testHashIsStableAndSensitive() {
        XCTAssertEqual(SyncHash.hash("a"), SyncHash.hash("a"))
        XCTAssertNotEqual(SyncHash.hash("a"), SyncHash.hash("b"))
        XCTAssertEqual(SyncHash.hash("").count, 64)
    }

    // MARK: Push planning

    func testPlanPushesNewAndChangedAndDeleted() {
        let a = entry(.clients, "{\"v\":1}"), b = entry(.clients, "{\"v\":2}"), c = entry(.tasks, "{\"v\":3}")
        var ledger = SyncLedger()
        ledger.setLocal(a.key, a.hash)                                   // unchanged
        ledger.setLocal(b.key, SyncHash.hash("old"))                     // edited
        let gone = SyncKey(.projects, UUID())
        ledger.setLocal(gone, "x")                                       // deleted locally
        let plan = SyncPlanner.plan(local: [a.key: a, b.key: b, c.key: c], ledger: ledger)
        XCTAssertEqual(Set(plan.upserts), [b.key, c.key])
        XCTAssertEqual(plan.deletes, [gone])
        XCTAssertTrue(plan.blockedDeletes.isEmpty)
    }

    func testPlanSkipsHeldBackRecords() {
        let a = entry(.projects, "{}")
        let plan = SyncPlanner.plan(local: [a.key: a], ledger: SyncLedger(), skip: [a.key])
        XCTAssertTrue(plan.upserts.isEmpty)
    }

    func testMassDeletionIsBlockedUnlessAllowed() {
        var ledger = SyncLedger()
        let keys = (0..<20).map { _ in SyncKey(.tasks, UUID()) }
        for key in keys { ledger.setLocal(key, "h") }
        let keep = entry(.clients, "{}")
        ledger.setLocal(keep.key, keep.hash)

        let blocked = SyncPlanner.plan(local: [keep.key: keep], ledger: ledger)
        XCTAssertTrue(blocked.deletes.isEmpty)
        XCTAssertEqual(blocked.blockedDeletes.count, 20)

        let allowed = SyncPlanner.plan(local: [keep.key: keep], ledger: ledger, allowMassDeletes: true)
        XCTAssertEqual(allowed.deletes.count, 20)
        XCTAssertTrue(allowed.blockedDeletes.isEmpty)
    }

    func testSmallDeletionsAreNeverBlocked() {
        var ledger = SyncLedger()
        let keys = (0..<5).map { _ in SyncKey(.tasks, UUID()) }
        for key in keys { ledger.setLocal(key, "h") }
        let plan = SyncPlanner.plan(local: [:], ledger: ledger)
        XCTAssertEqual(plan.deletes.count, 5, "deleting a handful (even all) of a tiny store is normal")
    }

    func testEmptyStoreWithBigLedgerIsBlocked() {
        var ledger = SyncLedger()
        for _ in 0..<50 { ledger.setLocal(SyncKey(.tasks, UUID()), "h") }
        let plan = SyncPlanner.plan(local: [:], ledger: ledger)
        XCTAssertEqual(plan.blockedDeletes.count, 50, "a wiped store must not wipe the cloud")
    }

    // MARK: Relations

    func testParentKeysAndMissingParents() {
        let client = UUID(), project = UUID()
        let task = entry(.tasks, "{\"id\":\"\(UUID().uuidString)\",\"clientID\":\"\(client.uuidString)\",\"projectID\":\"\(project.uuidString)\",\"blockedByID\":\"\(UUID().uuidString)\"}")
        let parents = SyncRelations.parentKeys(of: task)
        XCTAssertEqual(Set(parents), [SyncKey(.clients, client), SyncKey(.projects, project)], "blockedByID isn't a relationship")
        XCTAssertEqual(SyncRelations.missingParents(of: task, available: [SyncKey(.clients, client)]), [SyncKey(.projects, project)])
        XCTAssertTrue(SyncRelations.parentKeys(of: entry(.clients, "{}")).isEmpty)
        XCTAssertTrue(SyncRelations.parentKeys(of: entry(.tasks, "not json")).isEmpty)
    }

    // MARK: Reconciling remote changes

    func testNewRemoteRecordIsApplied() {
        let e = entry(.clients, "{\"n\":1}")
        let plan = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: e.key, entry: e)], local: [:], ledger: SyncLedger())
        XCTAssertEqual(plan.upserts, [e])
        XCTAssertEqual(plan.seenRemote[e.key], e.hash)
    }

    func testAlreadyAccountedForVersionIsIgnored() {
        let e = entry(.clients, "{}")
        var ledger = SyncLedger()
        ledger.setRemote(e.key, e.hash)
        ledger.setLocal(e.key, e.hash)
        let plan = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: e.key, entry: e)], local: [e.key: e], ledger: ledger)
        XCTAssertTrue(plan.upserts.isEmpty)
        XCTAssertTrue(plan.repush.isEmpty)
    }

    func testUnpushedLocalEditBeatsIncomingChange() {
        let key = SyncKey(.clients, UUID())
        let synced = SyncEntry(key: key, json: "{\"v\":\"synced\"}")
        let localEdit = SyncEntry(key: key, json: "{\"v\":\"local\"}")
        let remoteEdit = SyncEntry(key: key, json: "{\"v\":\"remote\"}")
        var ledger = SyncLedger()
        ledger.setLocal(key, synced.hash)
        ledger.setRemote(key, synced.hash)
        let plan = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: key, entry: remoteEdit)], local: [key: localEdit], ledger: ledger)
        XCTAssertTrue(plan.upserts.isEmpty, "the local edit isn't overwritten")
        XCTAssertEqual(plan.repush, [key])
        XCTAssertEqual(plan.seenRemote[key], remoteEdit.hash)
    }

    func testRemoteDeletionRemovesUnlessLocallyEdited() {
        let key = SyncKey(.tasks, UUID())
        let synced = SyncEntry(key: key, json: "{\"v\":1}")
        var ledger = SyncLedger()
        ledger.setLocal(key, synced.hash)
        ledger.setRemote(key, synced.hash)

        let clean = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: key, entry: nil)], local: [key: synced], ledger: ledger)
        XCTAssertEqual(clean.deletes, [key])
        XCTAssertEqual(clean.forgotten, [key])

        let edited = SyncEntry(key: key, json: "{\"v\":2}")
        let dirty = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: key, entry: nil)], local: [key: edited], ledger: ledger)
        XCTAssertTrue(dirty.deletes.isEmpty, "a local edit resurrects the record")
        XCTAssertEqual(dirty.repush, [key])

        let missing = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: key, entry: nil)], local: [:], ledger: ledger)
        XCTAssertTrue(missing.deletes.isEmpty)
        XCTAssertEqual(missing.forgotten, [key])
    }

    func testChildWithoutParentIsDeferredAndNotMarkedSeen() {
        let clientID = UUID()
        let project = entry(.projects, "{\"clientID\":\"\(clientID.uuidString)\"}")
        let plan = SyncReconciler.reconcile(changes: [SyncRemoteChange(key: project.key, entry: project)], local: [:], ledger: SyncLedger())
        XCTAssertTrue(plan.upserts.isEmpty)
        XCTAssertEqual(plan.deferred, [project])
        XCTAssertNil(plan.seenRemote[project.key], "must be reconsidered after a restart")

        // Parent arriving in the same batch lets both through.
        let client = SyncEntry(key: SyncKey(.clients, clientID), json: "{}")
        let both = SyncReconciler.reconcile(
            changes: [SyncRemoteChange(key: project.key, entry: project), SyncRemoteChange(key: client.key, entry: client)],
            local: [:], ledger: SyncLedger()
        )
        XCTAssertEqual(Set(both.upserts.map(\.key)), [project.key, client.key])
        XCTAssertTrue(both.deferred.isEmpty)
    }

    func testLedgerRoundTripsThroughJSON() throws {
        var ledger = SyncLedger()
        let key = SyncKey(.quotes, UUID())
        ledger.setLocal(key, "a"); ledger.setRemote(key, "b")
        let decoded = try JSONDecoder().decode(SyncLedger.self, from: try JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
        ledger.forget(key)
        XCTAssertNil(ledger.localHash(key))
        XCTAssertNil(ledger.remoteHash(key))
    }
}
