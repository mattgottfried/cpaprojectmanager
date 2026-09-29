import Foundation
import WatchConnectivity

/// Watch side of the companion: holds the latest "today" payload from the iPhone and
/// sends the wearer's actions back. The Watch never touches the CloudKit store itself.
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var payload: WatchPayload
    private static let cacheKey = "lastPayload"

    private override init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey), let cached = WatchPayload.decode(data) {
            payload = cached
        } else {
            payload = .empty
        }
        super.init()
    }

    var hasData: Bool { payload.generatedAt.timeIntervalSince1970 > 0 }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Actions

    func complete(_ task: WatchPayload.Task) {
        // Optimistic: remove it right away; the phone's next push is authoritative.
        var next = payload
        next.tasks.removeAll { $0.id == task.id }
        if task.isOverdue { next.overdueCount = max(0, next.overdueCount - 1) }
        apply(next)
        send(.complete(task.id))
    }

    func toggleTimer() {
        var next = payload
        if payload.timerStartedAt == nil {
            next.timerStartedAt = .now
            next.timerLabel = "General time"
            apply(next)
            send(.startTimer)
        } else {
            next.timerStartedAt = nil
            next.timerLabel = ""
            apply(next)
            send(.stopTimer)
        }
    }

    private func send(_ command: WatchCommand) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(command.message)
            return
        }
        if session.isReachable {
            session.sendMessage(command.message, replyHandler: nil) { _ in
                // Phone went away mid-send — queue it so it isn't lost.
                session.transferUserInfo(command.message)
            }
        } else {
            session.transferUserInfo(command.message)
        }
    }

    private func apply(_ new: WatchPayload) {
        payload = new
        if let data = new.encoded() { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    private func receive(context: [String: Any]) {
        guard let data = context[WatchPayload.contextKey] as? Data, let incoming = WatchPayload.decode(data) else { return }
        DispatchQueue.main.async { self.apply(incoming) }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        receive(context: session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(context: applicationContext)
    }
}
