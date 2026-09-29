import Foundation
import SwiftData

enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case check, ach, card, cash, quickbooks, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .check:      return "Check"
        case .ach:        return "ACH / bank transfer"
        case .card:       return "Card"
        case .cash:       return "Cash"
        case .quickbooks: return "QuickBooks"
        case .other:      return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .check:      return "doc.text"
        case .ach:        return "building.columns"
        case .card:       return "creditcard"
        case .cash:       return "banknote"
        case .quickbooks: return "arrow.triangle.2.circlepath"
        case .other:      return "ellipsis.circle"
        }
    }
}

/// A payment received against an invoice. Partial payments are allowed; the invoice
/// flips to Paid when its balance reaches zero.
@Model
final class Payment {
    var id: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var methodRaw: String = PaymentMethod.check.rawValue
    var note: String = ""
    var createdAt: Date = Date.now

    var invoice: Invoice? = nil

    init(amount: Double = 0, date: Date = .now, method: PaymentMethod = .check, note: String = "", invoice: Invoice? = nil) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.methodRaw = method.rawValue
        self.note = note
        self.invoice = invoice
        self.createdAt = .now
    }

    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .other }
        set { methodRaw = newValue.rawValue }
    }
}
