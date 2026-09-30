import Foundation

/// Which block of the Today screen an entry lands in.
enum TodaySection: String, CaseIterable, Identifiable {
    case overdue, today, next, comingUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Today"
        case .next:     return "Next up"
        case .comingUp: return "Coming up"
        }
    }

    var systemImage: String {
        switch self {
        case .overdue:  return "exclamationmark.triangle.fill"
        case .today:    return "sun.max.fill"
        case .next:     return "arrow.right.circle.fill"
        case .comingUp: return "calendar"
        }
    }

    var color: SemanticState {
        switch self {
        case .overdue:  return .bad
        case .today:    return .alert
        case .next:     return .info
        case .comingUp: return .neutral
        }
    }
}

/// Platform-free color meaning, mapped to real colors by `Theme` in the UI layer so
/// this file stays testable and the mapping stays in one place.
enum SemanticState { case good, caution, bad, alert, info, neutral }

/// A flattened view of a task or project for planning — decouples the planner from
/// SwiftData so it can be unit-tested with plain values.
struct PlannerItem: Equatable {
    var id: UUID
    var dueDate: Date?
    var snoozedUntil: Date?
    var isDone: Bool
    var isNextAction: Bool
    /// Waiting on another open task; hidden like a snoozed item.
    var isBlocked: Bool = false
}

struct TodayPlan: Equatable {
    var sections: [TodaySection: [UUID]]
    var snoozedCount: Int
    var blockedCount: Int = 0

    func ids(_ section: TodaySection) -> [UUID] { sections[section] ?? [] }
    var isEmpty: Bool { sections.values.allSatisfy(\.isEmpty) }
}

enum TodayPlanner {
    /// Sorts every open item into Overdue / Today / Next up / Coming up.
    /// - Undated items appear only if flagged `isNextAction`.
    /// - Items snoozed to a future day are hidden and counted.
    /// - Dated items further out than `comingUpDays` are left to the Deadlines tab.
    static func plan(
        _ items: [PlannerItem],
        now: Date = .now,
        calendar: Calendar = .current,
        comingUpDays: Int = 7
    ) -> TodayPlan {
        let today = calendar.startOfDay(for: now)
        var buckets: [TodaySection: [(index: Int, sortDate: Date, id: UUID)]] = [:]
        var snoozed = 0
        var blocked = 0

        for (index, item) in items.enumerated() {
            if item.isDone { continue }

            if item.isBlocked {
                blocked += 1
                continue
            }

            if let until = item.snoozedUntil, calendar.startOfDay(for: until) > today {
                snoozed += 1
                continue
            }

            let section: TodaySection
            let sortDate: Date
            if let due = item.dueDate {
                let day = calendar.startOfDay(for: due)
                sortDate = day
                if day < today {
                    section = .overdue
                } else if day == today {
                    section = .today
                } else {
                    let days = calendar.dateComponents([.day], from: today, to: day).day ?? Int.max
                    guard days <= comingUpDays else { continue }
                    section = .comingUp
                }
            } else if item.isNextAction {
                section = .next
                sortDate = .distantFuture
            } else {
                continue
            }
            buckets[section, default: []].append((index, sortDate, item.id))
        }

        var sections: [TodaySection: [UUID]] = [:]
        for (section, entries) in buckets {
            sections[section] = entries
                .sorted { ($0.sortDate, $0.index) < ($1.sortDate, $1.index) }
                .map { $0.id }
        }
        return TodayPlan(sections: sections, snoozedCount: snoozed, blockedCount: blocked)
    }

    /// The day a task should reappear after a snooze choice.
    static func snoozeDate(_ option: SnoozeOption, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        switch option {
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .thisWeekend:
            // The coming Saturday.
            var day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            while calendar.component(.weekday, from: day) != 7 {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return day
        case .nextWeek:
            // Next Monday.
            var day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            while calendar.component(.weekday, from: day) != 2 {
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
            return day
        }
    }
}

enum SnoozeOption: String, CaseIterable, Identifiable {
    case tomorrow, thisWeekend, nextWeek
    var id: String { rawValue }
    var label: String {
        switch self {
        case .tomorrow:    return "Tomorrow"
        case .thisWeekend: return "This weekend"
        case .nextWeek:    return "Next week"
        }
    }
    var systemImage: String {
        switch self {
        case .tomorrow:    return "sunrise.fill"
        case .thisWeekend: return "figure.walk"
        case .nextWeek:    return "calendar.badge.clock"
        }
    }
}
