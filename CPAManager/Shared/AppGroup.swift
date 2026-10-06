import Foundation

/// Identifiers shared between the app and the widget extension.
///
/// IMPORTANT: the App Group below must match the "App Groups" capability on BOTH
/// the CPAManager and CPAWidgets targets, and the entitlements files. If you change
/// the bundle prefix, update it here too.
enum AppGroup {
    #if os(macOS)
    /// macOS group IDs start with the Team ID (`$(TeamIdentifierPrefix)` in the entitlements) —
    /// that form needs no extra approval prompt. Must match CPAManagerMac.entitlements and
    /// CPAWidgetsMac.entitlements. (The Team ID is in project.yml; it is not a secret.)
    static let identifier = "X796Z5UW4P.group.com.gottfriedcpa.ProjectManager"
    #else
    static let identifier = "group.com.gottfriedcpa.ProjectManager"
    #endif
    static let snapshotKey = "dashboardSnapshot"

    /// Shared between the app and its widgets on every platform (the Mac app now has a widget
    /// extension too, so it uses the group container like iOS does).
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
