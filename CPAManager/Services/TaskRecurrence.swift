import Foundation

/// How a standalone task repeats. Stored on `TaskItem` as a raw string.
enum RepeatRule: String, CaseIterable, Identifiable, Codable {
    case none, daily, weekdays, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     return "Never"
        case .daily:    return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly:   return "Every week"
        case .monthly:  return "Every month"
        case .yearly:   return "Every year"
        }
    }

    var systemImage: String {
        self == .none ? "arrow.forward" : "arrow.triangle.2.circlepath"
    }
}

/// Pure date math for repeating tasks. Unit-tested.
enum TaskRecurrence {
    /// The single next date after `date`, one period on.
    static func step(_ date: Date, rule: RepeatRule, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: date)
        switch rule {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: day)
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            // Explicit Sat/Sun (not locale-dependent `isDateInWeekend`) so behavior is stable.
            while [1, 7].contains(calendar.component(.weekday, from: next)) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: day)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: day)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: day)
        }
    }

    /// The next occurrence to schedule when a repeating task with due date `due` is
    /// completed at `now`. Keeps the original cadence (a weekly Friday task stays on
    /// Fridays) but never returns a date on or before today, so finishing a task that
    /// is weeks overdue doesn't spawn another overdue one.
    static func nextOccurrence(
        after due: Date,
        rule: RepeatRule,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        guard rule != .none else { return nil }
        let today = calendar.startOfDay(for: now)
        var candidate = calendar.startOfDay(for: due)
        for _ in 0..<2000 {
            guard let next = step(candidate, rule: rule, calendar: calendar) else { return nil }
            candidate = next
            if candidate > today { return candidate }
        }
        return nil
    }

    /// The next date (strictly after `now`'s day, or today if `includingToday`) that
    /// falls on `weekday` (1 = Sunday … 7 = Saturday).
    static func nextWeekday(_ weekday: Int, from now: Date = .now, includingToday: Bool = true, calendar: Calendar = .current) -> Date {
        var day = calendar.startOfDay(for: now)
        if !includingToday { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        for _ in 0..<7 {
            if calendar.component(.weekday, from: day) == weekday { return day }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }
}

/// Pulls a repeat phrase ("every week", "monthly", "every Friday") out of a typed line.
enum RecurrenceParser {
    struct Result: Equatable {
        var title: String
        var rule: RepeatRule
        /// Set for "every Friday": 1 = Sunday … 7 = Saturday.
        var weekday: Int?
    }

    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    private static let phrase =
        "(?:every\\s+(?:day|weekday|week|month|year|sunday|monday|tuesday|wednesday|thursday|friday|saturday)"
        + "|daily|weekdays|weekly|monthly|yearly|annually)"

    static func extract(from text: String) -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match at the end first (the natural way to type it), then at the start.
        for pattern in ["\\s*\\b\(phrase)\\s*$", "^\\s*\(phrase)\\b\\s*"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range, in: trimmed) else { continue }

            let matched = trimmed[range].lowercased().trimmingCharacters(in: .whitespaces)
            guard let interpreted = interpret(matched) else { continue }
            let (rule, weekday) = interpreted

            var title = trimmed
            title.removeSubrange(range)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }   // the whole line is just a phrase — keep it as text
            return Result(title: title, rule: rule, weekday: weekday)
        }
        return Result(title: trimmed, rule: .none, weekday: nil)
    }

    private static func interpret(_ phrase: String) -> (RepeatRule, Int?)? {
        if phrase.contains("weekday") { return (.weekdays, nil) }
        if phrase == "daily" || phrase.hasSuffix(" day") { return (.daily, nil) }
        if phrase == "weekly" || phrase.hasSuffix(" week") { return (.weekly, nil) }
        if phrase == "monthly" || phrase.hasSuffix(" month") { return (.monthly, nil) }
        if phrase == "yearly" || phrase == "annually" || phrase.hasSuffix(" year") { return (.yearly, nil) }
        for (index, name) in weekdayNames.enumerated() where phrase.hasSuffix(name) {
            return (.weekly, index + 1)
        }
        return nil
    }
}

/// One entry point for turning a typed line into a task: repeat phrase, then date.
enum QuickCapture {
    struct Result: Equatable {
        var title: String
        var dueDate: Date?
        var rule: RepeatRule
    }

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        let recurrence = RecurrenceParser.extract(from: raw)
        let dated = QuickAddParser.parse(recurrence.title, now: now, calendar: calendar)

        var due = dated.dueDate
        if due == nil, let weekday = recurrence.weekday {
            due = TaskRecurrence.nextWeekday(weekday, from: now, calendar: calendar)
        }
        if due == nil, recurrence.rule != .none {
            due = calendar.startOfDay(for: now)   // a repeating task needs an anchor day
        }
        return Result(title: dated.title, dueDate: due, rule: recurrence.rule)
    }
}
