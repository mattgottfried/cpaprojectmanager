import Foundation

/// Business-day date math mirroring the firm's existing Shortcuts automations, so
/// dates computed in-app land on the same days the Reminders-based workflow would.
enum DateMath {
    /// Sunday/Saturday landing dates are nudged forward by 2 days — matches the
    /// "New Tax Return" Shortcut's weekend adjustment (including its Sun -> Tue
    /// behavior, rather than the more obvious Sun -> Mon).
    static func skippingWeekend(_ date: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sun ... 7 = Sat
        guard weekday == 1 || weekday == 7 else { return date }
        return calendar.date(byAdding: .day, value: 2, to: date) ?? date
    }

    /// `days` out from `date`, then weekend-adjusted. Used for intake due dates
    /// (received + 9 days, per the "New Tax Return" Shortcut).
    static func addingDaysWeekendAdjusted(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        let raw = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return skippingWeekend(raw, calendar: calendar)
    }

    /// The firm's "advance" step: +3 days normally, +5 when today is Wed/Thu/Fri —
    /// matches the "Auto Advance" and "Take Off Hold" Shortcuts.
    static func advancedDueDate(from date: Date = .now, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sun ... 7 = Sat
        let offset = (weekday == 4 || weekday == 5 || weekday == 6) ? 5 : 3
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }
}
