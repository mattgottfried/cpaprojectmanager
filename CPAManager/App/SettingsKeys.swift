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

    /// Days without logged contact before an active client with open work shows as "gone quiet".
    static let quietThresholdDays = "quietThresholdDays"

    /// Billing increment in minutes (0 = exact); see `TimeRounding`.
    static let timeRoundingMinutes = "timeRoundingMinutes"
    /// Notify if a timer is still running after this many hours (0 = never).
    static let timerReminderHours = "timerReminderHours"
    /// Your secure client-upload page (e.g. an Encyro page); inserted into requests and emails.
    static let uploadPageURL = "uploadPageURL"
    /// Days after sending for signature before Today nudges you.
    static let signatureChaseDays = "signatureChaseDays"
    /// Set once the first-run walkthrough has been finished or skipped.
    static let hasOnboarded = "hasOnboarded"

    // Google integrations (non-secret preferences; tokens live in the Keychain).
    static let googleGmailEnabled = "googleGmailEnabled"
    static let googleGmailQuery = "googleGmailQuery"
    static let googleScheduleEnabled = "googleScheduleEnabled"
    static let googlePushEnabled = "googlePushEnabled"
    static let googleCalendarID = "googleCalendarID"
    static let googleLastGmailSync = "googleLastGmailSync"
    static let googleSyncedEvents = "googleSyncedEvents"
}
