import Foundation

enum SignatureStatus: String, CaseIterable {
    case none = ""
    case sent
    case signed

    var label: String {
        switch self {
        case .none:   return "Not sent"
        case .sent:   return "Awaiting signature"
        case .signed: return "Signed"
        }
    }
}

struct SignatureCandidate: Equatable {
    var id: UUID
    var title: String
    var clientID: UUID?
    var clientName: String
    var statusRaw: String
    var sentAt: Date?
}

struct AwaitingSignature: Equatable, Identifiable {
    var id: UUID
    var title: String
    var clientID: UUID?
    var clientName: String
    var daysWaiting: Int
}

enum SignatureTracking {
    static func daysWaiting(sentAt: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: sentAt), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    /// Documents sent for signature and still unsigned after `chaseDays`, longest-waiting first.
    static func awaiting(_ docs: [SignatureCandidate], chaseDays: Int, now: Date = .now, calendar: Calendar = .current) -> [AwaitingSignature] {
        docs.compactMap { doc -> AwaitingSignature? in
            guard doc.statusRaw == SignatureStatus.sent.rawValue, let sentAt = doc.sentAt else { return nil }
            let days = daysWaiting(sentAt: sentAt, now: now, calendar: calendar)
            guard days >= max(0, chaseDays) else { return nil }
            return AwaitingSignature(id: doc.id, title: doc.title, clientID: doc.clientID, clientName: doc.clientName, daysWaiting: days)
        }
        .sorted { $0.daysWaiting > $1.daysWaiting }
    }
}

enum UploadLink {
    /// Cleans what the user pasted: trims, adds https:// when missing, and rejects anything
    /// that isn't a plain web address. Returns "" for an empty or invalid entry.
    static func normalized(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") else { return "" }
        return text
    }
}
