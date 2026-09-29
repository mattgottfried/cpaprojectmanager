import Foundation

/// Where a prospective client is in the sales process.
enum LeadStage: String, CaseIterable, Identifiable, Codable {
    case new, contacted, proposalSent, won, lost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .new:          return "New"
        case .contacted:    return "Contacted"
        case .proposalSent: return "Proposal sent"
        case .won:          return "Won"
        case .lost:         return "Lost"
        }
    }

    var systemImage: String {
        switch self {
        case .new:          return "sparkle"
        case .contacted:    return "bubble.left.and.bubble.right.fill"
        case .proposalSent: return "paperplane.fill"
        case .won:          return "checkmark.seal.fill"
        case .lost:         return "xmark.circle.fill"
        }
    }

    var state: SemanticState {
        switch self {
        case .new:          return .info
        case .contacted:    return .caution
        case .proposalSent: return .alert
        case .won:          return .good
        case .lost:         return .neutral
        }
    }

    /// Stages a lead can still be worked in.
    var isOpen: Bool { self == .new || self == .contacted || self == .proposalSent }

    static let openStages: [LeadStage] = [.new, .contacted, .proposalSent]
}

/// Value snapshot of a lead for pure pipeline math.
struct LeadSummary: Equatable {
    var id: UUID
    var stage: LeadStage
    var value: Double
    var lastContact: Date?
    var createdAt: Date
}

enum LeadPipeline {
    /// A prospect with no explicit stage yet counts as New, so anyone already marked
    /// "Prospect" shows up in the pipeline. Anyone who isn't a prospect and has no
    /// stage is an ordinary client (nil).
    static func effectiveStage(raw: String, status: ClientStatus) -> LeadStage? {
        if let stage = LeadStage(rawValue: raw) { return stage }
        return status == .prospect ? .new : nil
    }

    /// The next step forward (Proposal sent → Won). Won/Lost are terminal.
    static func advance(_ stage: LeadStage) -> LeadStage? {
        switch stage {
        case .new:          return .contacted
        case .contacted:    return .proposalSent
        case .proposalSent: return .won
        case .won, .lost:   return nil
        }
    }

    /// Winning a lead makes them a real client; losing one parks them as inactive
    /// (their history is kept, never deleted).
    static func status(for stage: LeadStage) -> ClientStatus {
        switch stage {
        case .new, .contacted, .proposalSent: return .prospect
        case .won:                            return .active
        case .lost:                           return .inactive
        }
    }

    struct Summary: Equatable {
        var countByStage: [LeadStage: Int]
        var openCount: Int
        var openValue: Double
        var winRate: Double?     // won / (won + lost); nil until one is closed
    }

    static func summarize(_ leads: [LeadSummary]) -> Summary {
        var counts: [LeadStage: Int] = [:]
        var openValue = 0.0
        for lead in leads {
            counts[lead.stage, default: 0] += 1
            if lead.stage.isOpen { openValue += lead.value }
        }
        let won = counts[.won] ?? 0
        let lost = counts[.lost] ?? 0
        let openCount = LeadStage.openStages.reduce(0) { $0 + (counts[$1] ?? 0) }
        return Summary(
            countByStage: counts,
            openCount: openCount,
            openValue: openValue,
            winRate: (won + lost) > 0 ? Double(won) / Double(won + lost) : nil
        )
    }

    /// Open leads nobody has touched in `days` days (never-contacted leads are measured
    /// from when they were added), longest-neglected first.
    static func staleLeads(_ leads: [LeadSummary], days: Int = 7, now: Date = .now, calendar: Calendar = .current) -> [UUID] {
        var stale: [(id: UUID, days: Int)] = []
        for lead in leads where lead.stage.isOpen {
            let reference = lead.lastContact ?? lead.createdAt
            let idle = ClientActivity.daysSince(reference, now: now, calendar: calendar) ?? 0
            if idle >= days { stale.append((lead.id, idle)) }
        }
        return stale.sorted { $0.days > $1.days }.map { $0.id }
    }
}
