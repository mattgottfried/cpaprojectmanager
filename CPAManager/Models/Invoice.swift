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

    @Relationship(deleteRule: .cascade, inverse: \Payment.invoice)
    var payments: [Payment]? = []

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

    var paymentList: [Payment] {
        (payments ?? []).sorted { $0.date > $1.date }
    }

    var amountPaid: Double {
        Double((payments ?? []).reduce(0) { $0 + InvoiceMath.cents($1.amount) }) / 100
    }

    /// What's still owed.
    var balance: Double {
        InvoiceMath.balance(total: total, payments: (payments ?? []).map(\.amount))
    }

    var isOverdue: Bool {
        InvoiceMath.isOverdue(status: status, dueDate: dueDate, balance: balance)
    }

    /// Records a payment and flips the invoice to Paid when nothing is owed.
    @discardableResult
    func recordPayment(_ amount: Double, on date: Date = .now, method: PaymentMethod = .check, note: String = "") -> Payment {
        // Appending sets the inverse (`payment.invoice`) and inserts it with the invoice.
        let payment = Payment(amount: amount, date: date, method: method, note: note)
        if payments == nil { payments = [] }
        payments?.append(payment)
        refreshPaidStatus()
        return payment
    }

    /// Re-derives Paid/Sent from the payments on file (call after adding or removing one).
    func refreshPaidStatus() {
        if InvoiceMath.isPaidInFull(total: total, payments: (payments ?? []).map(\.amount)) {
            status = .paid
        } else if status == .paid {
            status = .sent
        }
    }

    var displayNumber: String {
        String(format: "INV-%04d", number)
    }
}
