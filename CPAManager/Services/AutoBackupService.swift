import Foundation
import SwiftData

struct AutoBackupInfo: Identifiable, Equatable {
    var url: URL
    var date: Date
    var bytes: Int
    var id: URL { url }
}

/// Writes a full backup once a day to this device's private storage and keeps the last few.
/// Backups are per-device (they aren't synced): they're the safety net if a sync ever goes
/// wrong. Restore is a merge — it adds what's missing and never deletes anything.
@MainActor
enum AutoBackupService {
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CPAManager", isDirectory: true).appendingPathComponent("Backups", isDirectory: true)
    }

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.autoBackupEnabled) as? Bool ?? true
    }

    static func lastBackup(defaults: UserDefaults = .standard) -> Date? {
        let stamp = defaults.double(forKey: SettingsKeys.lastAutoBackup)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Makes today's backup if backups are on and one is due. Cheap to call often.
    @discardableResult
    static func runIfDue(context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard,
                         directory: URL = AutoBackupService.directory) -> URL? {
        guard isEnabled(defaults: defaults),
              AutoBackupLogic.isDue(lastBackup: lastBackup(defaults: defaults), now: now) else { return nil }
        return try? backupNow(context: context, now: now, defaults: defaults, directory: directory)
    }

    @discardableResult
    static func backupNow(context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard,
                          directory: URL = AutoBackupService.directory) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try BackupService.exportData(context: context, includeFiles: true)
        let url = directory.appendingPathComponent(AutoBackupLogic.fileName(for: now))
        try data.write(to: url, options: .atomic)
        defaults.set(now.timeIntervalSince1970, forKey: SettingsKeys.lastAutoBackup)

        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        for stale in AutoBackupLogic.filesToDelete(names) {
            try? fm.removeItem(at: directory.appendingPathComponent(stale))
        }
        return url
    }

    static func list(directory: URL = AutoBackupService.directory) -> [AutoBackupInfo] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            guard let date = AutoBackupLogic.date(fromFileName: name) else { return nil }
            let url = directory.appendingPathComponent(name)
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return AutoBackupInfo(url: url, date: date, bytes: size)
        }
        .sorted { $0.date > $1.date }
    }

    static func restore(_ url: URL, into context: ModelContext) throws -> BackupService.RestoreResult {
        let file = try BackupService.decode(Data(contentsOf: url))
        return BackupService.restore(file, into: context)
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
