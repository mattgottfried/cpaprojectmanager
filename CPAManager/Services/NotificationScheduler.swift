import Foundation
import UserNotifications
import SwiftData

/// Schedules local reminders for upcoming project and task due dates. No server or
/// push certificate needed — everything fires on-device.
enum NotificationScheduler {

    /// iOS keeps at most 64 pending local notifications; we stay well under.
    private static let maxScheduled = 60

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static var isAuthorized: Bool {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }

    /// Rebuild all reminders from current data. Call after edits or on launch.
    static func rescheduleAll(context: ModelContext, morningHour: Int = 8, focus: FocusHours = .load()) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Gather everything with a future due date, soonest first.
        var candidates: [(id: String, title: String, body: String, due: Date)] = []

        if let projects = try? context.fetch(FetchDescriptor<Project>()) {
            for project in projects where !project.status.isComplete {
                guard let due = project.dueDate, due >= today else { continue }
                candidates.append((
                    id: "project-\(project.id.uuidString)",
                    title: "Due: \(project.title)",
                    body: project.clientName,
                    due: due
                ))
            }
        }

        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            for task in tasks where !task.isDone {
                guard let due = task.dueDate, due >= today else { continue }
                candidates.append((
                    id: "task-\(task.id.uuidString)",
                    title: task.title,
                    body: task.project?.title ?? "Task",
                    due: due
                ))
            }
        }

        if let clients = try? context.fetch(FetchDescriptor<Client>()) {
            for client in clients where client.status != .inactive {
                guard let due = client.followUpDate, due >= today else { continue }
                candidates.append((
                    id: "followup-\(client.id.uuidString)",
                    title: "Follow up: \(client.displayName)",
                    body: "Last contact: \(ClientActivity.lastContactLabel(client.lastContactedAt))",
                    due: due
                ))
            }
        }

        if let invoices = try? context.fetch(FetchDescriptor<Invoice>()) {
            for invoice in invoices where invoice.status == .sent && invoice.balance > 0 {
                guard invoice.dueDate >= today else { continue }
                candidates.append((
                    id: "invoice-\(invoice.id.uuidString)",
                    title: "Invoice due: \(invoice.displayNumber) (\(Format.currency(invoice.balance)))",
                    body: invoice.client?.displayName ?? "",
                    due: invoice.dueDate
                ))
            }
        }

        let soonest = candidates.sorted { $0.due < $1.due }.prefix(maxScheduled)
        for item in soonest {
            schedule(
                id: item.id, title: item.title, body: item.body, on: item.due,
                hour: focus.alertHour(on: item.due, defaultHour: morningHour)
            )
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    private static func schedule(id: String, title: String, body: String, on date: Date, hour: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0

        guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category = NotificationActionParser.category(forRequestID: id) {
            content.categoryIdentifier = category
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
