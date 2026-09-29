import Foundation

extension SettingsKeys {
    /// Preferences that follow you across devices via iCloud key-value storage.
    /// Per-device UI state (which Work view, quick-capture mode) and caches (last
    /// Gmail sync time) are deliberately left out.
    static let synced: [String] = [
        defaultHourlyRate, reminderHour,
        firmName, firmTagline, firmContact,
        focusEnabled, focusStartHour, focusEndHour, focusWeekends,
        lastWeeklyReview, quietThresholdDays,
        googleGmailEnabled, googleGmailQuery, googleScheduleEnabled, googlePushEnabled,
        googleCalendarID,
        // Which calendar events this app has pushed — shared so any device can clean up
        // events another device created.
        googleSyncedEvents,
    ]
}

/// Pure merge rules for first launch / external changes. Unit-tested.
enum SettingsSyncPlanner {
    struct Plan {
        /// Values to write into this device's UserDefaults.
        var applyLocally: [String: Any] = [:]
        /// Values to upload to iCloud.
        var upload: [String: Any] = [:]
    }

    /// iCloud wins when it has a value (so a new device picks up your settings);
    /// otherwise this device's value seeds iCloud.
    static func reconcile(local: [String: Any], remote: [String: Any], keys: [String]) -> Plan {
        var plan = Plan()
        for key in keys {
            if let remoteValue = remote[key] {
                if !isEqual(local[key], remoteValue) { plan.applyLocally[key] = remoteValue }
            } else if let localValue = local[key] {
                plan.upload[key] = localValue
            }
        }
        return plan
    }

    /// Property-list equality (numbers compare by value, so `true == 1`).
    static func isEqual(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return (a as AnyObject).isEqual(b)
    }
}

/// Mirrors `SettingsKeys.synced` between `UserDefaults` (what `@AppStorage` reads) and
/// `NSUbiquitousKeyValueStore` (iCloud). Changes made here are uploaded; changes
/// arriving from another device are written into UserDefaults, so open screens
/// update on their own.
final class SettingsSync {
    static let shared = SettingsSync()

    /// Posted after iCloud values were applied to this device (e.g. so reminders can be re-timed).
    static let didApplyRemote = Notification.Name("SettingsSyncDidApplyRemote")

    /// False when the device isn't signed into iCloud.
    static var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private var started = false
    private var isApplyingRemote = false

    func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            self?.applyRemote(keys: changed)
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            self?.uploadChanges()
        }

        store.synchronize()
        reconcile()
    }

    private func localValues() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in SettingsKeys.synced {
            if let value = defaults.object(forKey: key) { values[key] = value }
        }
        return values
    }

    private func remoteValues() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in SettingsKeys.synced {
            if let value = store.object(forKey: key) { values[key] = value }
        }
        return values
    }

    private func reconcile() {
        let plan = SettingsSyncPlanner.reconcile(local: localValues(), remote: remoteValues(), keys: SettingsKeys.synced)
        write(plan.applyLocally)
        for (key, value) in plan.upload { store.set(value, forKey: key) }
        if !plan.upload.isEmpty { store.synchronize() }
    }

    private func applyRemote(keys: [String]) {
        var values: [String: Any] = [:]
        for key in keys where SettingsKeys.synced.contains(key) {
            if let value = store.object(forKey: key) { values[key] = value }
        }
        write(values.filter { !SettingsSyncPlanner.isEqual(defaults.object(forKey: $0.key), $0.value) })
    }

    private func write(_ values: [String: Any]) {
        guard !values.isEmpty else { return }
        isApplyingRemote = true
        for (key, value) in values { defaults.set(value, forKey: key) }
        isApplyingRemote = false
        NotificationCenter.default.post(name: Self.didApplyRemote, object: nil)
    }

    /// Cheap: compares ~17 values, and only touches iCloud when one actually differs.
    private func uploadChanges() {
        guard !isApplyingRemote else { return }
        var changed = false
        for key in SettingsKeys.synced {
            guard let value = defaults.object(forKey: key),
                  !SettingsSyncPlanner.isEqual(value, store.object(forKey: key)) else { continue }
            store.set(value, forKey: key)
            changed = true
        }
        if changed { store.synchronize() }
    }
}
