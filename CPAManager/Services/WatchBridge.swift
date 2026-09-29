import Foundation
import SwiftData
#if os(iOS) && !targetEnvironment(macCatalyst)
import WatchConnectivity

/// iPhone side of the Apple Watch companion. Pushes the "today" list to the Watch
/// whenever the dashboard snapshot is rebuilt, and applies the Watch's requests
/// (complete a task, start/stop the timer) to the real store.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private weak var timer: TimerController?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Call once at launch with the app's timer.
    func start(timer: TimerController) {
        self.timer = timer
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends the latest state. Uses the application context, which the system delivers
    /// even if the Watch app isn't running (only the newest value is kept).
    func push(snapshot: DashboardSnapshot) {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        let payload = WatchPayloadBuilder.make(
            snapshot: snapshot,
            timerStartedAt: timer?.startedAt,
            timerLabel: timer?.label ?? ""
        )
        guard let data = payload.encoded() else { return }
        try? session.updateApplicationContext([WatchPayload.contextKey: data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        DispatchQueue.main.async {
            self.push(snapshot: DashboardSnapshot.load())
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A different Watch was paired — reactivate for it.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    // MARK: Commands

    private func handle(_ message: [String: Any]) {
        guard let command = WatchCommand(message: message) else { return }
        let timer = self.timer
        Task { @MainActor in
            let context = Persistence.shared.container.mainContext
            switch command {
            case .complete(let id):
                let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
                if let task = tasks.first(where: { $0.id == id }), !task.isDone {
                    TaskCompletion.complete(task, context: context)
                    try? context.save()
                    let hour = UserDefaults.standard.object(forKey: SettingsKeys.reminderHour) as? Int ?? 8
                    NotificationScheduler.rescheduleAll(context: context, morningHour: hour)
                }
            case .startTimer:
                let stored = UserDefaults.standard.double(forKey: SettingsKeys.defaultHourlyRate)
                timer?.start(project: nil, hourlyRate: stored > 0 ? stored : 150, isBillable: true, context: context)
            case .stopTimer:
                timer?.stop(context: context)
            }
            // Rebuilds the snapshot, which pushes the new state back to the Watch.
            SnapshotBuilder.rebuild(context: context)
        }
    }
}
#endif
