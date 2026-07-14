import SwiftUI

// MARK: - Client entity type (drives the kind of tax work)

enum EntityType: String, CaseIterable, Identifiable, Codable {
    case individual1040
    case sCorp1120S
    case cCorp1120
    case partnership1065
    case trust1041
    case nonProfit990
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .individual1040:  return "Individual (1040)"
        case .sCorp1120S:      return "S-Corp (1120-S)"
        case .cCorp1120:       return "C-Corp (1120)"
        case .partnership1065: return "Partnership (1065)"
        case .trust1041:       return "Trust/Estate (1041)"
        case .nonProfit990:    return "Nonprofit (990)"
        case .other:           return "Other"
        }
    }

    /// Short code shown on compact badges.
    var code: String {
        switch self {
        case .individual1040:  return "1040"
        case .sCorp1120S:      return "1120-S"
        case .cCorp1120:       return "1120"
        case .partnership1065: return "1065"
        case .trust1041:       return "1041"
        case .nonProfit990:    return "990"
        case .other:           return "—"
        }
    }
}

// MARK: - Client status

enum ClientStatus: String, CaseIterable, Identifiable, Codable {
    case active
    case prospect
    case inactive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .active:   return "Active"
        case .prospect: return "Prospect"
        case .inactive: return "Inactive"
        }
    }

    var color: Color {
        switch self {
        case .active:   return .green
        case .prospect: return .blue
        case .inactive: return .gray
        }
    }
}

// MARK: - Project / engagement status

enum ProjectStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted
    case inProgress
    case waitingOnClient
    case review
    case complete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted:      return "Not Started"
        case .inProgress:      return "In Progress"
        case .waitingOnClient: return "Waiting on Client"
        case .review:          return "In Review"
        case .complete:        return "Complete"
        }
    }

    /// Sort weight for boards / grouping (open work first, complete last).
    var order: Int {
        switch self {
        case .notStarted:      return 0
        case .waitingOnClient: return 1
        case .inProgress:      return 2
        case .review:          return 3
        case .complete:        return 4
        }
    }

    var isComplete: Bool { self == .complete }

    var color: Color {
        switch self {
        case .notStarted:      return .gray
        case .inProgress:      return .blue
        case .waitingOnClient: return .orange
        case .review:          return .purple
        case .complete:        return .green
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted:      return "circle"
        case .inProgress:      return "circle.lefthalf.filled"
        case .waitingOnClient: return "hourglass"
        case .review:          return "magnifyingglass"
        case .complete:        return "checkmark.circle.fill"
        }
    }
}

// MARK: - Service type

enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case taxReturn
    case bookkeeping
    case payroll
    case advisory
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taxReturn:   return "Tax Return"
        case .bookkeeping: return "Bookkeeping"
        case .payroll:     return "Payroll"
        case .advisory:    return "Advisory"
        case .other:       return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .taxReturn:   return "doc.text.fill"
        case .bookkeeping: return "book.closed.fill"
        case .payroll:     return "dollarsign.circle.fill"
        case .advisory:    return "lightbulb.fill"
        case .other:       return "folder.fill"
        }
    }
}

// MARK: - Recurrence frequency

enum Frequency: String, CaseIterable, Identifiable, Codable {
    case weekly
    case monthly
    case quarterly
    case annually

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly:    return "Weekly"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .annually:  return "Annually"
        }
    }

    /// Advance a date by one period of this frequency.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        let value: Int
        switch self {
        case .weekly:    component = .day;   value = 7
        case .monthly:   component = .month; value = 1
        case .quarterly: component = .month; value = 3
        case .annually:  component = .year;  value = 1
        }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }
}

// MARK: - Priority

enum Priority: String, CaseIterable, Identifiable, Codable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        }
    }

    var order: Int {
        switch self {
        case .high:   return 0
        case .normal: return 1
        case .low:    return 2
        }
    }

    var color: Color {
        switch self {
        case .low:    return .gray
        case .normal: return .blue
        case .high:   return .red
        }
    }
}
