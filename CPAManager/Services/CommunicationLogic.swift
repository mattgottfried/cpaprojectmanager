import Foundation

// Pure logic for letters, email templates, rich notes and client occasions.

// MARK: - Merge fields

enum MergeFields {
    /// Tokens offered in the template editors, with what they fill in.
    static let tokens: [(token: String, label: String)] = [
        ("client", "Client name"),
        ("firstname", "First name"),
        ("company", "Company"),
        ("email", "Client email"),
        ("firm", "Your firm name"),
        ("date", "Today's date"),
        ("year", "Current year"),
        ("taxyear", "Tax year (prior year)"),
        ("fee", "Fee"),
        ("service", "Service"),
    ]

    /// Replaces `{token}` (case-insensitive) with values. Unknown tokens are left as
    /// typed so a typo is visible in the preview instead of silently vanishing.
    static func render(_ template: String, values: [String: String]) -> String {
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let close = template[index...].firstIndex(of: "}") {
                let raw = String(template[template.index(after: index)..<close])
                if let value = values[raw.lowercased()] {
                    result += value
                    index = template.index(after: close)
                    continue
                }
            }
            result.append(template[index])
            index = template.index(after: index)
        }
        return result
    }

    /// Tokens in `template` that `values` doesn't know about (for a warning).
    static func unknownTokens(in template: String, known: Set<String>) -> [String] {
        var found: [String] = []
        var index = template.startIndex
        while index < template.endIndex {
            if template[index] == "{", let close = template[index...].firstIndex(of: "}") {
                let raw = String(template[template.index(after: index)..<close]).lowercased()
                if !raw.isEmpty, !raw.contains(" "), !known.contains(raw), !found.contains(raw) { found.append(raw) }
                index = template.index(after: close)
            } else {
                index = template.index(after: index)
            }
        }
        return found
    }

    /// Standard values for a client. `fee` and `service` are optional context.
    static func values(
        clientName: String,
        company: String,
        email: String,
        firmName: String,
        now: Date = .now,
        fee: String = "",
        service: String = "",
        calendar: Calendar = .current
    ) -> [String: String] {
        let year = calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        let first = clientName.split(separator: " ").first.map(String.init) ?? clientName
        return [
            "client": clientName,
            "firstname": first,
            "company": company,
            "email": email,
            "firm": firmName,
            "date": formatter.string(from: now),
            "year": String(year),
            "taxyear": String(year - 1),
            "fee": fee,
            "service": service,
        ]
    }
}

// MARK: - mailto

enum MailtoBuilder {
    /// A `mailto:` URL with subject and body percent-encoded. Nil if there's no usable address.
    static func url(to address: String, subject: String, body: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return nil }
        // Percent-encode by hand: URLComponents leaves "&", "=" and "+" alone in query
        // values, which would corrupt a subject like "Q&A".
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        let path = trimmed.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@.-_+,"))) ?? trimmed
        return URL(string: "mailto:\(path)?subject=\(encode(subject))&body=\(encode(body))")
    }
}

// MARK: - Markdown notes

/// A tiny line-based Markdown subset for client notes: headings, bullets, checkboxes and
/// paragraphs. Notes stay a plain string, so older notes and CSV/backup keep working.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case bullet(text: String)
    case checkbox(checked: Bool, text: String)
    case paragraph(text: String)
    case blank
}

enum MarkdownBlocks {
    static func parse(_ text: String) -> [MarkdownBlock] {
        text.components(separatedBy: "\n").map(parseLine)
    }

