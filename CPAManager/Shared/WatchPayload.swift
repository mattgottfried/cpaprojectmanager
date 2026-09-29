import Foundation

/// What the iPhone sends the Apple Watch (a compact "today" list plus the running timer),
/// and what the Watch sends back. Plain Foundation only: this file is compiled into the
/// app, the widget and the Watch app.
struct WatchPayload: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        var id: UUID
        var title: String
        var subtitle: String
        var isOverdue: Bool
        /// True when the Watch may complete it (a real task, not a project or follow-up).
        var isTask: Bool
    }

    var generatedAt: Date
    var overdueCount: Int
    var dueTodayCount: Int
    var tasks: [Task]
    /// Set while a timer is running.
    var timerStartedAt: Date?
    var timerLabel: String

    static let empty = WatchPayload(
        generatedAt: Date(timeIntervalSince1970: 0),
        overdueCount: 0, dueTodayCount: 0, tasks: [],
        timerStartedAt: nil, timerLabel: ""
    )

    /// Key inside the WatchConnectivity application context.
    static let contextKey = "payload"

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchPayload? { try? JSONDecoder().decode(WatchPayload.self, from: data) }
}

/// Something the Watch asks the phone to do.
enum WatchCommand: Equatable {
    case complete(UUID)
    case startTimer
    case stopTimer

    static let key = "cmd"
    static let idKey = "id"

    /// Property-list-safe dictionary for WatchConnectivity.
    var message: [String: Any] {
        switch self {
        case .complete(let id): return [Self.key: "complete", Self.idKey: id.uuidString]
        case .startTimer:       return [Self.key: "startTimer"]
        case .stopTimer:        return [Self.key: "stopTimer"]
        }
    }

    init?(message: [String: Any]) {
        guard let name = message[Self.key] as? String else { return nil }
        switch name {
        case "complete":
            guard let raw = message[Self.idKey] as? String, let id = UUID(uuidString: raw) else { return nil }
            self = .complete(id)
        case "startTimer": self = .startTimer
        case "stopTimer":  self = .stopTimer
        default:           return nil
        }
    }
}
