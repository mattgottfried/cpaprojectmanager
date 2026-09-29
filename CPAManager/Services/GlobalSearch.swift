import Foundation

/// A flattened, searchable thing (client, project, task…), decoupled from SwiftData so
/// ranking is unit-tested with plain values.
struct SearchDoc: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case client, project, task, invoice, inbox, expense, note

        var label: String {
            switch self {
            case .client:  return "Clients"
            case .project: return "Work"
            case .task:    return "Tasks"
            case .invoice: return "Invoices"
            case .inbox:   return "Inbox"
            case .expense: return "Expenses"
            case .note:    return "Activity"
            }
        }

        var systemImage: String {
            switch self {
            case .client:  return "person.fill"
            case .project: return "folder.fill"
            case .task:    return "checkmark.circle"
            case .invoice: return "doc.text.fill"
            case .inbox:   return "tray.fill"
            case .expense: return "creditcard.fill"
            case .note:    return "clock.arrow.circlepath"
            }
        }

        /// Tie-breaker: when scores match, people/work come before notes.
        var priority: Int {
            switch self {
            case .client: return 0
            case .project: return 1
            case .task: return 2
            case .invoice: return 3
            case .inbox: return 4
            case .expense: return 5
            case .note: return 6
            }
        }
    }

    /// Stable deep-link identifier, e.g. "client:<uuid>" (see `DeepLink`).
    var id: String
    var kind: Kind
    var title: String
    var subtitle: String = ""
    /// Extra searchable text that isn't shown (tags, email, company…).
    var keywords: String = ""
    /// Deep-link identifier to open when this result is chosen, if different from `id`
    /// (an activity note opens its client).
    var target: String? = nil
}

struct SearchHit: Equatable, Identifiable {
    var doc: SearchDoc
    var score: Int
    var id: String { doc.id }
}

enum GlobalSearch {
    /// Every whitespace-separated word of the query must match somewhere. Title matches
    /// outrank subtitle matches, which outrank hidden keywords; earlier-in-the-title
    /// (prefix) matches outrank mid-title ones.
    static func search(_ docs: [SearchDoc], query: String, limit: Int = 30) -> [SearchHit] {
        let tokens = normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for doc in docs {
            let title = normalize(doc.title)
            let subtitle = normalize(doc.subtitle)
            let keywords = normalize(doc.keywords)

            var total = 0
            var matchedAll = true
            for token in tokens {
                let score = tokenScore(token, title: title, subtitle: subtitle, keywords: keywords)
                if score == 0 { matchedAll = false; break }
                total += score
            }
            if matchedAll {
                // A whole-title exact match is the best possible result.
                if title == tokens.joined(separator: " ") { total += 50 }
                hits.append(SearchHit(doc: doc, score: total))
            }
        }

        return Array(
            hits.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.doc.kind.priority != $1.doc.kind.priority { return $0.doc.kind.priority < $1.doc.kind.priority }
                return $0.doc.title.localizedCaseInsensitiveCompare($1.doc.title) == .orderedAscending
            }
            .prefix(limit)
        )
    }

    private static func tokenScore(_ token: String, title: String, subtitle: String, keywords: String) -> Int {
        if title.hasPrefix(token) { return 100 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(token) }) { return 80 }
        if title.contains(token) { return 60 }
        if subtitle.split(separator: " ").contains(where: { $0.hasPrefix(token) }) { return 35 }
        if subtitle.contains(token) { return 25 }
        if keywords.contains(token) { return 10 }
        return 0
    }

    /// Lowercased, punctuation folded to spaces, diacritics stripped, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "@" || scalar == "." ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}

/// A jump target for Spotlight results, Siri, notifications and the quick-open palette.
enum DeepLink: Equatable {
    case client(UUID)
    case project(UUID)
    case task(UUID)
    case invoice(UUID)

    var identifier: String {
        switch self {
        case .client(let id):  return "client:\(id.uuidString)"
        case .project(let id): return "project:\(id.uuidString)"
        case .task(let id):    return "task:\(id.uuidString)"
        case .invoice(let id): return "invoice:\(id.uuidString)"
        }
    }

    init?(identifier: String) {
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "client":  self = .client(id)
        case "project": self = .project(id)
        case "task":    self = .task(id)
        case "invoice": self = .invoice(id)
        default:        return nil
        }
    }
}
