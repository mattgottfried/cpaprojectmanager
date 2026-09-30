import XCTest
import SwiftData
@testable import CPAManager

private let cal = Calendar.current
private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
}

final class SyncHealthTests: XCTestCase {
    private let now = day(2026, 9, 30)

    private func input(signedIn: Bool = true, phase: SyncEngine.Phase = .idle, pending: Int = 0, deferred: Int = 0,
                       blocked: Int = 0, oversized: Int = 0, push: Date? = day(2026, 9, 30), pull: Date? = day(2026, 9, 30)) -> SyncHealthInput {
        SyncHealthInput(isSignedIn: signedIn, phase: phase, pendingUploads: pending, deferredCount: deferred,
                        blockedDeletions: blocked, oversizedFiles: oversized, lastPush: push, lastPull: pull)
    }

    func testHealthyAndSigningStates() {
        XCTAssertEqual(SyncHealth.assess(input(), now: now).level, .good)
        XCTAssertEqual(SyncHealth.assess(input(), now: now).headline, "Everything is in sync")
        XCTAssertEqual(SyncHealth.assess(input(phase: .syncing), now: now).headline, "Syncing…")
        let signedOut = SyncHealth.assess(input(signedIn: false), now: now)
        XCTAssertEqual(signedOut.level, .watch)
        XCTAssertEqual(signedOut.headline, "Not signed in")
    }

    func testErrorIsAProblemAndComesFirst() {
        let report = SyncHealth.assess(input(phase: .error("Missing permissions"), oversized: 1), now: now)
        XCTAssertEqual(report.level, .problem)
        XCTAssertEqual(report.issues.first, "Missing permissions")
        XCTAssertEqual(report.issues.count, 2)
    }

    func testPendingUploadsOnlyMatterOnceStale() {
        XCTAssertEqual(SyncHealth.assess(input(pending: 3, push: now), now: now).level, .good, "just pushed")
        let stale = SyncHealth.assess(input(pending: 3, push: now.addingTimeInterval(-3_600)), now: now)
        XCTAssertEqual(stale.level, .watch)
        XCTAssertTrue(stale.issues.contains { $0.contains("3 changes haven't uploaded") })
        XCTAssertEqual(SyncHealth.assess(input(phase: .syncing, pending: 3, push: nil), now: now).level, .good, "mid-sync is fine")
    }

    func testWatchItems() {
        XCTAssertTrue(SyncHealth.assess(input(deferred: 2), now: now).issues.contains { $0.contains("2 records are waiting") })
        XCTAssertTrue(SyncHealth.assess(input(blocked: 1), now: now).issues.contains { $0.contains("1 record is missing") })
        XCTAssertTrue(SyncHealth.assess(input(oversized: 2), now: now).issues.contains { $0.contains("Google Drive") })
        let quiet = SyncHealth.assess(input(pull: now.addingTimeInterval(-3 * 86_400)), now: now)
        XCTAssertTrue(quiet.issues.contains { $0.contains("3 days") })
    }

    func testAttentionTextIsNotRepeatedForBlockedDeletions() {
        let text = "12 records are missing from this device. Deleting them everywhere would remove them from your other devices too."
        let report = SyncHealth.assess(input(phase: .attention(text), blocked: 12), now: now)
        XCTAssertEqual(report.issues.filter { $0.contains("missing from this device") }.count, 1)
    }
}

final class DuplicateClientsTests: XCTestCase {
    private func client(_ name: String, company: String = "", email: String = "", created: Int = 0, records: Int = 0) -> DupClientInput {
        DupClientInput(id: UUID(), name: name, company: company, email: email,
                       createdAt: Date(timeIntervalSince1970: Double(created)), recordCount: records)
    }

