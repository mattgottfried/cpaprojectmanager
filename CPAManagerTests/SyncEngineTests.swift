import XCTest
import SwiftData
@testable import CPAManager

/// A stand-in for Firestore shared by two "devices".
@MainActor
final class FakeCloud {
    var documents: [SyncKey: String] = [:]
    fileprivate var backends: [FakeBackend] = []

    func attach(_ backend: FakeBackend) { backends.append(backend) }

    fileprivate func commit(upserts: [SyncEntry], deletes: [SyncKey], from writer: FakeBackend) {
        var changes: [SyncRemoteChange] = []
        for entry in upserts {
            documents[entry.key] = entry.json
            changes.append(SyncRemoteChange(key: entry.key, entry: entry))
        }
        for key in deletes {
            documents[key] = nil
            changes.append(SyncRemoteChange(key: key, entry: nil))
        }
        // Like Firestore, the writer doesn't see its own confirmed write as a change.
        for backend in backends where backend !== writer {
            backend.onBatch?(changes, false)
        }
    }

    fileprivate var initialChanges: [SyncRemoteChange] {
        documents.map { SyncRemoteChange(key: $0.key, entry: SyncEntry(key: $0.key, json: $0.value)) }
    }
}

final class FakeBackend: SyncBackend, @unchecked Sendable {
    private let cloud: FakeCloud
    fileprivate var onBatch: (@MainActor ([SyncRemoteChange], Bool) -> Void)?
    private(set) var writes = 0

    @MainActor init(cloud: FakeCloud) {
        self.cloud = cloud
        cloud.attach(self)
    }

    func start(
        onBatch: @escaping @MainActor ([SyncRemoteChange], Bool) -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.onBatch = onBatch
        MainActor.assumeIsolated {
            onBatch(cloud.initialChanges, true)
        }
    }

    func stop() { onBatch = nil }

    func write(upserts: [SyncEntry], deletes: [SyncKey]) async throws {
        await MainActor.run {
            writes += 1
            cloud.commit(upserts: upserts, deletes: deletes, from: self)
        }
    }
}

@MainActor
final class SyncEngineTests: XCTestCase {
    private struct Device {
        let context: ModelContext
        let container: ModelContainer
        let engine: SyncEngine
        let ledger: MemoryLedgerStore
    }

