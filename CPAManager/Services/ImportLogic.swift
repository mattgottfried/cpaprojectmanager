import Foundation

// Pure CSV parsing and mapping for importing clients and time (spreadsheets, or a
// QuickBooks customer-list export). Nothing here touches the store.

enum CSVParser {
    /// RFC 4180-style parsing: quoted fields, doubled quotes, commas and line breaks
    /// inside quotes, LF or CRLF row ends, and a leading byte-order mark. Blank rows are
    /// dropped.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        var chars = Array(text.unicodeScalars)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field); field = ""
                case "\n":
                    row.append(field); field = ""
                    rows.append(row); row = []
                case "\r":
                    break   // the "\n" of a CRLF ends the row; a lone "\r" is ignored
                default:
                    field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }
}

struct ImportColumns {
    private let index: [String: Int]

    /// Maps each wanted field to the first header that matches one of its aliases
    /// (case/space/punctuation-insensitive).
    init(headers: [String], aliases: [String: [String]]) {
        var map: [String: Int] = [:]
        let normalized = headers.map(ImportColumns.normalize)
        for (field, names) in aliases {
            for name in names {
                if let position = normalized.firstIndex(of: ImportColumns.normalize(name)) {
                    map[field] = position
                    break
                }
            }
        }
        index = map
    }

    func has(_ field: String) -> Bool { index[field] != nil }

