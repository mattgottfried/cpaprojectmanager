import Foundation
import UserNotifications
import SwiftData

/// What a notification button (or tapping the notification) should do.
enum NotificationCommand: Equatable {
    case completeTask(UUID)
    case snoozeTask(UUID)
    case markContacted(UUID)
    case remindClientNextWeek(UUID)
    case markInvoicePaid(UUID)
    case open(DeepLink)
}

/// Pure mapping between notification request IDs ("task-<uuid>", "followup-<uuid>",
/// "invoice-<uuid>", "project-<uuid>"), action IDs, and commands. Unit-tested.
enum NotificationActionParser {
    static let taskCategory = "CPA_TASK"
    static let followUpCategory = "CPA_FOLLOWUP"
    static let invoiceCategory = "CPA_INVOICE"

    static let doneAction = "CPA_DONE"
    static let snoozeAction = "CPA_SNOOZE"
    static let contactedAction = "CPA_CONTACTED"
    static let nextWeekAction = "CPA_NEXT_WEEK"
    static let paidAction = "CPA_PAID"

    private static func split(_ requestID: String) -> (prefix: String, id: UUID)? {
        guard let dash = requestID.firstIndex(of: "-") else { return nil }
        let prefix = String(requestID[..<dash])
        guard let id = UUID(uuidString: String(requestID[requestID.index(after: dash)...])) else { return nil }
        return (prefix, id)
    }

    static func category(forRequestID requestID: String) -> String? {
        switch split(requestID)?.prefix {
        case "task":     return taskCategory
        case "followup": return followUpCategory
        case "invoice":  return invoiceCategory
        default:         return nil
        }
    }

    static func command(
        requestID: String,
        actionID: String,
        defaultActionID: String = UNNotificationDefaultActionIdentifier
    ) -> NotificationCommand? {
        guard let parts = split(requestID) else { return nil }
        let id = parts.id

        if actionID == defaultActionID {
            switch parts.prefix {
            case "task":     return .open(.task(id))
            case "project":  return .open(.project(id))
            case "followup", "birthday", "anniversary": return .open(.client(id))
            case "invoice":  return .open(.invoice(id))
            default:         return nil
            }
        }

        switch (parts.prefix, actionID) {
        case ("task", doneAction):         return .completeTask(id)
        case ("task", snoozeAction):       return .snoozeTask(id)
        case ("followup", contactedAction): return .markContacted(id)
        case ("followup", nextWeekAction): return .remindClientNextWeek(id)
        case ("invoice", paidAction):      return .markInvoicePaid(id)
        default:                           return nil
        }
    }
}

/// Registers the action buttons and applies them when tapped — including while the app
/// is closed, since the system launches it in the background to run the action.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationActionHandler()
    static let openRequested = Notification.Name("CPAOpenRequested")

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        func action(_ id: String, _ title: String, _ symbol: String, destructive: Bool = false) -> UNNotificationAction {
            let action = UNNotificationAction(identifier: id, title: title, options: destructive ? [.destructive] : [])
            return action
        }

        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: NotificationActionParser.taskCategory,
                actions: [
                    action(NotificationActionParser.doneAction, "Done", "checkmark"),
                    action(NotificationActionParser.snoozeAction, "Tomorrow", "sunrise"),
                ],
                intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationActionParser.followUpCategory,
                actions: [
                    action(NotificationActionParser.contactedAction, "Contacted", "checkmark"),
                    action(NotificationActionParser.nextWeekAction, "Next week", "calendar"),
                ],
                intentIdentifiers: [], options: []
            ),
            UNNotificationCategory(
                identifier: NotificationActionParser.invoiceCategory,
                actions: [action(NotificationActionParser.paidAction, "Mark paid", "banknote")],
                intentIdentifiers: [], options: []
            ),
        ])
    }

    // Show reminders as banners even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let command = NotificationActionParser.command(
            requestID: response.notification.request.identifier,
            actionID: response.actionIdentifier
        ) else { return }
        await MainActor.run { Self.apply(command) }
    }

    @MainActor
    static func apply(_ command: NotificationCommand) {
        if case .open(let link) = command {
            // The app may still be launching — leave a note it will pick up, and nudge
            // it if it's already running.
            PendingCaptures.requestOpen(link.identifier)
            NotificationCenter.default.post(name: openRequested, object: nil)
            return
        }

        let context = Persistence.shared.container.mainContext
        switch command {
        case .completeTask(let id):
            if let task = task(id, context) { TaskCompletion.complete(task, context: context) }
        case .snoozeTask(let id):
            if let task = task(id, context) {
                task.snoozedUntil = TodayPlanner.snoozeDate(.tomorrow)
            }
        case .markContacted(let id):
            if let client = client(id, context) {
                context.insert(Interaction(kind: .note, summary: "Followed up", client: client))
                client.followUpDate = nil
            }
        case .remindClientNextWeek(let id):
            if let client = client(id, context) { client.followUpDate = FollowUpPreset.inAWeek.date() }
        case .markInvoicePaid(let id):
            if let invoice = invoice(id, context), invoice.balance > 0 {
                invoice.recordPayment(invoice.balance, method: .other, note: "Marked paid from a reminder")
            }
        case .open:
            break
        }
        try? context.save()
        let hour = UserDefaults.standard.object(forKey: SettingsKeys.reminderHour) as? Int ?? 8
        NotificationScheduler.rescheduleAll(context: context, morningHour: hour)
        SnapshotBuilder.rebuild(context: context)
    }

    @MainActor
    private static func task(_ id: UUID, _ context: ModelContext) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.id == id })).first
    }

    @MainActor
    private static func client(_ id: UUID, _ context: ModelContext) -> Client? {
        try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.id == id })).first
    }

    @MainActor
    private static func invoice(_ id: UUID, _ context: ModelContext) -> Invoice? {
        try? context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate<Invoice> { $0.id == id })).first
    }
}
