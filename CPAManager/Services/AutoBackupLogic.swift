import Foundation

// Pure rules for the automatic nightly backups: when one is due, what the files are called,
// and which old ones to drop. No file access here. Unit-tested.

enum AutoBackupLogic {
    static let prefix = "CPAManager-backup-"
    static let suffix = ".json"
    /// How many daily backups to keep.
    static let keep = 7

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// One file per day: "CPAManager-backup-2026-09-30.json".
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        prefix + formatter(calendar).string(from: date) + suffix
    }

    static func date(fromFileName name: String, calendar: Calendar = .current) -> Date? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let stamp = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return formatter(calendar).date(from: stamp)
    }

    /// Due when there's never been one, or the last was more than `hours` ago (a little under
    /// a day, so a daily launch always gets one).
    static func isDue(lastBackup: Date?, now: Date = .now, hours: Double = 20) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= hours * 3600
    }

    /// Backup files beyond the newest `keep`. Anything that isn't one of ours is left alone.
    static func filesToDelete(_ names: [String], keep: Int = AutoBackupLogic.keep, calendar: Calendar = .current) -> [String] {
        let dated = names.compactMap { name in date(fromFileName: name, calendar: calendar).map { (name, $0) } }
        let newestFirst = dated.sorted { $0.1 > $1.1 }
        return newestFirst.dropFirst(max(0, keep)).map(\.0)
    }
}
