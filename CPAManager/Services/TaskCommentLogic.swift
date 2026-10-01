import Foundation

// A task's notes kept as a dated thread. The thread lives inside the task's existing `notes`
// text (so nothing new has to sync): each comment starts with a "[[yyyy-MM-dd HH:mm]] " stamp,
// and older free-form notes show as the first, undated comment. Pure and unit-tested.

struct TaskComment: Equatable, Identifiable {
    var id: Int
    /// nil for notes written before comments existed.
    var date: Date?
    var text: String
}

enum TaskComments {
    private static let open = "[["
    private static let close = "]] "
    private static let stampLength = 16   // "2026-09-30 14:05"

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }

    /// The notes with one more comment at the end. Blank text changes nothing.
    static func adding(_ text: String, to notes: String, at date: Date = .now, calendar: Calendar = .current) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        let entry = "\(open)\(formatter(calendar).string(from: date))\(close)\(trimmed)"
        let existing = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.isEmpty ? entry : existing + "\n" + entry
    }

    /// The comments in the order written.
    static func parse(_ notes: String, calendar: Calendar = .current) -> [TaskComment] {
        let f = formatter(calendar)
        var result: [TaskComment] = []
        var date: Date?
        var lines: [String] = []
        var started = false

        func flush() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(TaskComment(id: result.count, date: date, text: text)) }
            lines = []
        }

        for line in notes.components(separatedBy: "\n") {
            if let stamp = stampedLine(line, formatter: f) {
                flush()
                date = stamp.date
                lines = [stamp.text]
                started = true
            } else {
                if !started { date = nil }
                lines.append(line)
            }
        }
        flush()
        return result
    }

    private static func stampedLine(_ line: String, formatter: DateFormatter) -> (date: Date, text: String)? {
        guard line.hasPrefix(open) else { return nil }
        let rest = line.dropFirst(open.count)
        guard rest.count >= stampLength + close.count else { return nil }
        let stamp = String(rest.prefix(stampLength))
        let after = rest.dropFirst(stampLength)
        guard after.hasPrefix(close), let date = formatter.date(from: stamp) else { return nil }
        return (date, String(after.dropFirst(close.count)))
    }

    static func count(_ notes: String, calendar: Calendar = .current) -> Int { parse(notes, calendar: calendar).count }
}

enum TaskTime {
    /// Seconds logged against a task: entries tagged with its id, running ones counted up to `now`.
    static func seconds(startedAt: [Date], endedAt: [Date?], now: Date = .now) -> Double {
        zip(startedAt, endedAt).reduce(0) { total, pair in
            total + max(0, (pair.1 ?? now).timeIntervalSince(pair.0))
        }
    }

    static func label(seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return seconds > 0 ? "under a minute" : "none yet" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
