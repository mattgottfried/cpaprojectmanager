import Foundation
import CloudKit
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

    func recordContainerResult(isCloudKitActive: Bool, error: Error?) {
        self.isCloudKitActive = isCloudKitActive
        self.containerError = error?.localizedDescription
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
