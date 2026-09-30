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
    @State private var timer: TimerController
    @State private var qboAuth = QBOAuthService()
    @State private var googleAuth = GoogleAuthService()
    @State private var cloud: CloudSync

    init() {
        // Shared with App Intents — see Persistence.swift.
        let boot = Persistence.shared
        container = boot.container
        _cloud = State(initialValue: CloudSync(context: boot.container.mainContext))
        let timerController = TimerController()
        _timer = State(initialValue: timerController)
        // Must be in place before launch finishes so background notification actions arrive.
        NotificationActionHandler.shared.install()
        #if os(iOS) && !targetEnvironment(macCatalyst)
        WatchBridge.shared.start(timer: timerController)
        #endif
        #if os(macOS)
        MacQuickCapture.installHotKey()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            // One AppRouter per window (see WindowRoot), so windows navigate independently.
            WindowRoot()
                .environment(timer)
                .environment(qboAuth)
                .environment(googleAuth)
                .environment(cloud)
                .tint(Theme.brand)
                .task {
                    cloud.start()
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
        .commands { AppCommands() }

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
                .appChrome()
                .frame(minWidth: 560, idealWidth: 620, minHeight: 620, idealHeight: 760)
                .modelContainer(container)
                .environment(cloud)
                .environment(qboAuth)
                .environment(googleAuth)
        }
        #endif
    }
}
