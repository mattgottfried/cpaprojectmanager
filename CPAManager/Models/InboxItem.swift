import Foundation
import SwiftData

/// Where a captured item came from. Stored as a raw string (CloudKit-safe).
enum InboxSource: String, CaseIterable, Codable {
    case manual, text, email, note, siri

    var label: String {
        switch self {
        case .manual: return "Typed"
        case .text:   return "Text message"
        case .email:  return "Email"
        case .note:   return "Note"
        case .siri:   return "Siri"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .text:   return "message.fill"
        case .email:  return "envelope.fill"
        case .note:   return "note.text"
        case .siri:   return "waveform"
        }
    }
}

/// Something captured quickly that still needs a decision: make it a task, attach
/// it to a project, or dismiss it. Processed items are kept (not deleted) so that
/// re-importing the same note later doesn't resurrect them.
@Model
final class InboxItem {
    var id: UUID = UUID()
    var text: String = ""
    var sourceRaw: String = InboxSource.manual.rawValue
    var createdAt: Date = Date.now
    var isProcessed: Bool = false
    var processedAt: Date? = nil
    /// Lowercased/collapsed text, used to skip duplicates on re-import.
    var dedupeKey: String = ""
    /// Stable ID from the source system (e.g. "gmail:<messageID>") so a sync never
    /// imports the same email twice, even if its subject repeats.
    var externalID: String = ""
    /// Web link back to the original (e.g. the Gmail thread).
    var link: String = ""
    /// A file from the share extension, stored in the App Group's shared attachments
    /// folder until it's filed onto a client or project.
    var attachmentName: String = ""

    var client: Client? = nil

    init(text: String = "", source: InboxSource = .manual) {
        self.id = UUID()
        self.text = text
        self.sourceRaw = source.rawValue
        self.createdAt = .now
        self.dedupeKey = NoteDigestParser.dedupeKey(text)
    }

    var source: InboxSource {
        get { InboxSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    func markProcessed() {
        isProcessed = true
        processedAt = .now
    }

    func reopen() {
        isProcessed = false
        processedAt = nil
    }
}
