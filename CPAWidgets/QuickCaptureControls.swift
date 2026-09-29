// Control Center / lock screen / Action button controls. These need the iOS 18 SDK
// (Xcode 16+); on older toolchains the file compiles to nothing.
#if compiler(>=6.0)
import AppIntents
import SwiftUI
import WidgetKit

/// Opens the app straight to the "add a task" field. The control runs in the widget
/// extension, so it leaves a note in the shared App Group; the app reads it as it
/// launches (see `RootView.applyHandoffs`).
@available(iOS 18.0, *)
struct OpenQuickTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Task"
    static var description = IntentDescription("Opens CPA Manager ready to type a task.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingCaptures.requestOpen("task")
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenInboxCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture to Inbox"
    static var description = IntentDescription("Opens CPA Manager ready to capture a thought.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingCaptures.requestOpen("inbox")
        return .result()
    }
}

@available(iOS 18.0, *)
struct QuickTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickTaskControl") {
            ControlWidgetButton(action: OpenQuickTaskIntent()) {
                Label("Add Task", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add Task")
        .description("Jump straight into adding a task.")
    }
}

@available(iOS 18.0, *)
struct InboxCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "InboxCaptureControl") {
            ControlWidgetButton(action: OpenInboxCaptureIntent()) {
                Label("Capture", systemImage: "tray.and.arrow.down.fill")
            }
        }
        .displayName("Capture to Inbox")
        .description("Jump straight into capturing a thought.")
    }
}
#endif