    static func parseLine(_ line: String) -> MarkdownBlock {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }

        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix { $0 == "#" }
            let rest = trimmed.dropFirst(hashes.count)
            if hashes.count <= 3, rest.first == " " {
                return .heading(level: hashes.count, text: rest.trimmingCharacters(in: .whitespaces))
            }
        }
        for marker in ["- [ ] ", "* [ ] "] where trimmed.hasPrefix(marker) {
            return .checkbox(checked: false, text: String(trimmed.dropFirst(marker.count)))
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] "] where trimmed.hasPrefix(marker) {
            return .checkbox(checked: true, text: String(trimmed.dropFirst(marker.count)))
        }
        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return .bullet(text: String(trimmed.dropFirst(marker.count)))
        }
        return .paragraph(text: trimmed)
    }

    /// Flips the checkbox on `lineIndex` (no-op if that line isn't a checkbox).
    static func toggleCheckbox(in text: String, lineIndex: Int) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return text }
        let line = lines[lineIndex]
        if let range = line.range(of: "[ ]") {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[x]")
        } else if let range = line.range(of: "[x]") ?? line.range(of: "[X]") {
            lines[lineIndex] = line.replacingCharacters(in: range, with: "[ ]")
        } else {
            return text
        }
        return lines.joined(separator: "\n")
    }

    /// True when the text uses any Markdown structure worth rendering.
    static func hasStructure(_ text: String) -> Bool {
        parse(text).contains {
            switch $0 {
            case .heading, .bullet, .checkbox: return true
            default: return false
            }
        }
    }

    /// (checked, total) checkbox counts.
    static func checkboxProgress(_ text: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for block in parse(text) {
            if case .checkbox(let checked, _) = block {
                total += 1
                if checked { done += 1 }
            }
        }
        return (done, total)
    }
}

// MARK: - Occasions (birthdays & anniversaries)

enum OccasionKind: String, Codable {
    case birthday, anniversary

    var label: String { self == .birthday ? "Birthday" : "Anniversary" }
    var systemImage: String { self == .birthday ? "birthday.cake.fill" : "heart.fill" }
}

struct OccasionSource: Equatable {
    var clientID: UUID
    var clientName: String
    var birthday: Date?
    var anniversary: Date?
    var birthdayAckYear: Int
    var anniversaryAckYear: Int
    var isActive: Bool
}

struct Occasion: Equatable, Identifiable {
    var clientID: UUID
    var clientName: String
    var kind: OccasionKind
    /// The next (or today's) occurrence, at start of day.
    var date: Date
    var daysAway: Int
    /// Anniversary years ("5th anniversary"); nil for birthdays (age isn't shown).
    var years: Int?
    /// Already acknowledged this year.
    var acknowledged: Bool

    var id: String { "\(kind.rawValue):\(clientID.uuidString)" }
}

enum Occasions {
    /// Next occurrence of a yearly date on or after `now`. Feb 29 falls on Feb 28 in
    /// non-leap years.
    static func nextOccurrence(of date: Date, from now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.month, .day], from: date)
        let year = calendar.component(.year, from: today)
        for candidateYear in [year, year + 1] {
            if let candidate = resolve(month: parts.month ?? 1, day: parts.day ?? 1, year: candidateYear, calendar: calendar),
               candidate >= today {
                return candidate
            }
        }
        return today
    }

    private static func resolve(month: Int, day: Int, year: Int, calendar: Calendar) -> Date? {
        if let exact = calendar.date(from: DateComponents(year: year, month: month, day: day)),
           calendar.component(.month, from: exact) == month {
            return calendar.startOfDay(for: exact)
        }
        // Feb 29 in a non-leap year.
        return calendar.date(from: DateComponents(year: year, month: month, day: min(day, 28))).map { calendar.startOfDay(for: $0) }
    }

    /// Occasions happening within `withinDays` (0 = today only), soonest first.
    static func upcoming(
        _ sources: [OccasionSource],
        now: Date = .now,
        withinDays: Int = 7,
        calendar: Calendar = .current
    ) -> [Occasion] {
        let today = calendar.startOfDay(for: now)
        var result: [Occasion] = []
        for source in sources where source.isActive {
            for (kind, date, ackYear) in [
                (OccasionKind.birthday, source.birthday, source.birthdayAckYear),
                (OccasionKind.anniversary, source.anniversary, source.anniversaryAckYear),
            ] {
                guard let date else { continue }
                let next = nextOccurrence(of: date, from: now, calendar: calendar)
                let days = calendar.dateComponents([.day], from: today, to: next).day ?? 0
                guard days <= withinDays else { continue }
                let years: Int? = kind == .anniversary
                    ? calendar.component(.year, from: next) - calendar.component(.year, from: date)
                    : nil
                result.append(Occasion(
                    clientID: source.clientID,
                    clientName: source.clientName,
                    kind: kind,
                    date: next,
                    daysAway: days,
                    years: (years ?? 0) > 0 ? years : nil,
                    acknowledged: ackYear == calendar.component(.year, from: next)
                ))
            }
        }
        return result.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.clientName.localizedCaseInsensitiveCompare($1.clientName) == .orderedAscending
        }
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1):       suffix = "st"
        case (_, 2):       suffix = "nd"
        case (_, 3):       suffix = "rd"
        default:           suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    static func title(for occasion: Occasion) -> String {
        switch occasion.kind {
        case .birthday:
            return "\(occasion.clientName)'s birthday"
        case .anniversary:
            if let years = occasion.years { return "\(occasion.clientName) — \(ordinal(years)) year as a client" }
            return "\(occasion.clientName) — client anniversary"
        }
    }
}

