import Foundation
import SwiftData

enum QuoteService {
    /// Turns a quote into a draft invoice (one line per quote line), marks the quote
    /// accepted and remembers the invoice. Returns nil when there is no client, no lines,
    /// or the quote was already converted.
    @discardableResult
    static func convertToInvoice(_ quote: Quote, dueInDays: Int = 14, context: ModelContext, now: Date = .now) -> Invoice? {
        guard quote.invoiceID == nil, let client = quote.client else { return nil }
        let lines = QuoteMath.cleaned(quote.lines)
        guard !lines.isEmpty else { return nil }

        let existing = (try? context.fetch(FetchDescriptor<Invoice>())) ?? []
        let number = (existing.map(\.number).max() ?? 1000) + 1
        let due = Calendar.current.date(byAdding: .day, value: dueInDays, to: now) ?? now
        let invoice = Invoice(number: number, issueDate: now, dueDate: due, notes: "From quote \(quote.displayNumber)", client: client)
        context.insert(invoice)
        for (index, line) in lines.enumerated() {
            context.insert(InvoiceLine(detail: line.detail, quantity: line.quantity, rate: line.rate, sortIndex: index, invoice: invoice))
        }
        quote.status = .accepted
        quote.invoiceID = invoice.id
        try? context.save()
        return invoice
    }
}
