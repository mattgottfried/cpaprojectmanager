import Foundation
import SwiftData

/// One line of a recurring invoice's template.
struct RecurringInvoiceLine: Codable, Equatable, Identifiable {
    var id = UUID()
    var detail: String
    var quantity: Double
    var rate: Double

    var amount: Double { Double(InvoiceMath.cents(quantity * rate)) / 100 }
}

/// A retainer / standing bill. On its issue date the app drafts an invoice for review
/// (never sends anything on its own) and advances the schedule.
@Model
final class RecurringInvoice {
    var id: UUID = UUID()
    var name: String = ""
    var frequencyRaw: String = Frequency.monthly.rawValue
    /// The next date an invoice should be drafted.
    var nextIssueDate: Date = Date.now
    /// Net terms: due this many days after the issue date.
    var termsDays: Int = 30
    var isActive: Bool = true
    var notes: String = ""
    /// JSON-encoded `[RecurringInvoiceLine]` (kept as data so CloudKit needs no extra record type).
    var linesData: Data = Data()
    var lastGeneratedAt: Date? = nil
    var createdAt: Date = Date.now

    var client: Client? = nil

    init(
        name: String = "",
        frequency: Frequency = .monthly,
        nextIssueDate: Date = .now,
        termsDays: Int = 30,
        lines: [RecurringInvoiceLine] = [],
        client: Client? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.frequencyRaw = frequency.rawValue
        self.nextIssueDate = nextIssueDate
        self.termsDays = termsDays
        self.client = client
        self.createdAt = .now
        self.lines = lines
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var lines: [RecurringInvoiceLine] {
        get { (try? JSONDecoder().decode([RecurringInvoiceLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var total: Double {
        Double(lines.reduce(0) { $0 + InvoiceMath.cents($1.amount) }) / 100
    }
}
