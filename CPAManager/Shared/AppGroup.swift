import Foundation

/// Identifiers shared between the app and the widget extension.
///
/// IMPORTANT: the App Group below must match the "App Groups" capability on BOTH
/// the CPAManager and CPAWidgets targets, and the entitlements files. If you change
/// the bundle prefix, update it here too.
enum AppGroup {
    static let identifier = "group.com.gottfriedcpa.ProjectManager"
    static let snapshotKey = "dashboardSnapshot"

    static var sharedDefaults: UserDefaults? {
        #if os(macOS)
        // No widget or share extension on the Mac app, so there's nothing to share with —
        // and touching a group container without the entitlement makes macOS prompt.
        return UserDefaults.standard
        #else
        return UserDefaults(suiteName: identifier)
        #endif
    }
}
