import AppIntents
import SwiftData
import Foundation

/// Where a Shortcut says the captured text came from.
enum CaptureSourceOption: String, AppEnum {
    case text, email, note, siri

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Source"
    static var caseDisplayRepresentations: [CaptureSourceOption: DisplayRepresentation] = [
        .text:  "Text message",
        .email: "Email",
        .note:  "Note",
        .siri:  "Siri",
    ]

    var inboxSource: InboxSource {
        switch self {
        case .text:  return .text
        case .email: return .email
        case .note:  return .note
        case .siri:  return .siri
        }
    }
}

/// The capture hook for everything iOS won't let an app read on its own. Wire it up
/// from Shortcuts:
///  - **Texts in a Note:** Find Notes → Get Text from Note → Add to Inbox
///    (Source: Note). Duplicates are skipped, so it is safe to run daily.
///  - **Email:** a share-sheet Shortcut that passes the message body to Add to Inbox
///    (Source: Email).
struct AddToInboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Inbox"
    static var description = IntentDescription(
        "Capture text from a note, email, or message into your CPA Manager inbox. Each line becomes an item; lines already captured are skipped.",
        categoryName: "Capture"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Source", default: .note)
    var source: CaptureSourceOption

    @Parameter(title: "One item per line", default: true)
    var splitLines: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Inbox from \(\.$source)") {
            \.$splitLines
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let result = InboxService.capture(
            text: text,
            source: source.inboxSource,
            context: context,
            splitLines: splitLines
        )
        let dialog: String
        switch result.added {
        case 0 where result.skippedDuplicates > 0:
            dialog = "Nothing new — already in your inbox."
        case 0:
            dialog = "Nothing to add."
        case 1:
            dialog = "Added 1 item to your inbox."
        default:
            dialog = "Added \(result.added) items to your inbox."
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// "Hey Siri, add a task in CPA Manager" — creates a real task straight away, with
/// the due date parsed from the words ("call Smith tomorrow").
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription(
        "Add a task to CPA Manager. Dates like \"tomorrow\" or \"Friday\" at the end are picked up automatically.",
        categoryName: "Capture"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Task")
    var task: String

    @Parameter(title: "Due date")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add task \(\.$task)") {
            \.$dueDate
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let parsed = QuickAddParser.parse(task)
        let title = parsed.title.isEmpty ? task : parsed.title
        let due = dueDate.map { Calendar.current.startOfDay(for: $0) } ?? parsed.dueDate
        let item = TaskItem(title: title, dueDate: due, isNextAction: due == nil)
        context.insert(item)
        try? context.save()

        let hour = UserDefaults.standard.object(forKey: SettingsKeys.reminderHour) as? Int ?? 8
        NotificationScheduler.rescheduleAll(context: context, morningHour: hour)
        SnapshotBuilder.rebuild(context: context)

        if let due {
            return .result(dialog: IntentDialog(stringLiteral: "Added \(title), due \(Format.relativeDay(due))."))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Added \(title) to Next up."))
    }
}

struct CPAManagerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "New task in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CaptureThoughtIntent(),
            phrases: [
                "Capture a thought in \(.applicationName)",
                "Remember something in \(.applicationName)",
            ],
            shortTitle: "Capture a Thought",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: TodaySummaryIntent(),
            phrases: [
                "What's on my plate in \(.applicationName)",
                "What's due today in \(.applicationName)",
            ],
            shortTitle: "What's on My Plate",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: ClientStatusIntent(),
            phrases: [
                "What's up with \(\.$client) in \(.applicationName)",
                "Status of \(\.$client) in \(.applicationName)",
            ],
            shortTitle: "Client Status",
            systemImageName: "person.crop.circle.badge.questionmark"
        )
        AppShortcut(
            intent: OpenClientIntent(),
            phrases: ["Open \(\.$client) in \(.applicationName)"],
            shortTitle: "Open Client",
            systemImageName: "person.fill"
        )
        AppShortcut(
            intent: AddToInboxIntent(),
            phrases: [
                "Add to my inbox in \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "Add to Inbox",
            systemImageName: "tray.and.arrow.down"
        )
    }
}

/// Hands-free capture: "Hey Siri, capture a thought in CPA Manager", or bind it to
/// the Action button (Settings → Action Button → Shortcut). It asks "What's on your
/// mind?", then drops the answer in the Inbox to sort later — no unlocking, no app.
struct CaptureThoughtIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture a Thought"
    static var description = IntentDescription(
        "Say or type something and it goes straight to your CPA Manager inbox to sort out later.",
        categoryName: "Capture"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Thought", requestValueDialog: IntentDialog("What's on your mind?"))
    var thought: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$thought)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let result = InboxService.capture(text: thought, source: .siri, context: context, splitLines: false)
        SnapshotBuilder.rebuild(context: context)
        let dialog = result.added > 0 ? "Captured." : "Already in your inbox."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
