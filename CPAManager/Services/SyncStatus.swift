import Foundation
import CoreData
import CloudKit
import SwiftData
import Observation

/// Diagnostic view of whether iCloud sync is actually active. The SwiftData
/// `ModelContainer` falls back to a local-only store if CloudKit setup fails, which
/// otherwise happens silently — this makes that visible in Settings so "isn't
/// syncing" can be diagnosed instead of guessed at.
@Observable
final class SyncStatus {
    static let containerIdentifier = "iCloud.com.gottfriedcpa.ProjectManager"

    /// Set once, from `CPAManagerApp.init()`, to whatever actually happened when
    /// creating the ModelContainer.
    private(set) var isCloudKitActive = false
    private(set) var containerError: String?

    /// Populated asynchronously — whether this device's iCloud account can even
    /// use the app's container (separate from whether SwiftData's own CloudKit
    /// mirroring succeeded).
    private(set) var accountStatusDescription = "Checking…"

    /// Real export/import activity, from `NSPersistentCloudKitContainer`'s own event
    /// notifications — SwiftData doesn't expose a "sync now" API (CloudKit mirroring
    /// is opportunistic/automatic by design, not something apps can force to run
    /// instantly), so this is the honest substitute: nudge a save, then show what
    /// actually happened rather than pretending we triggered an immediate sync.
    private(set) var isSyncing = false
    private(set) var lastExportDate: Date?
    private(set) var lastExportError: String?
    private(set) var lastImportDate: Date?
    private(set) var lastImportError: String?

    private var eventObserver: NSObjectProtocol?

    func recordContainerResult(isCloudKitActive: Bool, error: Error?) {
        self.isCloudKitActive = isCloudKitActive
        self.containerError = error.map(Self.fullDescription)
    }

    /// Start listening for CloudKit mirroring activity. Safe to call once; the
    /// notification is posted by the underlying `NSPersistentCloudKitContainer`
    /// regardless of whether it's wrapped by SwiftData.
    func startObservingCloudKitEvents() {
        guard eventObserver == nil else { return }
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }
            self?.handle(event)
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else {
            isSyncing = true
            return
        }
        isSyncing = false
        switch event.type {
        case .export:
            lastExportDate = event.endDate
            lastExportError = event.error.map(Self.fullDescription)
        case .import:
            lastImportDate = event.endDate
            lastImportError = event.error.map(Self.fullDescription)
        case .setup:
            break
        @unknown default:
            break
        }
    }

    /// Best-effort nudge: flushes any pending local changes (which schedules an
    /// export) and re-checks account status. There's no public API to force
    /// CloudKit's import/export cycle to run immediately — this just makes sure
    /// nothing is sitting unsaved, then the event observer above reports whatever
    /// actually happens next.
    func syncNow(context: ModelContext) {
        isSyncing = true
        try? context.save()
        refreshAccountStatus()
    }

    /// SwiftData/CloudKit errors are often generic at the top level (e.g.
    /// "SwiftDataError error 1") with the actually-useful explanation buried in
    /// the underlying-error chain or a debug-description key. Walk both so the
    /// Settings screen shows something a person can act on.
    private static func fullDescription(for error: Error) -> String {
        var lines: [String] = []
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 6 {
            let nsError = err as NSError
            lines.append("[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)")
            if let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String,
               !debugDescription.isEmpty {
                lines.append("Detail: \(debugDescription)")
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return lines.joined(separator: "\n")
    }

    func refreshAccountStatus() {
        CKContainer(identifier: Self.containerIdentifier).accountStatus { [weak self] status, error in
            let description = Self.describe(status: status, error: error)
            Task { @MainActor in
                self?.accountStatusDescription = description
            }
        }
    }

    private static func describe(status: CKAccountStatus, error: Error?) -> String {
        if let error {
            return "Error checking iCloud account: \(error.localizedDescription)"
        }
        switch status {
        case .available:         return "Available"
        case .noAccount:         return "No iCloud account signed in on this device"
        case .restricted:        return "Restricted (parental controls or MDM policy)"
        case .couldNotDetermine: return "Could not determine iCloud account status"
        case .temporarilyUnavailable: return "Temporarily unavailable"
        @unknown default:        return "Unknown"
        }
    }
}
