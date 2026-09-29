import Foundation
import SwiftData

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case software, office, travel, meals, professionalFees, education
    case insurance, advertising, bankFees, utilities, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .software:         return "Software & subscriptions"
        case .office:           return "Office & supplies"
        case .travel:           return "Travel & mileage"
        case .meals:            return "Meals"
        case .professionalFees: return "Licenses & professional fees"
        case .education:        return "Education & CPE"
        case .insurance:        return "Insurance"
        case .advertising:      return "Marketing & advertising"
        case .bankFees:         return "Bank & processing fees"
        case .utilities:        return "Phone & internet"
        case .other:            return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .software:         return "app.badge"
        case .office:           return "paperclip"
        case .travel:           return "car.fill"
        case .meals:            return "fork.knife"
        case .professionalFees: return "checkmark.seal"
        case .education:        return "graduationcap.fill"
        case .insurance:        return "shield.fill"
        case .advertising:      return "megaphone.fill"
        case .bankFees:         return "creditcard.fill"
        case .utilities:        return "wifi"
        case .other:            return "ellipsis.circle"
        }
    }

    /// Starting point for the deductible share; always editable per expense. Business
    /// meals are commonly only partly deductible — confirm with the current rules.
    var defaultDeductiblePercent: Int { self == .meals ? 50 : 100 }
}

/// A business expense with an optional receipt image/PDF.
@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var vendor: String = ""
    var note: String = ""
    /// 0–100. Defaults from the category when the expense is created.
    var deductiblePercent: Int = 100
    @Attribute(.externalStorage) var receiptData: Data = Data()
    var receiptExtension: String = ""
    var createdAt: Date = Date.now

    /// Set when a client should reimburse this (e.g. filing fees you paid for them).
    var client: Client? = nil

    init(
        amount: Double = 0,
        date: Date = .now,
        category: ExpenseCategory = .other,
        vendor: String = "",
        note: String = "",
        client: Client? = nil
    ) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.categoryRaw = category.rawValue
        self.vendor = vendor
        self.note = note
        self.deductiblePercent = category.defaultDeductiblePercent
        self.client = client
        self.createdAt = .now
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var hasReceipt: Bool { !receiptData.isEmpty }

    var deductibleAmount: Double {
        ExpenseMath.deductible(amount: amount, percent: deductiblePercent)
    }
}
