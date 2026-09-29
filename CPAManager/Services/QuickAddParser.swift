import Foundation

/// Turns a line typed into a quick-add field into a title plus an optional due
/// date ("call Smith tomorrow", "send 1099s friday"). Pure and unit-tested.
enum QuickAddParser {
    struct Result: Equatable {
        var title: String
        var dueDate: Date?
    }

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Result(title: "", dueDate: nil) }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return Result(title: trimmed, dueDate: nil)
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        // Only trust a date phrase at the very end or very start of the line, so
        // "Review 2025 return" or "Call 407 client" aren't mangled by a stray match.
        guard let match = matches.last(where: { isAtEdge($0.range, in: trimmed) }),
              let date = match.date,
              let swiftRange = Range(match.range, in: trimmed) else {
            return Result(title: trimmed, dueDate: nil)
        }

        // Interpret a bare weekday/day-only phrase as the future, and drop time-of-day
        // noise — tasks are day-granular in this app.
        var day = calendar.startOfDay(for: date)
        if day < calendar.startOfDay(for: now) {
            day = calendar.startOfDay(for: now)
        }

        var title = trimmed
        title.removeSubrange(swiftRange)
        title = cleanTitle(title)
        if title.isEmpty { title = trimmed }   // whole line was a date; keep it as text
        return Result(title: title, dueDate: title == trimmed ? nil : day)
    }

    private static func isAtEdge(_ range: NSRange, in text: String) -> Bool {
        let length = (text as NSString).length
        return range.location == 0 || NSMaxRange(range) == length
    }

    private static func cleanTitle(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Trailing/leading glue words left behind by the removed phrase.
        let glue = ["by", "on", "due", "before", "at", "-", "—", ","]
        var changed = true
        while changed {
            changed = false
            for g in glue {
                let lower = t.lowercased()
                if lower.hasSuffix(" " + g) {
                    t = String(t.dropLast(g.count + 1)).trimmingCharacters(in: .whitespaces)
                    changed = true
                } else if lower.hasPrefix(g + " ") {
                    t = String(t.dropFirst(g.count + 1)).trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
        }
        return t
    }
}
