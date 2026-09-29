import SwiftUI
import SwiftData
import UIKit

@main
struct CPAManagerApp: App {
    let container: ModelContainer
    @State private var timer = TimerController()
    @State private var qboAuth = QBOAuthService()
    @State private var syncStatus: SyncStatus

    init() {
        // Shared with App Intents — see Persistence.swift.
        let boot = Persistence.shared
        container = boot.container
        _syncStatus = State(initialValue: boot.syncStatus)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(qboAuth)
                .environment(syncStatus)
                .tint(Theme.brand)
                .task {
                    syncStatus.refreshAccountStatus()
                    syncStatus.startObservingCloudKitEvents()
                    // Lets CloudKit's remote-change notifications reach this
                    // device in the background rather than only on next launch.
                    UIApplication.shared.registerForRemoteNotifications()
                }
        }
        .modelContainer(container)
    }
}
