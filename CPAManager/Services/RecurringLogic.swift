import Foundation

// Pure recurring-work helpers: titles, upcoming-occurrence preview, end dates. Unit-tested.

enum RecurringNaming {
    static let defaultPattern = "{name} - {period}"

    /// Tokens: {name} {client} {period} {month} {monthnum} {year} {quarter} {due} {frequency}.
    /// {period} is the period the work *covers* (a bookkeeping close due 6/27 covers 05/2026),
    /// formatted for the frequency; the other date tokens describe that same period.
    static func title(
        pattern: String,
        name: String,
        clientName: String,
        frequency: Frequency,
        due: Date,
        calendar: Calendar = .current
    ) -> String {
        let period = frequency.previousDate(before: due, calendar: calendar)
        func format(_ pattern: String, _ date: Date) -> String {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = pattern
            return f.string(from: date)
        }
        let quarter = ((calendar.component(.month, from: period) - 1) / 3) + 1

        let values: [String: String] = [
            "name": name,
            "client": clientName,
            "period": periodLabel(frequency: frequency, period: period, calendar: calendar),
            "month": format("MMMM", period),
            "monthnum": format("MM", period),
            "year": format("yyyy", period),
            "quarter": "Q\(quarter)",
            "due": format("MMM d, yyyy", due),
            "frequency": frequency.label,
        ]

        let raw = pattern.trimmingCharacters(in: .whitespaces).isEmpty ? defaultPattern : pattern
        var result = raw
        for (token, value) in values {
            result = result.replacingOccurrences(of: "{\(token)}", with: value, options: .caseInsensitive)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// The compact period label used by the default title ("05/2026", "Sep 8", "2025").
    static func periodLabel(frequency: Frequency, period: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        switch frequency {
        case .monthly, .quarterly: f.dateFormat = "MM/yyyy"
        case .weekly, .biweekly:   f.dateFormat = "MMM d"
        case .annually:            f.dateFormat = "yyyy"
        }
        return f.string(from: period)
    }
}

enum RecurrencePreview {
    /// The next `count` due dates starting at `start` (inclusive), following exactly the
    /// same stepping rules as the generator: advance one period, then skip a weekend if
    /// asked. Stops early at `endDate`.
    static func dates(
        startingAt start: Date,
        frequency: Frequency,
        count: Int,
        adjustForWeekends: Bool,
        endDate: Date? = nil,
        calendar: Calendar = .current
    ) -> [Date] {
        var result: [Date] = []
        var current = calendar.startOfDay(for: start)
        var guardCount = 0
        while result.count < count && guardCount < 500 {
            if let endDate, current > calendar.startOfDay(for: endDate) { break }
            result.append(current)
            var next = frequency.nextDate(after: current, calendar: calendar)
            if adjustForWeekends { next = DateMath.skippingWeekend(next, calendar: calendar) }
            if next <= current { break }
            current = next
            guardCount += 1
        }
        return result
    }

    /// True once the schedule has run past its end date.
    static func hasEnded(nextDue: Date, endDate: Date?, calendar: Calendar = .current) -> Bool {
        guard let endDate else { return false }
        return calendar.startOfDay(for: nextDue) > calendar.startOfDay(for: endDate)
    }
}
