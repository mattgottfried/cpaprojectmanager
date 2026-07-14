import Foundation

/// Formatting helpers shared by the app and the widget.
enum Format {
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Human, relative due-date label: "Today", "Tomorrow", "3 days ago", "Aug 12".
    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: .now)
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        switch days {
        case 0:            return "Today"
        case 1:            return "Tomorrow"
        case -1:           return "Yesterday"
        case 2...6:        return "in \(days) days"
        case -6 ... -2:    return "\(-days) days ago"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
            if sameYear { return shortDate.string(from: date) }
            return mediumDate.string(from: date)
        }
    }

    static func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// "2h 15m" — compact tracked-time label.
    static func hoursMinutes(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// "01:23:45" — running clock for the timer.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
