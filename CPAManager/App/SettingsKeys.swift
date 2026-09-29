import Foundation

/// Keys for lightweight user preferences stored in `@AppStorage`.
enum SettingsKeys {
    static let defaultHourlyRate = "defaultHourlyRate"
    static let reminderHour = "reminderHour"
    static let firmName = "firmName"
    /// Second header line on printed routing sheets, e.g. "Certified Public
    /// Accountants  •  Ocoee, FL".
    static let firmTagline = "firmTagline"
    /// Third header line on printed routing sheets, e.g.
    /// "matt@example.com  •  407-555-0100".
    static let firmContact = "firmContact"

    /// "Side business hours" focus mode (see FocusHours).
    static let focusEnabled = "focusEnabled"
    static let focusStartHour = "focusStartHour"
    static let focusEndHour = "focusEndHour"
    static let focusWeekends = "focusWeekends"
    /// Date of the last completed weekly review.
    static let lastWeeklyReview = "lastWeeklyReview"
}
