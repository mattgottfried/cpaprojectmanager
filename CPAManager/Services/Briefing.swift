import Foundation

/// Spoken/short summaries for Siri and Shortcuts. Pure and unit-tested.
enum Briefing {
    /// "Dana Lee: 2 open projects, last contact 5 days ago, follow-up in 3 days, $200.00 outstanding."
    static func client(
        name: String,
        openProjects: Int,
        lastContact: String,
        followUp: Date?,
        outstanding: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        var parts: [String] = []
        parts.append(openProjects == 0 ? "no open projects" : "\(openProjects) open project\(openProjects == 1 ? "" : "s")")
        parts.append(lastContact == "No contact logged" ? "no contact logged" : "last contact \(lastContact.lowercased())")
        if let followUp {
            parts.append("follow-up \(Format.relativeDay(followUp, calendar: calendar).lowercased())")
        }
        if InvoiceMath.cents(outstanding) > 0 {
            parts.append("\(Format.currency(outstanding)) outstanding")
        }
        return "\(name): " + parts.joined(separator: ", ") + "."
    }

    /// "2 overdue and 3 due today. Next: Call Smith, Send 1099s. 4 items in your inbox."
    static func today(overdue: Int, dueToday: Int, inbox: Int, next: [String]) -> String {
        var sentences: [String] = []
        if overdue == 0 && dueToday == 0 {
            sentences.append("Nothing overdue or due today.")
        } else {
            var counts: [String] = []
            if overdue > 0 { counts.append("\(overdue) overdue") }
            if dueToday > 0 { counts.append("\(dueToday) due today") }
            sentences.append(counts.joined(separator: " and ") + ".")
        }
        let top = next.prefix(3)
        if !top.isEmpty { sentences.append("Next: " + top.joined(separator: ", ") + ".") }
        if inbox > 0 { sentences.append("\(inbox) item\(inbox == 1 ? "" : "s") in your inbox.") }
        return sentences.joined(separator: " ")
    }
}
