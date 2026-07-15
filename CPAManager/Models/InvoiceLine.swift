import Foundation
import SwiftData

/// A single billed item on an invoice — either generated from a `TimeEntry`
/// (hours x rate) or a manually added flat-fee line.
@Model
final class InvoiceLine {
    var id: UUID = UUID()
    var detail: String = ""
    var quantity: Double = 1
    var rate: Double = 0
    var sortIndex: Int = 0
    /// If generated from a `TimeEntry`, its id — used to mark the entry billed.
    var timeEntryID: UUID? = nil

    var invoice: Invoice? = nil

    init(
        detail: String = "",
        quantity: Double = 1,
        rate: Double = 0,
        sortIndex: Int = 0,
        timeEntryID: UUID? = nil,
        invoice: Invoice? = nil
    ) {
        self.id = UUID()
        self.detail = detail
        self.quantity = quantity
        self.rate = rate
        self.sortIndex = sortIndex
        self.timeEntryID = timeEntryID
        self.invoice = invoice
    }

    var amount: Double { quantity * rate }
}
