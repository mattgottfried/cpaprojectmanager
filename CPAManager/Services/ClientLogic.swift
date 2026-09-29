import Foundation

// Pure, unit-tested helpers behind the CRM features: tags, filters, and how long it
// has been since a client was contacted.

/// Tags are stored on a client as one comma-separated string (CloudKit-friendly, no
/// extra model). These helpers keep them normalized.
enum TagSet {
    struct TagCount: Equatable {
        var tag: String
        var count: Int
    }

    static func normalize(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        let words = t.lowercased().split(whereSeparator: { $0.isWhitespace })
        return words.joined(separator: " ")
    }

    /// "Referral, #bookkeeping ,referral" → ["referral", "bookkeeping"].
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in raw.split(separator: ",") {
            let tag = normalize(String(piece))
            if !tag.isEmpty, seen.insert(tag).inserted { result.append(tag) }
        }
        return result
    }

    static func encode(_ tags: [String]) -> String {
        parse(tags.joined(separator: ",")).joined(separator: ", ")
    }

    /// Every tag in use with how many clients carry it, most-used first.
    static func counts(_ lists: [[String]]) -> [TagCount] {
        var counts: [String: Int] = [:]
        for list in lists {
            for tag in Set(list) { counts[tag, default: 0] += 1 }
        }
        return counts
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }
}

/// Value snapshot of a client for filtering, decoupled from SwiftData.
struct ClientSummary: Equatable {
    var id: UUID
    var displayName: String
    var company: String
    var email: String
    var status: ClientStatus
    var entityType: EntityType
    var tags: [String]
    var openWorkCount: Int
}

struct ClientFilter: Equatable {
    var status: ClientStatus? = nil
    var entityType: EntityType? = nil
    var tag: String? = nil
    var onlyWithOpenWork: Bool = false
    var search: String = ""

    /// True when nothing narrows the list (search excluded — it isn't saved).
    var isEmpty: Bool {
        status == nil && entityType == nil && tag == nil && !onlyWithOpenWork
    }

    var activeCount: Int {
        [status != nil, entityType != nil, tag != nil, onlyWithOpenWork].filter { $0 }.count
    }

    func matches(_ client: ClientSummary) -> Bool {
        if let status, client.status != status { return false }
        if let entityType, client.entityType != entityType { return false }
        if let tag, !client.tags.contains(TagSet.normalize(tag)) { return false }
        if onlyWithOpenWork, client.openWorkCount == 0 { return false }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hit = client.displayName.localizedCaseInsensitiveContains(q)
                || client.company.localizedCaseInsensitiveContains(q)
                || client.email.localizedCaseInsensitiveContains(q)
                || client.tags.contains { $0.localizedCaseInsensitiveContains(q) }
            if !hit { return false }
        }
        return true
    }
}

enum ClientActivity {
    static func daysSince(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
    }

    /// "Today", "Yesterday", "5 days ago", "3 weeks ago", "4 months ago".
    static func lastContactLabel(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let days = daysSince(date, now: now, calendar: calendar) else { return "No contact logged" }
        switch days {
        case 0:        return "Today"
        case 1:        return "Yesterday"
        case 2...13:   return "\(days) days ago"
        case 14...59:  return "\(days / 7) weeks ago"
        default:       return "\(max(2, days / 30)) months ago"
        }
    }
}

/// Quick choices for "remind me to follow up".
enum FollowUpPreset: String, CaseIterable, Identifiable {
    case tomorrow, inAWeek, inTwoWeeks, inAMonth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tomorrow:    return "Tomorrow"
        case .inAWeek:     return "In a week"
        case .inTwoWeeks:  return "In 2 weeks"
        case .inAMonth:    return "In a month"
        }
    }

    func date(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let result: Date?
        switch self {
        case .tomorrow:    result = calendar.date(byAdding: .day, value: 1, to: today)
        case .inAWeek:     result = calendar.date(byAdding: .day, value: 7, to: today)
        case .inTwoWeeks:  result = calendar.date(byAdding: .day, value: 14, to: today)
        case .inAMonth:    result = calendar.date(byAdding: .month, value: 1, to: today)
        }
        return result ?? today
    }
}

