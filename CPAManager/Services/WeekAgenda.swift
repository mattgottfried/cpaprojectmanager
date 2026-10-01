import Foundation

// Pure logic for the "due this week" views: the This Week widget and the Siri answer. Looks at
// open, unblocked tasks due from today through the next six days. No SwiftData. Unit-tested.

struct WeekTaskInput: Equatable {
    var id: UUID
    var title: String
    var subtitle: String
    var dueDate: Date?
    var isDone: Bool
    var isBlocked: Bool
    var isHigh: Bool
    var snoozedUntil: Date?
}

struct WeekEntry: Equatable, Identifiable {
    var id: UUID
    var title: String
    var subtitle: String
    var dueDate: Date
    var isHigh: Bool
}

enum WeekAgenda {
    /// Tasks due today through `days - 1` days ahead, earliest first (high priority first within a
    /// day). Done, blocked and still-snoozed tasks are left out.
    static func entries(_ tasks: [WeekTaskInput], days: Int = 7, now: Date = .now, calendar: Calendar = .current) -> [WeekEntry] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: max(1, days), to: start) else { return [] }
        return tasks.compactMap { task -> WeekEntry? in
            guard !task.isDone, !task.isBlocked, let due = task.dueDate else { return nil }
            if let snoozed = task.snoozedUntil, calendar.startOfDay(for: snoozed) > start { return nil }
            let day = calendar.startOfDay(for: due)
            guard day >= start, day < end else { return nil }
            return WeekEntry(id: task.id, title: task.title, subtitle: task.subtitle, dueDate: due, isHigh: task.isHigh)
        }
        .sorted { a, b in
            let dayA = calendar.startOfDay(for: a.dueDate), dayB = calendar.startOfDay(for: b.dueDate)
            if dayA != dayB { return dayA < dayB }
            if a.isHigh != b.isHigh { return a.isHigh }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// Open, unblocked tasks whose due day is before today.
    static func overdueCount(_ tasks: [WeekTaskInput], now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        return tasks.filter { task in
            guard !task.isDone, !task.isBlocked, let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) < start
        }.count
    }

    /// "today", "tomorrow", then the short weekday ("Fri").
    static func dayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

extension Briefing {
    /// "2 overdue. 5 due this week: Call Smith (today), Send 1099s (Wed), Review (Fri) and 2 more."
    static func week(overdue: Int, entries: [WeekEntry], now: Date = .now, calendar: Calendar = .current, listed: Int = 3) -> String {
        var sentences: [String] = []
        if overdue > 0 { sentences.append("\(overdue) overdue.") }
        if entries.isEmpty {
            sentences.append("Nothing else due this week.")
        } else {
            let shown = entries.prefix(listed).map { "\($0.title) (\(WeekAgenda.dayLabel($0.dueDate, now: now, calendar: calendar)))" }
            var line = "\(entries.count) due this week: " + shown.joined(separator: ", ")
            let more = entries.count - shown.count
            if more > 0 { line += " and \(more) more" }
            sentences.append(line + ".")
        }
        return sentences.joined(separator: " ")
    }
}
