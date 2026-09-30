import Foundation
import SwiftData

/// A standard price ("1040 individual return", "Monthly bookkeeping") you reuse on quotes.
@Model
final class FeeItem {
    var id: UUID = UUID()
    var name: String = ""
    var detail: String = ""
    var unitPrice: Double = 0
    /// Hourly items multiply by hours when added to a quote; flat items are quantity 1.
    var isHourly: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(name: String = "", detail: String = "", unitPrice: Double = 0, isHourly: Bool = false, sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.detail = detail
        self.unitPrice = unitPrice
        self.isHourly = isHourly
        self.sortIndex = sortIndex
        self.createdAt = .now
    }
}

/// A price proposal for a client. Lines are stored as JSON (like recurring invoices);
/// accepting a quote can turn it into a draft invoice.
@Model
final class Quote {
    var id: UUID = UUID()
    var number: Int = 1001
    var statusRaw: String = QuoteStatus.draft.rawValue
    var issueDate: Date = Date.now
    var validUntil: Date? = nil
    var notes: String = ""
    var linesData: Data = Data()
    /// Set once the quote has been turned into an invoice.
    var invoiceID: UUID? = nil
    var createdAt: Date = Date.now

    var client: Client? = nil

    init(number: Int = 1001, client: Client? = nil, lines: [QuoteLine] = [], validUntil: Date? = nil, notes: String = "") {
        self.id = UUID()
        self.number = number
        self.client = client
        self.validUntil = validUntil
        self.notes = notes
        self.createdAt = .now
        self.lines = lines
    }

    var status: QuoteStatus {
        get { QuoteStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var lines: [QuoteLine] {
        get { (try? JSONDecoder().decode([QuoteLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var total: Double { QuoteMath.total(lines) }
    var displayNumber: String { QuoteMath.displayNumber(number) }
}
