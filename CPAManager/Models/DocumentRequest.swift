import Foundation
import SwiftData

/// One item a client owes you ("2025 W-2s", "December bank statement"). Tick it off
/// when it arrives; outstanding ones can be chased with a single email.
@Model
final class DocumentRequest {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var requestedAt: Date = Date.now
    /// When you need it by (shows on Today until received).
    var dueDate: Date? = nil
    var receivedAt: Date? = nil
    var createdAt: Date = Date.now

    var client: Client? = nil
    var project: Project? = nil

    init(title: String = "", notes: String = "", dueDate: Date? = nil, client: Client? = nil, project: Project? = nil) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.client = client
        self.project = project
        self.requestedAt = .now
        self.createdAt = .now
    }

    var isReceived: Bool { receivedAt != nil }

    func markReceived(on date: Date = .now) { receivedAt = date }
    func markOutstanding() { receivedAt = nil }
}
