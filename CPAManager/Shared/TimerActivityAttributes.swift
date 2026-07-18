import Foundation

// Live Activities have no Mac Catalyst equivalent — ActivityKit is importable
// there, but ActivityAttributes conformance is explicitly unavailable, so guard
// on targetEnvironment too, not just canImport.
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// Describes the billable-hours Live Activity shown on the lock screen and in the
/// Dynamic Island. Shared between the app (which starts/updates it) and the widget
/// extension (which renders it).
struct TimerActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the running timer began — the UI derives elapsed time from this.
        var startedAt: Date
        var isBillable: Bool
    }

    var clientName: String
    var projectTitle: String
}
#endif
