import Foundation
import SwiftData

/// A client of the firm. Deleting a client cascades to their projects (and, in
/// turn, tasks and time entries).
@Model
final class Client {
    // Every stored property has a default value and every relationship is
    // optional — both are requirements for SwiftData + CloudKit sync.
    var id: UUID = UUID()
    var name: String = ""
    var company: String = ""
    var entityTypeRaw: String = EntityType.individual1040.rawValue
    var statusRaw: String = ClientStatus.active.rawValue
    var email: String = ""
    var phone: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    /// This client's QuickBooks Online Customer Id, once synced (see Services/QBO).
    var qboCustomerId: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Project.client)
    var projects: [Project]? = []

    @Relationship(deleteRule: .cascade, inverse: \Document.client)
    var documents: [Document]? = []

    @Relationship(deleteRule: .cascade, inverse: \Invoice.client)
    var invoices: [Invoice]? = []

    @Relationship(deleteRule: .cascade, inverse: \RecurringEngagement.client)
    var recurringEngagements: [RecurringEngagement]? = []

    /// Standalone tasks (no project) linked to this client. Nullify, so deleting a
    /// client never silently deletes to-dos.
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.client)
    var looseTasks: [TaskItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \InboxItem.client)
    var inboxItems: [InboxItem]? = []

    init(
        name: String = "",
        company: String = "",
        entityType: EntityType = .individual1040,
        status: ClientStatus = .active,
        email: String = "",
        phone: String = "",
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.company = company
        self.entityTypeRaw = entityType.rawValue
        self.statusRaw = status.rawValue
        self.email = email
        self.phone = phone
        self.notes = notes
        self.createdAt = .now
    }

    // MARK: Typed accessors over the raw-string storage

    var entityType: EntityType {
        get { EntityType(rawValue: entityTypeRaw) ?? .other }
        set { entityTypeRaw = newValue.rawValue }
    }

    var status: ClientStatus {
        get { ClientStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // MARK: Convenience

    var projectList: [Project] { projects ?? [] }

    var invoiceList: [Invoice] { invoices ?? [] }

    var recurringEngagementList: [RecurringEngagement] { recurringEngagements ?? [] }

    var openProjects: [Project] {
        projectList.filter { !$0.status.isComplete }
    }

    var displayName: String {
        name.isEmpty ? (company.isEmpty ? "Untitled Client" : company) : name
    }

    /// Initials for the avatar bubble.
    var initials: String {
        let source = displayName
        let parts = source.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }
}
