import Foundation

/// Rounds tracked time up to a billing increment (e.g. 15 minutes).
enum TimeRounding {
    /// Increments offered in Settings; 0 = bill exact time.
    static let options: [Int] = [0, 6, 15, 30, 60]

    static func label(_ minutes: Int) -> String {
        switch minutes {
        case 0:  return "Exact time"
        case 60: return "1 hour"
        case 6:  return "6 minutes (0.1 hr)"
        default: return "\(minutes) minutes"
        }
    }

    /// The saved preference (works from any thread; safe before settings load).
    static var currentIncrement: Int {
        UserDefaults.standard.integer(forKey: SettingsKeys.timeRoundingMinutes)
    }

    /// Seconds rounded *up* to the next increment. Zero stays zero; any positive time
    /// bills at least one increment. Exact multiples are left alone.
    static func roundedSeconds(_ seconds: Double, incrementMinutes: Int) -> Double {
        guard seconds > 0 else { return 0 }
        guard incrementMinutes > 0 else { return seconds }
        let step = Double(incrementMinutes) * 60
        let blocks = (seconds / step - 1e-9).rounded(.up)
        return max(1, blocks) * step
    }

    static func hours(seconds: Double, incrementMinutes: Int) -> Double {
        roundedSeconds(seconds, incrementMinutes: incrementMinutes) / 3600
    }
}

/// When to nudge about a timer that may have been left running.
enum TimerReminderPlan {
    static let hourOptions: [Int] = [0, 1, 2, 3, 4, 6]

    /// Nil when reminders are off.
    static func fireDate(startedAt: Date, afterHours hours: Int) -> Date? {
        guard hours > 0 else { return nil }
        return startedAt.addingTimeInterval(Double(hours) * 3600)
    }
}
