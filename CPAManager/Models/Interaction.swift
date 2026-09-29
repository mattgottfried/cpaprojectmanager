import Foundation
import SwiftData

enum InteractionKind: String, CaseIterable, Identifiable, Codable {
    case call, email, text, meeting, note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .call:    return "Call"
        case .email:   return "Email"
        case .text:    return "Text"
        case .meeting: return "Meeting"
        case .note:    return "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .call:    return "phone.fill"
        case .email:   return "envelope.fill"
        case .text:    return "message.fill"
        case .meeting: return "person.2.fill"
        case .note:    return "note.text"
        }
    }
}

/// One entry in a client's communication history.
@Model
final class Interaction {
    var id: UUID = UUID()
    var kindRaw: String = InteractionKind.note.rawValue
    var summary: String = ""
    var occurredAt: Date = Date.now
    var createdAt: Date = Date.now

    var client: Client? = nil

    init(kind: InteractionKind = .note, summary: String = "", occurredAt: Date = .now, client: Client? = nil) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.summary = summary
        self.occurredAt = occurredAt
        self.createdAt = .now
        self.client = client
    }

    var kind: InteractionKind {
        get { InteractionKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }
}