    func value(_ field: String, in row: [String]) -> String {
        guard let position = index[field], position < row.count else { return "" }
        return row[position].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalize(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Clients

struct ClientImportRecord: Equatable {
    var name: String
    var company: String
    var email: String
    var phone: String
    var entityTypeRaw: String
    var tags: [String]
    var notes: String
}

struct ImportSkip: Equatable {
    var row: Int          // 1-based, counting the header as row 1
    var reason: String
}

struct ClientImportPlan: Equatable {
    var records: [ClientImportRecord] = []
    var skipped: [ImportSkip] = []
    var missingRequiredColumn: String? = nil
}

enum ClientImport {
    static let aliases: [String: [String]] = [
        "name": ["name", "customer", "customer name", "display name", "full name", "client", "client name", "contact", "contact name"],
        "company": ["company", "company name", "business", "business name", "organization"],
        "email": ["email", "e-mail", "email address", "main email", "primary email"],
        "phone": ["phone", "phone number", "phone numbers", "main phone", "mobile", "telephone", "cell"],
        "entity": ["entity", "entity type", "type", "tax entity", "return type"],
        "tags": ["tags", "tag", "labels"],
        "notes": ["notes", "note", "memo", "comments"],
    ]

    /// Free text → an `EntityType` raw value ("S Corp", "1120-S", "individual"…).
    static func entityTypeRaw(from text: String) -> String {
        let t = text.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !t.isEmpty else { return EntityType.individual1040.rawValue }
        if t.contains("1120s") || t.contains("scorp") { return EntityType.sCorp1120S.rawValue }
        if t.contains("1120") || t.contains("ccorp") || t.contains("corporation") { return EntityType.cCorp1120.rawValue }
        if t.contains("1065") || t.contains("partnership") || t.contains("llc") { return EntityType.partnership1065.rawValue }
        if t.contains("1041") || t.contains("trust") || t.contains("estate") { return EntityType.trust1041.rawValue }
        if t.contains("990") || t.contains("nonprofit") { return EntityType.nonProfit990.rawValue }
        if t.contains("1040") || t.contains("individual") || t.contains("personal") { return EntityType.individual1040.rawValue }
        return EntityType.other.rawValue
    }

    /// Builds the import plan. Rows are skipped when they have no name (or company), or when
    /// the email/name already exists in the app or earlier in the file.
    static func plan(rows: [[String]], existingEmails: Set<String>, existingNames: Set<String>) -> ClientImportPlan {
        var plan = ClientImportPlan()
        guard let headers = rows.first else { plan.missingRequiredColumn = "the header row"; return plan }
        let columns = ImportColumns(headers: headers, aliases: aliases)
        guard columns.has("name") || columns.has("company") else {
            plan.missingRequiredColumn = "a Name (or Company) column"
            return plan
        }

        var emails = existingEmails
        var names = existingNames
        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            var name = columns.value("name", in: row)
            let company = columns.value("company", in: row)
            if name.isEmpty { name = company }
            guard !name.isEmpty else {
                plan.skipped.append(ImportSkip(row: rowNumber, reason: "No name"))
                continue
            }
            let email = columns.value("email", in: row).lowercased()
            let nameKey = name.lowercased()
            if !email.isEmpty, emails.contains(email) {
                plan.skipped.append(ImportSkip(row: rowNumber, reason: "Email already exists"))
                continue
            }
            if email.isEmpty, names.contains(nameKey) {
                plan.skipped.append(ImportSkip(row: rowNumber, reason: "Name already exists"))
                continue
            }
            if !email.isEmpty { emails.insert(email) }
            names.insert(nameKey)

            let tags = columns.value("tags", in: row)
                .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            plan.records.append(ClientImportRecord(
                name: name, company: name == company ? "" : company, email: email,
                phone: columns.value("phone", in: row),
                entityTypeRaw: entityTypeRaw(from: columns.value("entity", in: row)),
                tags: tags, notes: columns.value("notes", in: row)
            ))
        }
        return plan
    }
}

// MARK: - Time

struct TimeImportRecord: Equatable {
    var date: Date
    var clientName: String
    var projectTitle: String
    var hours: Double
    var rate: Double?
    var notes: String
    var isBillable: Bool
}

struct TimeImportPlan: Equatable {
    var records: [TimeImportRecord] = []
    var skipped: [ImportSkip] = []
    var missingRequiredColumn: String? = nil
}

enum TimeImport {
    static let aliases: [String: [String]] = [
        "date": ["date", "day", "start date", "work date"],
        "client": ["client", "customer", "client name"],
        "project": ["project", "job", "engagement", "task"],
        "hours": ["hours", "duration", "time", "hrs", "quantity"],
        "rate": ["rate", "hourly rate", "billing rate"],
        "notes": ["notes", "note", "description", "memo"],
        "billable": ["billable", "is billable"],
    ]

    /// "1.5", "1,5", "1:30" or "1h 30m" → hours. Nil if it isn't a positive duration.
    static func hours(from text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        if t.contains(":") {
            let parts = t.split(separator: ":").compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            let value = parts[0] + parts[1] / 60
            return value > 0 ? value : nil
        }
        if t.contains("h") || t.contains("m") {
            var total = 0.0
            var number = ""
            for ch in t {
                if ch.isNumber || ch == "." { number.append(ch) }
                else if ch == "h" { total += (Double(number) ?? 0); number = "" }
                else if ch == "m" { total += (Double(number) ?? 0) / 60; number = "" }
            }
            return total > 0 ? total : nil
        }
        let value = Double(t.replacingOccurrences(of: ",", with: "."))
        return (value ?? 0) > 0 ? value : nil
    }

    static func parseDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        for format in ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "MM-dd-yyyy", "MMM d, yyyy", "MMMM d, yyyy"] {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: t) { return date }
        }
        return nil
    }

    static func plan(rows: [[String]], calendar: Calendar = .current) -> TimeImportPlan {
        var plan = TimeImportPlan()
        guard let headers = rows.first else { plan.missingRequiredColumn = "the header row"; return plan }
        let columns = ImportColumns(headers: headers, aliases: aliases)
        guard columns.has("date") else { plan.missingRequiredColumn = "a Date column"; return plan }
        guard columns.has("hours") else { plan.missingRequiredColumn = "an Hours column"; return plan }

        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            guard let date = parseDate(columns.value("date", in: row), calendar: calendar) else {
                plan.skipped.append(ImportSkip(row: rowNumber, reason: "Unreadable date"))
                continue
            }
            guard let hours = hours(from: columns.value("hours", in: row)) else {
                plan.skipped.append(ImportSkip(row: rowNumber, reason: "Unreadable hours"))
                continue
            }
            let rateText = columns.value("rate", in: row).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            let billableText = columns.value("billable", in: row).lowercased()
            plan.records.append(TimeImportRecord(
                date: date,
                clientName: columns.value("client", in: row),
                projectTitle: columns.value("project", in: row),
                hours: hours,
                rate: Double(rateText),
                notes: columns.value("notes", in: row),
                isBillable: !["no", "false", "n", "0"].contains(billableText)
            ))
        }
        return plan
    }
}
