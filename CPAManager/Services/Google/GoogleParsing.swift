import Foundation

// Pure parsing/planning for the Google integrations. No networking, no SwiftData —
// everything here is unit-tested with canned API responses.

// MARK: - Gmail

struct GmailListResponse: Decodable {
    struct Ref: Decodable {
        let id: String
        let threadId: String?
    }
    let messages: [Ref]?
}

struct GmailMessage: Decodable {
    struct Header: Decodable {
        let name: String
        let value: String
    }
    struct Payload: Decodable {
        let headers: [Header]?
    }
    let id: String
    let threadId: String?
    let snippet: String?
    /// Milliseconds since the epoch, as a string.
    let internalDate: String?
    let payload: Payload?
}

struct ParsedEmail: Equatable {
    var id: String
    var threadID: String
    var subject: String
    var senderName: String
    var senderEmail: String
    var date: Date?
    var snippet: String
}

enum GmailParsing {
    static let defaultQuery = "is:starred newer_than:30d"

    static func parse(_ message: GmailMessage) -> ParsedEmail {
        func header(_ name: String) -> String {
            message.payload?.headers?
                .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?
                .value ?? ""
        }
        let sender = senderParts(header("From"))
        let date = message.internalDate
            .flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000) }
        let subject = header("Subject").trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedEmail(
            id: message.id,
            threadID: message.threadId ?? message.id,
            subject: subject.isEmpty ? "(no subject)" : subject,
            senderName: sender.name,
            senderEmail: sender.email,
            date: date,
            snippet: (message.snippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// `"Dana Lee" <dana@acme.com>`, `Dana Lee <dana@acme.com>`, or a bare address.
    static func senderParts(_ header: String) -> (name: String, email: String) {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close else {
            return (trimmed.contains("@") ? "" : trimmed, trimmed.contains("@") ? trimmed : "")
        }
        let email = String(trimmed[trimmed.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        var name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
            name = String(name.dropFirst().dropLast())
        }
        return (name, email)
    }

    /// One line for the inbox: "Subject — Sender".
    static func inboxText(_ email: ParsedEmail) -> String {
        let who = email.senderName.isEmpty ? email.senderEmail : email.senderName
        return who.isEmpty ? email.subject : "\(email.subject) — \(who)"
    }

    static func externalID(_ messageID: String) -> String { "gmail:\(messageID)" }

    static func webLink(threadID: String) -> String {
        "https://mail.google.com/mail/u/0/#all/\(threadID)"
    }

    /// Case-insensitive match of a sender address to a known client email.
    static func matchClientIndex(senderEmail: String, clientEmails: [String]) -> Int? {
        let target = senderEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard !target.isEmpty else { return nil }
        return clientEmails.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == target }
    }

    /// Search string for the Gmail API; falls back to the default when blank.
    static func effectiveQuery(_ user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultQuery : trimmed
    }
}

// MARK: - Calendar (read)

struct CalendarEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var location: String
    var link: URL?
}

struct GoogleEventsResponse: Decodable {
    struct When: Decodable {
        let dateTime: String?
        let date: String?
    }
    struct Item: Decodable {
        let id: String
        let summary: String?
        let status: String?
        let location: String?
        let htmlLink: String?
        let start: When?
        let end: When?
    }
    let items: [Item]?
}

struct GoogleCalendarListResponse: Decodable {
    struct Entry: Decodable {
        let id: String
        let summary: String?
        let primary: Bool?
        let accessRole: String?
    }
    let items: [Entry]?
}

enum CalendarParsing {
    /// Events we created ourselves (due-date sync) carry this ID prefix, so the
    /// schedule view can leave them out instead of showing to-dos as meetings.
    static let ownEventPrefix = "cpa"