    private func makeContext() throws -> (ModelContext, ModelContainer) {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Persistence.schema, configurations: config)
        return (container.mainContext, container)
    }

    private func makeDevice(cloud: FakeCloud) throws -> Device {
        let (context, container) = try makeContext()
        let ledger = MemoryLedgerStore()
        let engine = SyncEngine(context: context, backend: FakeBackend(cloud: cloud), ledgerStore: ledger)
        engine.automaticallySchedulesPushes = false
        return Device(context: context, container: container, engine: engine, ledger: ledger)
    }

    private func clients(_ context: ModelContext) -> [Client] {
        (try? context.fetch(FetchDescriptor<Client>())) ?? []
    }

    // MARK: Convergence

    func testNewRecordsReachAnotherDeviceWithRelationshipsIntact() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let client = Client(name: "Dana Lee", email: "dana@x.com")
        a.context.insert(client)
        let project = Project(title: "Lee 1040", client: client)
        a.context.insert(project)
        a.context.insert(TaskItem(title: "Call Dana", project: project))
        try a.context.save()

        a.engine.start()
        await a.engine.pushNow()
        XCTAssertEqual(cloud.documents.count, 3)

        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        let received = try XCTUnwrap(clients(b.context).first)
        XCTAssertEqual(received.name, "Dana Lee")
        XCTAssertEqual(received.projectList.count, 1)
        XCTAssertEqual(received.projectList.first?.taskList.first?.title, "Call Dana")
        a.engine.stop(); b.engine.stop()
    }

    func testEditsAndDeletesPropagate() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let client = Client(name: "Old Name")
        a.context.insert(client)
        let task = TaskItem(title: "Temp")
        a.context.insert(task)
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()

        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        XCTAssertEqual(clients(b.context).first?.name, "Old Name")

        client.name = "New Name"
        a.context.delete(task)
        try a.context.save()
        await a.engine.pushNow()

        XCTAssertEqual(clients(b.context).first?.name, "New Name")
        XCTAssertEqual(try b.context.fetchCount(FetchDescriptor<TaskItem>()), 0)
        a.engine.stop(); b.engine.stop()
    }

    func testUnchangedStorePushesNothing() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        a.context.insert(Client(name: "X"))
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()
        let backend = cloud.backendsForTests.first
        let writes = backend?.writes ?? -1
        await a.engine.pushNow()
        XCTAssertEqual(backend?.writes, writes, "nothing changed, nothing sent")
        a.engine.stop()
    }

    func testRemoteChangeDoesNotEchoBack() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let client = Client(name: "Echo")
        a.context.insert(client)
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()
        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        let bBackend = cloud.backendsForTests[1]
        let before = bBackend.writes
        await b.engine.pushNow()
        XCTAssertEqual(bBackend.writes, before, "applying a remote record must not make the receiver push it again")
        a.engine.stop(); b.engine.stop()
    }

    // MARK: Conflicts

    func testUnpushedLocalEditWinsOverIncomingChange() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let client = Client(name: "Start")
        a.context.insert(client)
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()

        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        let onB = try XCTUnwrap(clients(b.context).first)

        // B edits but hasn't pushed; A edits and pushes.
        onB.name = "From B"
        try b.context.save()
        client.name = "From A"
        try a.context.save()
        await a.engine.pushNow()

        XCTAssertEqual(onB.name, "From B", "B's unpushed edit isn't clobbered")
        await b.engine.pushNow()
        XCTAssertEqual(client.name, "From B", "and it then propagates to A")
        a.engine.stop(); b.engine.stop()
    }

    // MARK: Safety

    func testMassDeletionIsHeldBackAndCanBeRestored() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        for i in 0..<20 { a.context.insert(TaskItem(title: "Task \(i)")) }
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()
        XCTAssertEqual(cloud.documents.count, 20)

        // Everything vanishes locally (e.g. a reset store with the old ledger left behind).
        for task in try a.context.fetch(FetchDescriptor<TaskItem>()) { a.context.delete(task) }
        try a.context.save()
        await a.engine.pushNow()

        XCTAssertEqual(cloud.documents.count, 20, "the cloud copy is untouched")
        XCTAssertEqual(a.engine.blockedDeletionCount, 20)
        if case .attention = a.engine.phase {} else { XCTFail("expected the attention state, got \(a.engine.phase)") }

        a.engine.restoreDeletedFromCloud()
        XCTAssertEqual(try a.context.fetchCount(FetchDescriptor<TaskItem>()), 20)
        XCTAssertEqual(a.engine.blockedDeletionCount, 0)
        a.engine.stop()
    }

    func testConfirmedMassDeletionGoesThrough() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        for i in 0..<15 { a.context.insert(TaskItem(title: "T\(i)")) }
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()
        for task in try a.context.fetch(FetchDescriptor<TaskItem>()) { a.context.delete(task) }
        try a.context.save()
        await a.engine.pushNow()
        XCTAssertEqual(cloud.documents.count, 15)

        a.engine.confirmDeletions()
        await a.engine.pushNow()
        XCTAssertEqual(cloud.documents.count, 0)
        a.engine.stop()
    }

    func testChildArrivingBeforeItsParentIsHeldThenLinked() async throws {
        let cloud = FakeCloud()
        // Author the records on device A, but hand device B the child first.
        let a = try makeDevice(cloud: cloud)
        let client = Client(name: "Parent Co")
        a.context.insert(client)
        let project = Project(title: "Child job", client: client)
        a.context.insert(project)
        try a.context.save()
        let snapshot = SyncStore.snapshot(a.context)
        let clientEntry = try XCTUnwrap(snapshot.entries.values.first { $0.key.collection == .clients })
        let projectEntry = try XCTUnwrap(snapshot.entries.values.first { $0.key.collection == .projects })

        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        let backend = cloud.backendsForTests[1]
        backend.onBatch?([SyncRemoteChange(key: projectEntry.key, entry: projectEntry)], false)
        XCTAssertEqual(try b.context.fetchCount(FetchDescriptor<Project>()), 0, "held back until its client arrives")

        backend.onBatch?([SyncRemoteChange(key: clientEntry.key, entry: clientEntry)], false)
        let linked = try XCTUnwrap(try b.context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(linked.client?.name, "Parent Co")
        b.engine.stop(); a.engine.stop()
    }

    func testNothingIsPushedBeforeTheCloudStateIsKnown() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        a.context.insert(Client(name: "Early"))
        try a.context.save()
        // Not started: no snapshot yet.
        await a.engine.pushNow()
        XCTAssertTrue(cloud.documents.isEmpty)
    }

    // MARK: Attached files

    private func documents(_ context: ModelContext) -> [Document] {
        (try? context.fetch(FetchDescriptor<Document>())) ?? []
    }

    func testEditingADocumentRecordDoesNotStripItsFileFromTheCloud() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let doc = Document(filename: "W-2", fileExtension: "pdf", data: Data(repeating: 7, count: 10_000))
        a.context.insert(doc)
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()

        doc.filename = "W-2 (renamed)"
        try a.context.save()
        await a.engine.pushNow()

        let c = try makeDevice(cloud: cloud)
        c.engine.start()
        let received = try XCTUnwrap(documents(c.context).first)
        XCTAssertEqual(received.filename, "W-2 (renamed)")
        XCTAssertEqual(received.data.count, 10_000, "a device joining later still gets the file")
        a.engine.stop(); c.engine.stop()
    }

    func testOversizedFileIsCountedOnceAndTheRecordStillSyncs() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        let doc = Document(filename: "Huge", fileExtension: "pdf", data: Data(repeating: 1, count: 900_000))
        a.context.insert(doc)
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()
        XCTAssertNotNil(cloud.documents[SyncKey(.documents, doc.id)])
        XCTAssertEqual(a.engine.oversizedFileCount, 1)

        doc.filename = "Huge (renamed)"
        try a.context.save()
        await a.engine.pushNow()
        XCTAssertEqual(a.engine.oversizedFileCount, 1, "not counted again on every push")
        a.engine.stop()
    }

    func testAnEmptyLocalFileNeverWipesTheCopyOnAnotherDevice() async throws {
        let cloud = FakeCloud()
        let a = try makeDevice(cloud: cloud)
        a.context.insert(Document(filename: "ID", fileExtension: "jpg", data: Data(repeating: 3, count: 5_000)))
        try a.context.save()
        a.engine.start()
        await a.engine.pushNow()

        // A device that has the record but not the bytes edits it.
        let b = try makeDevice(cloud: cloud)
        b.engine.start()
        let onB = try XCTUnwrap(documents(b.context).first)
        onB.data = Data()
        onB.filename = "ID (b)"
        try b.context.save()
        await b.engine.pushNow()

        XCTAssertEqual(documents(a.context).first?.data.count, 5_000)
        XCTAssertEqual(documents(a.context).first?.filename, "ID (b)")
        a.engine.stop(); b.engine.stop()
    }
}

extension FakeCloud {
    fileprivate var backendsForTests: [FakeBackend] { backends }
}
