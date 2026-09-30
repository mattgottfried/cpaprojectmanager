import Foundation

// Pure logic for the client folder structure in Google Drive: the template (numbered folders,
// which ones hold a year subfolder), where each kind of document is filed, how filed documents
// are named, how existing folders are recognised, and matching document requests to files that
// have landed in Drive. No networking, no SwiftData. Unit-tested.

/// What a document is, for deciding which folder it is filed in.
enum DocumentKind: String, CaseIterable, Codable, Identifiable {
    case upload        // scans, photos and files from the client
    case letter        // engagement letters, proposals, other letters
    case invoice
    case quote
    case deliverable   // finished returns and workpapers you hand back
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upload:      return "Scans, photos and client files"
        case .letter:      return "Letters and engagement letters"
        case .invoice:     return "Invoices"
        case .quote:       return "Quotes"
        case .deliverable: return "Finished returns and deliverables"
        case .other:       return "Everything else"
        }
    }

    /// Best guess for a file that was added before kinds existed (used by "Move to Google Drive").
    static func infer(filename: String, fileExtension: String) -> DocumentKind {
        let name = filename.lowercased()
        if name.contains("invoice") { return .invoice }
        if name.contains("quote") { return .quote }
        if name.contains("engagement") || name.contains("proposal") || name.contains("letter") { return .letter }
        if name.contains("return") && fileExtension.lowercased() == "pdf" && name.contains("filed") { return .deliverable }
        return .upload
    }
}

struct ClientFolderSlot: Codable, Equatable, Identifiable {
    var id: String
    /// The folder's name in Drive, e.g. "03 - Deliverables".
    var name: String
    /// Files inside get a subfolder per year (the tax year of the job), e.g. "2025".
    var yearFolders: Bool

    init(id: String = UUID().uuidString, name: String, yearFolders: Bool = false) {
        self.id = id; self.name = name; self.yearFolders = yearFolders
    }

    /// The leading number ("03" from "03 - Deliverables"), used to recognise the folder even if
    /// it was renamed slightly. Empty when the name doesn't start with digits.
    var code: String { FolderMatch.code(of: name) }
}

struct DriveFolderTemplate: Codable, Equatable {
    var slots: [ClientFolderSlot]
    /// `DocumentKind.rawValue` → slot id. A kind with no entry goes in the client's folder itself.
    var routes: [String: String]
    /// Tokens: {year} {client} {title} {date}.
    var namePattern: String

    static let standard = DriveFolderTemplate(
        slots: [
            ClientFolderSlot(id: "permanent", name: "00 - Permanent"),
            ClientFolderSlot(id: "intake", name: "01 - Intake"),
            ClientFolderSlot(id: "uploads", name: "02 - Source Documents (Client Uploads)"),
            ClientFolderSlot(id: "deliverables", name: "03 - Deliverables", yearFolders: true),
            ClientFolderSlot(id: "billing", name: "04 - Invoices & Engagements"),
        ],
        routes: [
            DocumentKind.upload.rawValue: "uploads",
            DocumentKind.letter.rawValue: "billing",
            DocumentKind.invoice.rawValue: "billing",
            DocumentKind.quote.rawValue: "billing",
            DocumentKind.deliverable.rawValue: "deliverables",
        ],
        namePattern: "{year} - {client} - {title}"
    )

    func slot(for kind: DocumentKind) -> ClientFolderSlot? {
        guard let id = routes[kind.rawValue], !id.isEmpty else { return nil }
        return slots.first { $0.id == id }
    }

    /// Folder names to walk from the client's folder to where a document goes (empty = the client folder).
    func path(for kind: DocumentKind, year: Int) -> [String] {
        guard let slot = slot(for: kind) else { return [] }
        return slot.yearFolders ? [slot.name, String(year)] : [slot.name]
    }

    /// Stored in settings as JSON; anything unreadable falls back to the standard layout.
    static func decode(_ json: String) -> DriveFolderTemplate {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(DriveFolderTemplate.self, from: data),
              !value.slots.isEmpty else { return .standard }
        return value
    }

    func encoded() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Slot names that would create the same folder twice, or are blank — shown in the editor.
    var problems: [String] {
        var found: [String] = []
        var seen = Set<String>()
        for slot in slots {
            let key = slot.name.trimmingCharacters(in: .whitespaces).lowercased()
            if key.isEmpty { found.append("A folder has no name."); continue }
            if !seen.insert(key).inserted { found.append("\"\(slot.name)\" appears twice.") }
        }
        return found
    }
}

enum FolderMatch {
    /// The leading digits of a name when they're followed by a non-digit ("03 - X" → "03").
    static func code(of name: String) -> String {
        let digits = name.prefix { $0.isNumber }
        guard !digits.isEmpty else { return "" }
        let rest = name.dropFirst(digits.count)
        if let next = rest.first, next.isNumber { return "" }
        return String(digits)
    }

