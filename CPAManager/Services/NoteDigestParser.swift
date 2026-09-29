import Foundation

/// Splits a block of pasted/shared text (an Apple Note of digested text messages, an
/// email body, a Shortcuts payload) into individual capture candidates. Pure and
/// unit-tested; the same parser backs the in-app "Paste" sheet and the App Intent, so
/// re-running a Shortcut over the same note yields the same dedupe keys.
enum NoteDigestParser {
    struct Candidate: Equatable {
        var text: String
        /// Already checked off / struck in the source ("[x]", "✓", "☑").
        var isChecked: Bool
    }

    static let checkedMarkers = ["[x]", "[X]", "☑", "☑️", "✅", "✓", "✔"]
    static let uncheckedMarkers = ["[ ]", "☐", "○", "◻︎", "□"]
    static let bulletMarkers = ["-", "–", "—", "•", "*", "·", "▪︎", "●"]

    /// One candidate per meaningful line. Headings ("Today:", "## Messages"),
    /// separators and very short fragments are dropped.
    static func candidates(from text: String) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)

        for rawLine in lines {
            let parsed = stripMarkers(String(rawLine))
            let line = parsed.text
            guard isMeaningful(line) else { continue }
            let key = dedupeKey(line)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(Candidate(text: line, isChecked: parsed.checked))
        }
        return result
    }

    /// Lowercased alphanumerics only, whitespace collapsed — stable across trivial
    /// edits like punctuation, bullets, or casing.
    static func dedupeKey(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    // MARK: Helpers

    private static func stripMarkers(_ line: String) -> (text: String, checked: Bool) {
        var t = line.trimmingCharacters(in: .whitespaces)
        var checked = false

        // Repeat so "- [x] foo" and "1. ☐ foo" both resolve.
        var progressed = true
        while progressed {
            progressed = false
            for marker in checkedMarkers where t.hasPrefix(marker) {
                t = String(t.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                checked = true
                progressed = true
            }
            for marker in uncheckedMarkers where t.hasPrefix(marker) {
                t = String(t.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                progressed = true
            }
            for marker in bulletMarkers where t.hasPrefix(marker + " ") {
                t = String(t.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                progressed = true
            }
            if let numbered = dropNumberPrefix(t) {
                t = numbered
                progressed = true
            }
        }
        return (t, checked)
    }

    /// "1. foo" / "12) foo" → "foo". Leaves "2025 return" alone (no dot/paren).
    private static func dropNumberPrefix(_ s: String) -> String? {
        var digits = 0
        for ch in s {
            if ch.isNumber { digits += 1 } else { break }
        }
        guard digits > 0, digits <= 3 else { return nil }
        let rest = s.dropFirst(digits)
        guard let first = rest.first, first == "." || first == ")" else { return nil }
        let after = rest.dropFirst().trimmingCharacters(in: .whitespaces)
        return after.isEmpty ? nil : after
    }

    private static func isMeaningful(_ line: String) -> Bool {
        if line.count < 3 { return false }
        if line.hasPrefix("#") { return false }                     // markdown heading
        if line.allSatisfy({ "-=_*~ ".contains($0) }) { return false } // separator
        // A bare heading like "Today:" or "Messages:".
        if line.hasSuffix(":"), line.split(separator: " ").count <= 3 { return false }
        return true
    }
}
