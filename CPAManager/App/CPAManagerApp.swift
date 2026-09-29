import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@main
struct CPAManagerApp: App {
    let container: ModelContainer
    @State private var timer = TimerController()
    @State private var qboAuth = QBOAuthService()
    @State private var googleAuth = GoogleAuthService()
    @State private var syncStatus: SyncStatus
    @State private var router = AppRouter()

    init() {
        // Shared with App Intents — see Persistence.swift.
        let boot = Persistence.shared
        container = boot.container
        _syncStatus = State(initialValue: boot.syncStatus)
        #if os(macOS)
        MacQuickCapture.installHotKey()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(timer)
                .environment(qboAuth)
                .environment(googleAuth)
                .environment(syncStatus)
                .environment(router)
                .tint(Theme.brand)
                .task {
                    syncStatus.refreshAccountStatus()
                    syncStatus.startObservingCloudKitEvents()
                    // Lets CloudKit's remote-change notifications reach this
                    // device in the background rather than only on next launch.
                    #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                    #else
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1120, height: 740)
        #endif
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
                Button("Leads") { router.go(to: .leads) }.keyboardShortcut("7", modifiers: .command)
            }
        }

        #if os(macOS)
        // Menu bar quick capture (also reachable anywhere with ⌃⌥Space).
        MenuBarExtra("Quick Capture", systemImage: "tray.and.arrow.down.fill") {
            QuickCaptureView()
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)

        // ⌘, opens Settings.
        Settings {
            NavigationStack { SettingsView() }
                .frame(minWidth: 520, minHeight: 620)
                .modelContainer(container)
                .environment(syncStatus)
                .environment(qboAuth)
                .environment(googleAuth)
        }
        #endif
    }
}
