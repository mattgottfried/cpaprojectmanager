import Foundation
import SwiftData

/// A bill sent to a client, built from unbilled time entries and/or flat-fee
/// line items. `qboId`/`qboSyncState` track its mirror record in QuickBooks
/// Online once synced (see `Services/QBO`).
@Model
final class Invoice {
    var id: UUID = UUID()
    var number: Int = 1
    var issueDate: Date = Date.now
    var dueDate: Date = Date.now
    var statusRaw: String = InvoiceStatus.draft.rawValue
    var notes: String = ""
    var qboId: String = ""
    var qboSyncStateRaw: String = QBOSyncState.notSynced.rawValue
    var qboSyncError: String = ""
    var createdAt: Date = Date.now

    var client: Client? = nil

    @Relationship(deleteRule: .cascade, inverse: \InvoiceLine.invoice)
    var lines: [InvoiceLine]? = []

    init(
        number: Int = 1,
        issueDate: Date = .now,
        dueDate: Date = .now,
        status: InvoiceStatus = .draft,
        notes: String = "",
        client: Client? = nil
    ) {
        self.id = UUID()
        self.number = number
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.statusRaw = status.rawValue
        self.notes = notes
        self.client = client
        self.createdAt = .now
    }

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var qboSyncState: QBOSyncState {
        get { QBOSyncState(rawValue: qboSyncStateRaw) ?? .notSynced }
        set { qboSyncStateRaw = newValue.rawValue }
    }

    var lineList: [InvoiceLine] {
        (lines ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }

    var total: Double {
        lineList.reduce(0) { $0 + $1.amount }
    }

    var isOverdue: Bool {
        status != .paid && dueDate < Calendar.current.startOfDay(for: .now)
    }

    var displayNumber: String {
        String(format: "INV-%04d", number)
    }
}
