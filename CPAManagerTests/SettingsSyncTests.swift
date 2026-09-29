import XCTest
@testable import CPAManager

final class SettingsSyncTests: XCTestCase {
    private let keys = ["a", "b", "c", "d"]

    func testRemoteWinsWhenItDiffers() {
        let plan = SettingsSyncPlanner.reconcile(local: ["a": 1, "b": "old"], remote: ["a": 2, "b": "new"], keys: keys)
        XCTAssertEqual(plan.applyLocally["a"] as? Int, 2)
        XCTAssertEqual(plan.applyLocally["b"] as? String, "new")
        XCTAssertTrue(plan.upload.isEmpty)
    }

    func testLocalSeedsICloudWhenRemoteIsEmpty() {
        let plan = SettingsSyncPlanner.reconcile(local: ["a": 150.0, "b": true], remote: [:], keys: keys)
        XCTAssertEqual(plan.upload["a"] as? Double, 150.0)
        XCTAssertEqual(plan.upload["b"] as? Bool, true)
        XCTAssertTrue(plan.applyLocally.isEmpty)
    }

    func testEqualValuesAreLeftAlone() {
        let plan = SettingsSyncPlanner.reconcile(local: ["a": 8, "b": "x"], remote: ["a": 8, "b": "x"], keys: keys)
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertTrue(plan.upload.isEmpty)
    }

    func testUnlistedKeysAreIgnored() {
        let plan = SettingsSyncPlanner.reconcile(local: ["zzz": 1], remote: ["yyy": 2], keys: keys)
        XCTAssertTrue(plan.applyLocally.isEmpty)
        XCTAssertTrue(plan.upload.isEmpty)
    }

    func testNumbersCompareByValueAcrossTypes() {
        XCTAssertTrue(SettingsSyncPlanner.isEqual(true, 1))
        XCTAssertTrue(SettingsSyncPlanner.isEqual(8, 8.0))
        XCTAssertFalse(SettingsSyncPlanner.isEqual(8, 9))
        XCTAssertFalse(SettingsSyncPlanner.isEqual("8", 8))
        XCTAssertTrue(SettingsSyncPlanner.isEqual(nil, nil))
        XCTAssertFalse(SettingsSyncPlanner.isEqual(nil, 1))
    }

    func testSyncedKeysCoverSettingsButNotPerDeviceState() {
        XCTAssertTrue(SettingsKeys.synced.contains(SettingsKeys.reminderHour))
        XCTAssertTrue(SettingsKeys.synced.contains(SettingsKeys.googleSyncedEvents))
        XCTAssertFalse(SettingsKeys.synced.contains(SettingsKeys.googleLastGmailSync))
        XCTAssertFalse(SettingsKeys.synced.contains("workShowsBoard"))
        XCTAssertEqual(Set(SettingsKeys.synced).count, SettingsKeys.synced.count, "no duplicate keys")
    }
}
