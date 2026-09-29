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

    var systemImage: String {
        switch self {
        case .active:   return "checkmark.circle.fill"
        case .prospect: return "sparkle.magnifyingglass"
        case .inactive: return "moon.zzz.fill"
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
//
// Mirrors the firm's real pipeline (Not Started -> Awaiting Docs -> In Progress ->
// On Hold -> In Review -> Awaiting Signature -> Ready to File -> Filed -> Complete).
// Raw values for the original five cases are unchanged so existing TestFlight data
// (and CloudKit records already synced) keep working; only new cases were added.

enum ProjectStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted
    case awaitingDocs
    case inProgress
    case waitingOnClient
    case review
    case awaitingSignature
    case readyToFile
    case filed
    case complete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted:        return "Not Started"
        case .awaitingDocs:      return "Awaiting Docs"
        case .inProgress:        return "In Progress"
        case .waitingOnClient:   return "On Hold"
        case .review:            return "In Review"
        case .awaitingSignature: return "Awaiting Signature"
        case .readyToFile:       return "Ready to File"
        case .filed:             return "Filed"
        case .complete:          return "Complete"
        }
    }

    /// Sort weight for boards / grouping (open work first, complete last).
    var order: Int {
        switch self {
        case .notStarted:        return 0
        case .awaitingDocs:      return 1
        case .inProgress:        return 2
        case .waitingOnClient:   return 3
        case .review:            return 4
        case .awaitingSignature: return 5
        case .readyToFile:       return 6
        case .filed:             return 7
        case .complete:          return 8
        }
    }

    var isComplete: Bool { self == .complete }

    var color: Color {
        switch self {
        case .notStarted:        return .gray
        case .awaitingDocs:      return .orange
        case .inProgress:        return .blue
        case .waitingOnClient:   return .red
        case .review:            return .purple
        case .awaitingSignature: return .yellow
        case .readyToFile:       return .cyan
        case .filed:             return .green
        case .complete:          return .mint
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted:        return "circle"
        case .awaitingDocs:      return "tray.and.arrow.down.fill"
        case .inProgress:        return "circle.lefthalf.filled"
        case .waitingOnClient:   return "pause.circle.fill"
        case .review:            return "magnifyingglass"
        case .awaitingSignature: return "signature"
        case .readyToFile:       return "paperplane.fill"
        case .filed:             return "checkmark.seal.fill"
        case .complete:          return "checkmark.circle.fill"
        }
    }
}

// MARK: - Hold reason
//
// Mirrors the firm's "Put On Hold" Shortcut, which pairs a reason category with a
// free-text detail (e.g. "Waiting on Client — Debt Schedule").

enum HoldReason: String, CaseIterable, Identifiable, Codable {
    case waitingOnClient
    case waitingOnRelatedEntity
    case waitingOnBookkeeping
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .waitingOnClient:       return "Waiting on Client"
        case .waitingOnRelatedEntity: return "Waiting on Related Entity"
        case .waitingOnBookkeeping:  return "Waiting on Bookkeeping"
        case .other:                 return "Other"
        }
    }
}

// MARK: - Service type

enum ServiceType: String, CaseIterable, Identifiable, Codable {
    case taxReturn
    case bookkeeping
    case payroll
    case advisory
    case irsNotice
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .taxReturn:   return "Tax Return"
        case .bookkeeping: return "Bookkeeping"
        case .payroll:     return "Payroll"
        case .advisory:    return "Advisory"
        case .irsNotice:   return "IRS Notice"
        case .other:       return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .taxReturn:   return "doc.text.fill"
        case .bookkeeping: return "book.closed.fill"
        case .payroll:     return "dollarsign.circle.fill"
        case .advisory:    return "lightbulb.fill"
        case .irsNotice:   return "envelope.open.fill"
        case .other:       return "folder.fill"
        }
    }
}

// MARK: - Recurrence frequency

enum Frequency: String, CaseIterable, Identifiable, Codable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case annually

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekly:    return "Weekly"
        case .biweekly:  return "Every 2 Weeks"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        case .annually:  return "Annually"
        }
    }

    private var component: (Calendar.Component, Int) {
        switch self {
        case .weekly:    return (.day, 7)
        case .biweekly:  return (.day, 14)
        case .monthly:   return (.month, 1)
        case .quarterly: return (.month, 3)
        case .annually:  return (.year, 1)
        }
    }

    /// Advance a date by one period of this frequency.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let (unit, value) = component
        return calendar.date(byAdding: unit, value: value, to: date) ?? date
    }

    /// The date one period earlier — used to label recurring work by the period it
    /// covers (e.g. a bookkeeping project due in June is titled for the May close).
    func previousDate(before date: Date, calendar: Calendar = .current) -> Date {
        let (unit, value) = component
        return calendar.date(byAdding: unit, value: -value, to: date) ?? date
    }
}

// MARK: - Invoice status

enum InvoiceStatus: String, CaseIterable, Identifiable, Codable {
    case draft
    case sent
    case paid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent:  return "Sent"
        case .paid:  return "Paid"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .gray
        case .sent:  return .blue
        case .paid:  return .green
        }
    }
}

// MARK: - QuickBooks Online sync state

enum QBOSyncState: String, CaseIterable, Identifiable, Codable {
    case notSynced
    case synced
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notSynced: return "Not Synced"
        case .synced:    return "Synced"
        case .failed:    return "Sync Failed"
        }
    }

    var color: Color {
        switch self {
        case .notSynced: return .gray
        case .synced:    return .green
        case .failed:    return .red
        }
    }

    var systemImage: String {
        switch self {
        case .notSynced: return "icloud.slash"
        case .synced:    return "checkmark.icloud.fill"
        case .failed:    return "exclamationmark.icloud.fill"
        }
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