    func testSameNameAndSameEmailGroupTogether() {
        let a = client("Dana Lee", records: 5), b = client("dana  lee", created: 5), c = client("D. Lee", email: "DANA@x.com")
        let d = client("Dana L", email: "dana@x.com"), e = client("Someone Else")
        let groups = DuplicateClients.groups([a, b, c, d, e])
        XCTAssertEqual(groups.count, 2)
        let names = groups.first { $0.keeper == a.id }
        XCTAssertEqual(names?.others, [b.id])
        XCTAssertEqual(names?.reason, "Same name")
        let emails = groups.first { $0.keeper != a.id }
        XCTAssertEqual(Set([emails?.keeper].compactMap { $0 } + (emails?.others ?? [])), [c.id, d.id])
        XCTAssertEqual(emails?.reason, "Same email")
    }

    func testKeeperHasTheMostRecordsThenTheOldest() {
        let old = client("Pat", created: 1), busy = client("Pat", created: 9, records: 4), newer = client("Pat", created: 5)
        let group = DuplicateClients.groups([old, busy, newer]).first
        XCTAssertEqual(group?.keeper, busy.id)
        XCTAssertEqual(group?.others, [old.id, newer.id], "then the oldest first")
    }

    func testDifferentCompaniesAndBlankNamesAreNotDuplicates() {
        XCTAssertTrue(DuplicateClients.groups([client("Pat", company: "Acme"), client("Pat", company: "Globex")]).isEmpty)
        XCTAssertTrue(DuplicateClients.groups([client(""), client("")]).isEmpty)
        XCTAssertTrue(DuplicateClients.groups([]).isEmpty)
    }

    func testChainedMatchesFormOneGroup() {
        // a~b by name, b~c by email.
        let a = client("Sam Roe", records: 2), b = client("Sam Roe", email: "s@x.com"), c = client("Samuel R", email: "s@x.com")
        let groups = DuplicateClients.groups([a, b, c])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].others.count, 2)
        XCTAssertEqual(groups[0].reason, "Same email and Same name")
    }
}

final class AutoBackupLogicTests: XCTestCase {
    func testFileNamesRoundTripAndStayOneADay() {
        let name = AutoBackupLogic.fileName(for: day(2026, 9, 30, hour: 23))
        XCTAssertEqual(name, "CPAManager-backup-2026-09-30.json")
        XCTAssertEqual(name, AutoBackupLogic.fileName(for: day(2026, 9, 30, hour: 1)))
        let parsed = AutoBackupLogic.date(fromFileName: name)
        XCTAssertEqual(parsed.map { cal.startOfDay(for: $0) }, cal.startOfDay(for: day(2026, 9, 30)))
        XCTAssertNil(AutoBackupLogic.date(fromFileName: "notes.json"))
        XCTAssertNil(AutoBackupLogic.date(fromFileName: "CPAManager-backup-garbage.json"))
    }

    func testDueWhenNeverOrAboutADayAgo() {
        let now = day(2026, 9, 30)
        XCTAssertTrue(AutoBackupLogic.isDue(lastBackup: nil, now: now))
        XCTAssertFalse(AutoBackupLogic.isDue(lastBackup: now.addingTimeInterval(-3 * 3600), now: now))
        XCTAssertTrue(AutoBackupLogic.isDue(lastBackup: now.addingTimeInterval(-21 * 3600), now: now))
    }

    func testKeepsTheNewestAndIgnoresStrangers() {
        let names = (1...5).map { AutoBackupLogic.fileName(for: day(2026, 9, $0)) } + ["photo.jpg", "backup.json"]
        let doomed = AutoBackupLogic.filesToDelete(names, keep: 2)
        XCTAssertEqual(Set(doomed), Set((1...3).map { AutoBackupLogic.fileName(for: day(2026, 9, $0)) }))
        XCTAssertTrue(AutoBackupLogic.filesToDelete(names, keep: 10).isEmpty)
    }
}

