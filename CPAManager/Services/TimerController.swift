import Foundation
import SwiftData
import Observation
import UserNotifications
#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Owns the single running time entry and drives its Live Activity. Injected into the
/// SwiftUI environment so any screen can start/stop the billable-hours timer.
@Observable
final class TimerController {
    private(set) var runningEntryID: UUID?
    private(set) var startedAt: Date?
    private(set) var label: String = ""
    private(set) var clientName: String = ""

    var isRunning: Bool { runningEntryID != nil }

    var elapsedSeconds: Double {
        guard let startedAt else { return 0 }
        return max(0, Date.now.timeIntervalSince(startedAt))
    }

    // MARK: Start / stop

    func start(project: Project?, hourlyRate: Double, isBillable: Bool, context: ModelContext) {
        if isRunning { stop(context: context) }

        let entry = TimeEntry(
            startedAt: .now,
            isBillable: isBillable,
            hourlyRate: hourlyRate,
            project: project
        )
        context.insert(entry)
        try? context.save()

        runningEntryID = entry.id
        startedAt = entry.startedAt
        label = project?.title ?? "General time"
        clientName = project?.client?.displayName ?? ""

        startLiveActivity(startedAt: entry.startedAt, isBillable: isBillable)
        scheduleStillRunningReminder(startedAt: entry.startedAt)
        SnapshotBuilder.rebuild(context: context)
    }

    func stop(context: ModelContext) {
        guard let id = runningEntryID else { return }
        let descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first {
            entry.endedAt = .now
            try? context.save()
        }
        clearRunningState()
        endLiveActivity()
        cancelStillRunningReminder()
        SnapshotBuilder.rebuild(context: context)
    }

    /// Re-attach to a still-running entry after a relaunch (e.g. timer left running).
    func restore(context: ModelContext) {
        let descriptor = FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.endedAt == nil })
        guard let entry = try? context.fetch(descriptor)
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first else { return }

        runningEntryID = entry.id
        startedAt = entry.startedAt
        label = entry.projectTitle.isEmpty ? "General time" : entry.projectTitle
        clientName = entry.clientName
    }

    private func clearRunningState() {
        runningEntryID = nil
        startedAt = nil
        label = ""
        clientName = ""
    }

    // MARK: "Still running?" reminder

    private static let reminderID = "timer-running"

    private func scheduleStillRunningReminder(startedAt: Date) {
        let hours = UserDefaults.standard.integer(forKey: SettingsKeys.timerReminderHours)
        guard let fire = TimerReminderPlan.fireDate(startedAt: startedAt, afterHours: hours), fire > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timer still running"
        content.body = "\(label) has been running \(Format.hoursMinutes(fire.timeIntervalSince(startedAt))). Stop it if you're done."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.reminderID, content: content, trigger: trigger))
    }

    private func cancelStillRunningReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderID])
    }

    // MARK: Live Activity

    private func startLiveActivity(startedAt: Date, isBillable: Bool) {
        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = TimerActivityAttributes(clientName: clientName, projectTitle: label)
        let state = TimerActivityAttributes.ContentState(startedAt: startedAt, isBillable: isBillable)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activities may be disabled; timer still works without one.
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
        Task {
            for activity in Activity<TimerActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