// MARK: - Starter templates

enum TemplateStarters {
    struct Letter { var name: String; var kind: LetterKind; var body: String }
    struct Email { var name: String; var subject: String; var body: String }

    static let letters: [Letter] = [
        Letter(name: "Tax preparation engagement letter", kind: .engagement, body: """
        {date}

        {client}
        {company}

        Re: Engagement for {taxyear} tax preparation

        Dear {firstname},

        Thank you for choosing {firm}. This letter confirms the terms of our engagement to prepare your {taxyear} income tax returns.

        Scope. We will prepare your {taxyear} federal and applicable state income tax returns from the information you provide. We will not audit or verify that information, and we may ask for more documentation.

        Your responsibilities. You are responsible for providing complete and accurate records and for reviewing the returns before they are filed. Please keep your source documents.

        Fees. Our fee for this engagement is {fee}. Invoices are due on receipt.

        Timing. We will begin once we have received all requested documents. Returns are prepared in the order complete information arrives.

        If these terms are acceptable, please sign and return a copy of this letter.

        Sincerely,
        {firm}
        """),
        Letter(name: "Bookkeeping engagement letter", kind: .engagement, body: """
        {date}

        {client}
        {company}

        Re: Bookkeeping services

        Dear {firstname},

        This letter confirms that {firm} will provide {service} for {company} beginning {date}.

        We will record and categorize transactions and reconcile accounts from the bank and card statements and documents you provide, and deliver financial reports after each period closes. You remain responsible for the accuracy of the records you give us and for your business decisions.

        Fees. {fee}, invoiced monthly.

        Either of us may end this engagement with written notice.

        Sincerely,
        {firm}
        """),
        Letter(name: "Service proposal", kind: .proposal, body: """
        {date}

        Proposal for {client}
        Prepared by {firm}

        Dear {firstname},

        Thank you for the opportunity to propose {service}.

        What you get
        - A single point of contact for your tax and accounting questions
        - Work delivered on an agreed schedule
        - Clear, upfront pricing

        Investment
        {fee}

        Next steps
        Sign below and we will send an engagement letter and a short list of documents to get started.

        {firm}
        """),
    ]

    static let emails: [Email] = [
        Email(name: "Document request", subject: "Documents needed for your {taxyear} return", body: """
        Hi {firstname},

        To get your {taxyear} return started I need a few things from you. Reply to this email with the documents attached, or upload them when convenient.

        Thank you,
        {firm}
        """),
        Email(name: "Follow-up", subject: "Checking in", body: """
        Hi {firstname},

        Just checking in — do you have any updates, or anything I can help with?

        Thanks,
        {firm}
        """),
        Email(name: "Invoice reminder", subject: "Friendly reminder: invoice outstanding", body: """
        Hi {firstname},

        A quick reminder that your invoice is still outstanding. Let me know if you have any questions.

        Thank you,
        {firm}
        """),
        Email(name: "Birthday wishes", subject: "Happy birthday!", body: """
        Hi {firstname},

        Wishing you a very happy birthday!

        {firm}
        """),
        Email(name: "Work complete", subject: "Your {service} is complete", body: """
        Hi {firstname},

        Your {service} is complete. Please let me know if you have any questions.

        Thank you,
        {firm}
        """),
    ]
}