@MainActor
final class AutoBackupServiceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("backups-\(UUID().uuidString)", isDirectory: true)
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    func testRunsOncePerDayAndCanBeTurnedOff() throws {
        let context = try makeContext()
        context.insert(Client(name: "Dana"))
        let dir = tempDir(), prefs = defaults()
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = AutoBackupService.runIfDue(context: context, now: day(2026, 9, 30), defaults: prefs, directory: dir)
        XCTAssertNotNil(first)
        XCTAssertNil(AutoBackupService.runIfDue(context: context, now: day(2026, 9, 30, hour: 15), defaults: prefs, directory: dir), "not due again the same day")
        XCTAssertNotNil(AutoBackupService.runIfDue(context: context, now: day(2026, 10, 1), defaults: prefs, directory: dir))
        XCTAssertEqual(AutoBackupService.list(directory: dir).count, 2)

        prefs.set(false, forKey: SettingsKeys.autoBackupEnabled)
        XCTAssertNil(AutoBackupService.runIfDue(context: context, now: day(2026, 10, 5), defaults: prefs, directory: dir))
    }

    func testOldBackupsArePrunedAndARestoreBringsDataBack() throws {
        let context = try makeContext()
        let client = Client(name: "Dana")
        context.insert(client)
        let dir = tempDir(), prefs = defaults()
        defer { try? FileManager.default.removeItem(at: dir) }
        for dayNumber in 1...9 {
            try AutoBackupService.backupNow(context: context, now: day(2026, 9, dayNumber), defaults: prefs, directory: dir)
        }
        let kept = AutoBackupService.list(directory: dir)
        XCTAssertEqual(kept.count, AutoBackupLogic.keep)
        XCTAssertEqual(kept.first?.date, cal.startOfDay(for: day(2026, 9, 9)))

        context.delete(client)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 0)
        let result = try AutoBackupService.restore(try XCTUnwrap(kept.first).url, into: context)
        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Client>()).first?.name, "Dana")
    }
}

@MainActor
final class ClientMergeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(schema: Persistence.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: Persistence.schema, configurations: config).mainContext
    }

    func testMergeMovesEverythingAndFillsBlanks() throws {
        let context = try makeContext()
        let keeper = Client(name: "Dana Lee", email: "")
        keeper.tags = ["referral"]
        keeper.notes = "Keeper note"
        let twin = Client(name: "Dana Lee", email: "dana@x.com", phone: "555-0100")
        twin.tags = ["vip", "referral"]
        twin.notes = "Twin note"
        twin.extensionYears = [2025]
        context.insert(keeper); context.insert(twin)

        let project = Project(title: "2025 return", client: twin)
        context.insert(project)
        let invoice = Invoice(number: 1001, client: twin)
        context.insert(invoice)
        context.insert(Interaction(kind: .call, summary: "Hello", client: twin))
        let expense = Expense()
        expense.client = twin
        context.insert(expense)
        context.insert(Document(filename: "W-2", data: Data([1, 2, 3]), client: twin))
        try context.save()

        ClientMergeService.merge([twin], into: keeper, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        XCTAssertEqual(project.client?.id, keeper.id)
        XCTAssertEqual(invoice.client?.id, keeper.id)
        XCTAssertEqual(expense.client?.id, keeper.id)
        XCTAssertEqual(keeper.interactionList.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Project>()), 1, "the job survives the twin's deletion")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Document>()), 1)
        XCTAssertEqual(keeper.email, "dana@x.com")
        XCTAssertEqual(keeper.phone, "555-0100")
        XCTAssertEqual(keeper.tags, ["referral", "vip"])
        XCTAssertTrue(keeper.notes.contains("Keeper note") && keeper.notes.contains("Twin note"))
        XCTAssertTrue(keeper.extensionYears.contains(2025))
    }

    func testMergeUndoRestoresTheTwin() throws {
        let context = try makeContext()
        let keeper = Client(name: "Pat"), twin = Client(name: "Pat")
        context.insert(keeper); context.insert(twin)
        let project = Project(title: "Job", client: twin)
        context.insert(project)
        try context.save()

        let toast = context.performUndoable("Merged", overwrite: true) {
            ClientMergeService.merge([twin], into: keeper, context: context)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 1)
        toast.undo?()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Client>()), 2)
        let restoredProject = try XCTUnwrap(try context.fetch(FetchDescriptor<Project>()).first)
        XCTAssertEqual(restoredProject.client?.id, twin.id, "the job goes back to its original client")
    }
}