    /// The existing folder that is `name`: an exact (case-insensitive) name, else one with the
    /// same leading number ("02 - Source Docs" is "02 - Source Documents (Client Uploads)").
    static func match(name: String, in children: [DriveFile]) -> DriveFile? {
        let folders = children.filter(\.isFolder)
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = folders.first(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }) { return exact }
        let wantedCode = FolderMatch.code(of: name)
        guard !wantedCode.isEmpty else { return nil }
        return folders.first { FolderMatch.code(of: $0.name) == wantedCode }
    }
}

enum ClientFolderName {
    /// The name a client's folder gets in Drive.
    static func name(for displayName: String) -> String {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Client" : cleaned
    }
}

enum DocumentNaming {
    static let tokens = ["{year}", "{client}", "{title}", "{date}"]

    /// Renders the pattern. Empty tokens don't leave dangling separators ("2025 -  - Letter" →
    /// "2025 - Letter"), and a pattern with no {title} still keeps the title at the end.
    static func render(pattern: String, title: String, client: String, year: Int, date: Date, calendar: Calendar = .current) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "{title}" }
        if !text.contains("{title}") { text += " - {title}" }

        let stamp = DateFormatter()
        stamp.calendar = calendar
        stamp.timeZone = calendar.timeZone
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd"
        let values: [String: String] = [
            "{year}": year > 0 ? String(year) : "",
            "{client}": client.trimmingCharacters(in: .whitespacesAndNewlines),
            "{title}": cleanTitle,
            "{date}": stamp.string(from: date),
        ]
        for (token, value) in values { text = text.replacingOccurrences(of: token, with: value) }

        // Collapse separators left behind by empty tokens.
        while text.contains(" -  - ") { text = text.replacingOccurrences(of: " -  - ", with: " - ") }
        text = text.replacingOccurrences(of: "  ", with: " ")
        let trimSet = CharacterSet(charactersIn: " -")
        text = text.trimmingCharacters(in: trimSet)
        return text.isEmpty ? (cleanTitle.isEmpty ? "Document" : cleanTitle) : text
    }

    /// The year used in names and year folders: the job's tax year, else the calendar year.
    static func year(taxYear: Int?, date: Date, calendar: Calendar = .current) -> Int {
        if let taxYear, taxYear > 1990 { return taxYear }
        return calendar.component(.year, from: date)
    }
}

// MARK: Document requests that tick themselves

struct OpenRequest: Equatable {
    var id: UUID
    var title: String
}

struct RequestSuggestion: Equatable, Identifiable {
    var requestID: UUID
    var requestTitle: String
    var fileID: String
    var fileName: String
    var id: UUID { requestID }
}

enum RequestMatcher {
    private static let stopWords: Set<String> = ["and", "the", "for", "of", "from", "your", "all", "any", "copy", "copies", "form", "forms", "documents", "document", "docs", "statement"]

    static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func years(in text: String) -> Set<String> {
        var found = Set<String>()
        var run = ""
        for ch in text + " " {
            if ch.isNumber { run.append(ch) } else {
                if run.count == 4, let value = Int(run), (1990...2100).contains(value) { found.insert(run) }
                run = ""
            }
        }
        return found
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    static func matches(requestTitle: String, fileName: String) -> Bool {
        let requestYears = years(in: requestTitle)
        let fileYears = years(in: fileName)
        if !requestYears.isEmpty, !fileYears.isEmpty, requestYears.isDisjoint(with: fileYears) { return false }

        let file = normalize(fileName)
        // "W-2" ↔ "2025 W2 Acme.pdf": compare with punctuation removed.
        let compact = normalize(words(requestTitle).filter { !requestYears.contains($0) }.joined())
        let singular = compact.hasSuffix("s") ? String(compact.dropLast()) : compact
        for candidate in [compact, singular] where candidate.count >= 2 && file.contains(candidate) { return true }

        // Otherwise every meaningful word of the request must appear in the file name.
        let keywords = words(requestTitle).filter { !requestYears.contains($0) && $0.count >= 3 && !stopWords.contains($0) }
        guard !keywords.isEmpty else { return false }
        return keywords.allSatisfy { word in
            let stem = word.hasSuffix("s") && word.count > 3 ? String(word.dropLast()) : word
            return file.contains(stem)
        }
    }

    /// One suggestion per open request, using the first file that matches.
    static func suggestions(requests: [OpenRequest], files: [DriveFile]) -> [RequestSuggestion] {
        let candidates = files.filter { !$0.isFolder }
        return requests.compactMap { request -> RequestSuggestion? in
            guard let file = candidates.first(where: { matches(requestTitle: request.title, fileName: $0.name) }) else { return nil }
            return RequestSuggestion(requestID: request.id, requestTitle: request.title, fileID: file.id, fileName: file.name)
        }
    }
}