extension ClientActivity {
    /// Logging a contact clears a follow-up that is due (today or earlier); a follow-up
    /// set for a future day is left alone.
    static func shouldClearFollowUp(_ followUp: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let followUp else { return false }
        return calendar.startOfDay(for: followUp) <= calendar.startOfDay(for: now)
    }
}

/// Weekly-review scheduling and "who have I lost touch with" logic.
enum WeeklyReviewPlanner {
    struct QuietInput: Equatable {
        var id: UUID
        var lastContact: Date?
        var createdAt: Date
        var hasOpenWork: Bool
        var isActive: Bool
        /// A future follow-up already on the calendar means "I've got this" — don't nag.
        var followUpDate: Date? = nil
    }

    static func isDue(lastReview: Date?, now: Date = .now, calendar: Calendar = .current, intervalDays: Int = 7) -> Bool {
        guard let lastReview else { return true }
        guard let days = ClientActivity.daysSince(lastReview, now: now, calendar: calendar) else { return true }
        return days >= intervalDays
    }

    /// Active clients with open work and no logged contact for `thresholdDays`, longest
    /// silence first. A client with no logged contact at all is measured from when they
    /// were added, so a brand-new client isn't flagged immediately.
    static func quietClients(
        _ inputs: [QuietInput],
        now: Date = .now,
        calendar: Calendar = .current,
        thresholdDays: Int = 14
    ) -> [UUID] {
        var quiet: [(id: UUID, days: Int)] = []
        let today = calendar.startOfDay(for: now)
        for input in inputs where input.isActive && input.hasOpenWork {
            if let followUp = input.followUpDate, calendar.startOfDay(for: followUp) > today { continue }
            let reference = input.lastContact ?? input.createdAt
            let days = ClientActivity.daysSince(reference, now: now, calendar: calendar) ?? 0
            if days >= thresholdDays { quiet.append((input.id, days)) }
        }
        return quiet.sorted { $0.days > $1.days }.map { $0.id }
    }
}

/// "Side business hours": when the user wants to be nudged. Outside these hours the
/// app stays quiet; due-date alerts are moved to the start of the window.
struct FocusHours: Equatable {
    var isEnabled = false
    var startHour = 18
    var endHour = 22
    var weekendsAllDay = true

    func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Is `date` inside the user's working window? Always true when disabled.
    func isWithin(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return true }
        if weekendsAllDay && isWeekend(date, calendar: calendar) { return true }
        let hour = calendar.component(.hour, from: date)
        if startHour < endHour { return hour >= startHour && hour < endHour }
        return hour >= startHour || hour < endHour   // window wraps past midnight
    }

    /// Hour at which to fire a due-date reminder for tasks due on `day`.
    func alertHour(on day: Date, defaultHour: Int, calendar: Calendar = .current) -> Int {
        guard isEnabled else { return defaultHour }
        if weekendsAllDay && isWeekend(day, calendar: calendar) { return defaultHour }
        return startHour
    }

    static func load(defaults: UserDefaults = .standard) -> FocusHours {
        var focus = FocusHours()
        focus.isEnabled = defaults.bool(forKey: SettingsKeys.focusEnabled)
        if let start = defaults.object(forKey: SettingsKeys.focusStartHour) as? Int { focus.startHour = start }
        if let end = defaults.object(forKey: SettingsKeys.focusEndHour) as? Int { focus.endHour = end }
        if let weekends = defaults.object(forKey: SettingsKeys.focusWeekends) as? Bool { focus.weekendsAllDay = weekends }
        return focus
    }

    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        let suffix = h < 12 ? "AM" : "PM"
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(suffix)"
    }
}
