import Foundation

// Pure rules for the Sync Health screen: turns the engine's counters into a plain-English
// verdict. No SwiftData, no Firebase.

struct SyncHealthInput: Equatable {
    var isSignedIn: Bool
    var phase: SyncEngine.Phase
    var pendingUploads: Int
    /// Records waiting for a related record to arrive first.
    var deferredCount: Int
    /// Records missing here that the engine won't delete everywhere without your say-so.
    var blockedDeletions: Int
    /// Attached files too big to travel inside a record.
    var oversizedFiles: Int
    var lastPush: Date?
    var lastPull: Date?
}

struct SyncHealthReport: Equatable {
    enum Level: Equatable { case good, watch, problem }

    var level: Level
    var headline: String
    var issues: [String]
}

enum SyncHealth {
    /// A push that hasn't gone through for this long, with changes waiting, is worth a mention.
    static let stalePushMinutes = 10
    /// Not having heard from the cloud for this long is worth a mention.
    static let staleDays = 2

    static func assess(_ input: SyncHealthInput, now: Date = .now) -> SyncHealthReport {
        guard input.isSignedIn else {
            return SyncHealthReport(level: .watch, headline: "Not signed in",
                                    issues: ["Your data is only on this device. Sign in under Settings ▸ Cloud Sync to keep your devices in step."])
        }

        var problems: [String] = []
        var watches: [String] = []

        switch input.phase {
        case .error(let text):
            problems.append(text)
        case .attention(let text):
            watches.append(text)
        default:
            break
        }
        if input.blockedDeletions > 0 && !watches.contains(where: { $0.contains("missing from this device") }) {
            watches.append("\(input.blockedDeletions) record\(input.blockedDeletions == 1 ? " is" : "s are") missing from this device and are being held back from deleting everywhere.")
        }
        if input.pendingUploads > 0 {
            let stale = input.lastPush.map { now.timeIntervalSince($0) > Double(stalePushMinutes * 60) } ?? true
            if stale && input.phase != .syncing {
                watches.append("\(input.pendingUploads) change\(input.pendingUploads == 1 ? " hasn't" : "s haven't") uploaded yet. They'll go up when the connection allows.")
            }
        }
        if input.deferredCount > 0 {
            watches.append("\(input.deferredCount) record\(input.deferredCount == 1 ? " is" : "s are") waiting for a related record to arrive.")
        }
        if let pull = input.lastPull, now.timeIntervalSince(pull) > Double(staleDays * 86_400) {
            let days = Int(now.timeIntervalSince(pull) / 86_400)
            watches.append("Nothing received from the cloud in \(days) days. Open the app on another device or tap Sync Now.")
        }
        if input.oversizedFiles > 0 {
            watches.append("\(input.oversizedFiles) attached file\(input.oversizedFiles == 1 ? " is" : "s are") too large to sync (over about 0.8 MB). Keep big files in Google Drive and link them instead.")
        }

        if !problems.isEmpty {
            return SyncHealthReport(level: .problem, headline: "Sync problem", issues: problems + watches)
        }
        if !watches.isEmpty {
            return SyncHealthReport(level: .watch, headline: "Needs a look", issues: watches)
        }
        switch input.phase {
        case .stopped, .connecting:
            return SyncHealthReport(level: .watch, headline: "Connecting…", issues: [])
        case .syncing:
            return SyncHealthReport(level: .good, headline: "Syncing…", issues: [])
        default:
            return SyncHealthReport(level: .good, headline: "Everything is in sync", issues: [])
        }
    }
}
