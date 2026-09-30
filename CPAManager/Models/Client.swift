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
    /// Comma-separated, normalized tags (see TagSet).
    var tagsRaw: String = ""
    /// When to reach out next. Shows on Today from that day; cleared when contact is logged.
    var followUpDate: Date? = nil
    /// Raw `LeadStage`; empty means "not tracked as a lead" (see `leadStage`).
    var leadStageRaw: String = ""
    /// Estimated annual fees, for the pipeline total.
    var leadValue: Double = 0
    /// Comma-separated tax years for which an extension has been filed ("2025, 2024").
    var extensionYearsRaw: String = ""
    /// Yearly occasions (only month/day matter for the birthday; the anniversary's year
    /// is the year they became a client). `*AckYear` is the year we last acknowledged it.
    var birthday: Date? = nil
    var anniversary: Date? = nil
    var birthdayAckYear: Int = 0
    var anniversaryAckYear: Int = 0
    /// Per-client hourly rate; 0 means "use the firm default".
    var hourlyRateOverride: Double = 0
    /// Flat-fee clients' timers default to non-billable (the fee goes on a quote/invoice).
    var isFlatFee: Bool = false
    /// The client's folder in Google Drive (see `DriveBrowserView`); empty = none chosen.
    var driveFolderID: String = ""
    var driveFolderName: String = ""

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

    @Relationship(deleteRule: .cascade, inverse: \Interaction.client)
    var interactions: [Interaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \DocumentRequest.client)
    var documentRequests: [DocumentRequest]? = []

    @Relationship(deleteRule: .cascade, inverse: \RecurringInvoice.client)
    var recurringInvoices: [RecurringInvoice]? = []

    @Relationship(deleteRule: .cascade, inverse: \Quote.client)
    var quotes: [Quote]? = []

    @Relationship(deleteRule: .nullify, inverse: \Expense.client)
    var expenses: [Expense]? = []

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

    var hasFollowUp: Bool { followUpDate != nil }

    var documentRequestList: [DocumentRequest] { documentRequests ?? [] }

    /// Tax years with an extension filed.
    var extensionYears: Set<Int> {
        get { Set(extensionYearsRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }) }
        set { extensionYearsRaw = newValue.sorted().map(String.init).joined(separator: ", ") }
    }

    /// Pipeline stage. Existing "Prospect" clients read as `.new` leads.
    var leadStage: LeadStage? {
        get { LeadPipeline.effectiveStage(raw: leadStageRaw, status: status) }
        set {
            leadStageRaw = newValue?.rawValue ?? ""
            if let newValue { status = LeadPipeline.status(for: newValue) }
        }
    }

    var leadSummary: LeadSummary? {
        guard let stage = leadStage else { return nil }
        return LeadSummary(id: id, stage: stage, value: leadValue, lastContact: lastContactedAt, createdAt: createdAt)
    }

    var interactionList: [Interaction] { interactions ?? [] }

    var tags: [String] {
        get { TagSet.parse(tagsRaw) }
        set { tagsRaw = TagSet.encode(newValue) }
    }

    /// Most recent logged contact, if any.
    var lastContactedAt: Date? { interactionList.map(\.occurredAt).max() }

    var summary: ClientSummary {
        ClientSummary(
            id: id, displayName: displayName, company: company, email: email,
            status: status, entityType: entityType, tags: tags, openWorkCount: openProjects.count
        )
    }

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
