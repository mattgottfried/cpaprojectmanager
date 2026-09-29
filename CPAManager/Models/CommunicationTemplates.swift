import Foundation
import SwiftData

enum LetterKind: String, CaseIterable, Identifiable, Codable {
    case engagement, proposal, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .engagement: return "Engagement letter"
        case .proposal:   return "Proposal"
        case .other:      return "Letter"
        }
    }
    /// Engagement letters and proposals end with an accept-and-sign block.
    var hasSignatureBlock: Bool { self != .other }
}

/// A reusable letter with merge fields ("{client}", "{fee}"…) — engagement letters,
/// proposals. Filled in per client and saved as a PDF (see `LetterPDF`).
@Model
final class LetterTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = LetterKind.engagement.rawValue
    var body: String = ""
    var createdAt: Date = Date.now

    init(name: String = "", kind: LetterKind = .engagement, body: String = "") {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.body = body
        self.createdAt = .now
    }

    var kind: LetterKind {
        get { LetterKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

/// A reusable email (subject + body) with merge fields, sent through the user's own
/// mail app via `mailto:` and logged on the client.
@Model
final class EmailTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var subject: String = ""
    var body: String = ""
    var createdAt: Date = Date.now

    init(name: String = "", subject: String = "", body: String = "") {
        self.id = UUID()
        self.name = name
        self.subject = subject
        self.body = body
        self.createdAt = .now
    }
}
