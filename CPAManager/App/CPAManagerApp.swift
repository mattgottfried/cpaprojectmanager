import SwiftUI
import SwiftData
import UIKit

@main
struct CPAManagerApp: App {
    let container: ModelContainer
    @State private var timer = TimerController()
    @State private var qboAuth = QBOAuthService()
    @State private var syncStatus: SyncStatus
    @State private var router = AppRouter()

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
                .environment(router)
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
        .commands {
            // Keyboard shortcuts (⌘N etc.). They show in the Mac menu bar and in the
            // iPad hardware-keyboard shortcut overlay.
            CommandGroup(replacing: .newItem) {
                Button("New Task") { router.go(to: .today, focus: .newTask) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Capture to Inbox") { router.go(to: .inbox, focus: .inboxCapture) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Today") { router.go(to: .today) }.keyboardShortcut("1", modifiers: .command)
                Button("Inbox") { router.go(to: .inbox) }.keyboardShortcut("2", modifiers: .command)
                Button("Clients") { router.go(to: .clients) }.keyboardShortcut("3", modifiers: .command)
                Button("Work") { router.go(to: .work) }.keyboardShortcut("4", modifiers: .command)
                Button("Deadlines") { router.go(to: .deadlines) }.keyboardShortcut("5", modifiers: .command)
                Button("Weekly Review") { router.go(to: .review) }.keyboardShortcut("6", modifiers: .command)
            }
        }
    }
}