    static func events(from response: GoogleEventsResponse, calendar: Calendar = .current) -> [CalendarEvent] {
        var result: [CalendarEvent] = []
        for item in response.items ?? [] {
            if item.status == "cancelled" { continue }
            if item.id.hasPrefix(ownEventPrefix) { continue }
            guard let start = item.start, let parsed = parse(start, calendar: calendar) else { continue }
            let end = item.end.flatMap { parse($0, calendar: calendar)?.date }
            result.append(CalendarEvent(
                id: item.id,
                title: (item.summary?.isEmpty == false ? item.summary! : "(no title)"),
                start: parsed.date,
                end: end,
                isAllDay: parsed.allDay,
                location: item.location ?? "",
                link: item.htmlLink.flatMap(URL.init(string:))
            ))
        }
        return result.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    private static func parse(_ when: GoogleEventsResponse.When, calendar: Calendar) -> (date: Date, allDay: Bool)? {
        if let dateTime = when.dateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateTime) { return (date, false) }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTime) { return (date, false) }
            return nil
        }
        if let day = when.date {
            let parts = day.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            else { return nil }
            return (date, true)
        }
        return nil
    }

    /// Events that touch `day` (an all-day event ending the next morning still counts
    /// only for its own day, matching how Google reports exclusive all-day ends).
    static func events(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return events.filter { event in
            if event.isAllDay {
                let eventEnd = event.end ?? (calendar.date(byAdding: .day, value: 1, to: event.start) ?? event.start)
                return event.start < end && eventEnd > start
            }
            return event.start >= start && event.start < end
        }
    }
}

// MARK: - Calendar (push due dates)

/// Something dated in the app that should appear on the Google calendar as an all-day
/// event.
struct CalendarSyncItem: Equatable {
    var id: UUID
    var title: String
    var day: Date
    var notes: String

    /// Google lets us choose the event ID, which makes every write idempotent.
    /// IDs must be 5–1024 chars of base32hex (a–v, 0–9): a lowercased UUID without
    /// dashes qualifies, and the prefix marks it as ours.
    var eventID: String {
        CalendarParsing.ownEventPrefix + id.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Changes whenever anything visible about the event does.
    func signature(calendar: Calendar = .current) -> String {
        "\(title)|\(CalendarSyncPlanner.dayString(day, calendar: calendar))|\(notes)"
    }
}

enum CalendarSyncPlanner {
    struct Plan: Equatable {
        var creates: [CalendarSyncItem]
        var updates: [CalendarSyncItem]
        var deletes: [String]   // event IDs
    }

    /// Diffs what should be on the calendar against what we previously pushed
    /// (`synced` maps eventID → signature).
    static func plan(items: [CalendarSyncItem], synced: [String: String], calendar: Calendar = .current) -> Plan {
        var creates: [CalendarSyncItem] = []
        var updates: [CalendarSyncItem] = []
        var wanted = Set<String>()
        for item in items {
            wanted.insert(item.eventID)
            if let previous = synced[item.eventID] {
                if previous != item.signature(calendar: calendar) { updates.append(item) }
            } else {
                creates.append(item)
            }
        }
        let deletes = synced.keys.filter { !wanted.contains($0) }.sorted()
        return Plan(creates: creates, updates: updates, deletes: deletes)
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// JSON body for an all-day event. Marked transparent (doesn't block your time)
    /// and with no Google reminders — the app already notifies.
    static func eventBody(_ item: CalendarSyncItem, calendar: Calendar = .current, includeID: Bool) -> [String: Any] {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: item.day)) ?? item.day
        var body: [String: Any] = [
            "summary": item.title,
            "description": item.notes,
            "start": ["date": dayString(item.day, calendar: calendar)],
            "end": ["date": dayString(next, calendar: calendar)],
            "transparency": "transparent",
            "reminders": ["useDefault": false],
            // Revives the event if the user deleted it in Google (cancelled events keep their IDs).
            "status": "confirmed",
        ]
        if includeID { body["id"] = item.eventID }
        return body
    }
}
