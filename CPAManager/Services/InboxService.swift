import Foundation
import SwiftData

/// SwiftData-facing side of capture. All text splitting/dedupe rules live in
/// `NoteDigestParser`; this only talks to the store.
enum InboxService {
    struct ImportResult: Equatable {
        var added: Int
        var skippedDuplicates: Int
        var skippedChecked: Int
    }

    /// Adds one inbox item per meaningful line of `text`. Lines already captured
    /// before (processed or not) are skipped, so re-running a Shortcut over the same
    /// note each day only brings in what's new. Checked-off lines are ignored.
    @discardableResult
    static func capture(text: String, source: InboxSource, context: ModelContext, splitLines: Bool = true) -> ImportResult {
        let existing = (try? context.fetch(FetchDescriptor<InboxItem>())) ?? []
        var knownKeys = Set(existing.map(\.dedupeKey))

        let candidates: [NoteDigestParser.Candidate]
        if splitLines {
            candidates = NoteDigestParser.candidates(from: text)
        } else {
            let single = text.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates = single.isEmpty ? [] : [NoteDigestParser.Candidate(text: single, isChecked: false)]
        }

        var result = ImportResult(added: 0, skippedDuplicates: 0, skippedChecked: 0)
        for candidate in candidates {
            if candidate.isChecked {
                result.skippedChecked += 1
                continue
            }
            let key = NoteDigestParser.dedupeKey(candidate.text)
            guard !key.isEmpty, knownKeys.insert(key).inserted else {
                result.skippedDuplicates += 1
                continue
            }
            context.insert(InboxItem(text: candidate.text, source: source))
            result.added += 1
        }
        if result.added > 0 { try? context.save() }
        return result
    }

    /// Turns an inbox item into a standalone task (next action or dated) and marks
    /// it processed. Returns the created task.
    @discardableResult
    static func makeTask(from item: InboxItem, dueDate: Date?, client: Client?, context: ModelContext) -> TaskItem {
        let parsed = QuickAddParser.parse(item.text)
        let title = parsed.title.isEmpty ? item.text : parsed.title
        let due = dueDate ?? parsed.dueDate
        let task = TaskItem(title: title, dueDate: due, isNextAction: due == nil)
        task.client = client ?? item.client
        context.insert(task)
        item.markProcessed()
        try? context.save()
        return task
    }

    /// Adds the item as a task inside an existing project and marks it processed.
    @discardableResult
    static func attach(_ item: InboxItem, to project: Project, dueDate: Date?, context: ModelContext) -> TaskItem {
        let parsed = QuickAddParser.parse(item.text)
        let title = parsed.title.isEmpty ? item.text : parsed.title
        let nextIndex = (project.tasks ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        let task = TaskItem(title: title, dueDate: dueDate ?? parsed.dueDate, sortIndex: nextIndex, project: project)
        context.insert(task)
        item.markProcessed()
        try? context.save()
        return task
    }
}
