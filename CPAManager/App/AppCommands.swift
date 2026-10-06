import SwiftUI

/// Menu-bar / hardware-keyboard commands. They act on the focused window's router.
struct AppCommands: Commands {
    @FocusedValue(\.appRouter) private var router
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Keyboard shortcuts (⌘N etc.). They show in the Mac menu bar and in the
        // iPad hardware-keyboard shortcut overlay.
        CommandGroup(replacing: .newItem) {
            Button("New Task") { router?.go(to: .today, focus: .newTask) }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(router == nil)
            Button("New Tax Return") { router?.creating = .taxReturn }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(router == nil)
            Button("New Client") { router?.creating = .client }
                .disabled(router == nil)
            Button("Capture to Inbox") { router?.go(to: .inbox, focus: .inboxCapture) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(router == nil)
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .toolbar) {
            Button("Sync Now") { router?.refreshTick += 1 }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(router == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search…") { router?.showingQuickOpen = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(router == nil)
        }
        CommandMenu("Go") {
            Button("Today") { router?.go(to: .today) }.keyboardShortcut("1", modifiers: .command)
            Button("Inbox") { router?.go(to: .inbox) }.keyboardShortcut("2", modifiers: .command)
            Button("Clients") { router?.go(to: .clients) }.keyboardShortcut("3", modifiers: .command)
            Button("Work") { router?.go(to: .work) }.keyboardShortcut("4", modifiers: .command)
            Button("Deadlines") { router?.go(to: .deadlines) }.keyboardShortcut("5", modifiers: .command)
            Button("Weekly Review") { router?.go(to: .review) }.keyboardShortcut("6", modifiers: .command)
            Button("Leads") { router?.go(to: .leads) }.keyboardShortcut("7", modifiers: .command)
        }
    }
}
