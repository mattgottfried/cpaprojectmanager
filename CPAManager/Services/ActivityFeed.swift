import Foundation

/// One thing that happened, with the time it happened. Built from timestamps already
/// on the records (completed, created, received, paid…) — the feed doesn't need its
/// own change log.
struct ActivityEvent: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case taskDone, taskAdded, inbox, contact, payment, invoice, project, client, document, expense, time

        var systemImage: String {
            switch self {
            case .taskDone:  return "checkmark.circle.fill"
            case .taskAdded: return "plus.circle"
            case .inbox:     return "tray.and.arrow.down.fill"
            case .contact:   return "bubble.left.and.bubble.right.fill"
            case .payment:   return "banknote.fill"
            case .invoice:   return "doc.text.fill"
            case .project:   return "folder.fill"
            case .client:    return "person.crop.circle.badge.plus"
            case .document:  return "paperclip"
            case .expense:   return "creditcard.fill"
            case .time:      return "clock.fill"
            }
        }

        var state: SemanticState {
            switch self {
            case .taskDone, .payment: return .good
            case .contact, .inbox, .invoice, .client: return .info
            case .expense: return .caution
            default: return .neutral
            }
        }
    }

    var id: String
    var date: Date
    var kind: Kind
    var title: String
    var detail: String = ""
    /// Deep link to open when tapped, if there is one.
    var link: String? = nil
}

struct ActivitySection: Equatable, Identifiable {
    var day: Date
    var label: String
    var events: [ActivityEvent]
    var id: Date { day }
}

enum ActivityFeed {
    /// Groups events by day, newest day first and newest event first within a day.
    /// Events older than `days` (or in the future) are dropped.
    static func sections(
        _ events: [ActivityEvent],
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivitySection] {
        let today = calendar.startOfDay(for: now)
        guard let earliest = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }

        let recent = events.filter { $0.date >= earliest && $0.date < tomorrow }
        let byDay = Dictionary(grouping: recent) { calendar.startOfDay(for: $0.date) }

        return byDay.keys.sorted(by: >).map { day in
            ActivitySection(
                day: day,
                label: dayLabel(day, today: today, calendar: calendar),
                events: (byDay[day] ?? []).sorted { $0.date > $1.date }
            )
        }
    }

    static func dayLabel(_ day: Date, today: Date, calendar: Calendar = .current) -> String {
        let diff = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch diff {
        case 0:  return "Today"
        case 1:  return "Yesterday"
        default: return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }
}
