import Foundation
import SwiftData

/// Turns items queued by the share extension into Inbox items, and files their
/// attachments as Documents. Called on launch and whenever the app becomes active.
enum CaptureQueue {
    @discardableResult
    static func drain(context: ModelContext) -> Int {
        let captures = PendingCaptures.drain()
        guard !captures.isEmpty else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<InboxItem>())) ?? []
        var knownKeys = Set(existing.map(\.dedupeKey))
        var added = 0

        for capture in captures {
            let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = text.isEmpty ? attachmentLabel(capture.attachmentName) : text
            guard !display.isEmpty else { continue }

            // Re-sharing the same text is a no-op; an attachment always counts as new.
            let key = NoteDigestParser.dedupeKey(display)
            if capture.attachmentName.isEmpty, !knownKeys.insert(key).inserted { continue }

            let item = InboxItem(text: display, source: InboxSource(rawValue: capture.sourceRaw) ?? .email)
            item.createdAt = capture.createdAt
            item.link = capture.link
            item.attachmentName = capture.attachmentName
            context.insert(item)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    private static func attachmentLabel(_ storedName: String) -> String {
        guard !storedName.isEmpty else { return "" }
        let parts = PendingCaptures.displayParts(storedName)
        return parts.ext.isEmpty ? parts.base : "\(parts.base).\(parts.ext)"
    }

    /// Files an item's attachment onto a client and/or project, then removes the temp copy.
    @discardableResult
    static func fileAttachment(of item: InboxItem, client: Client?, project: Project?, context: ModelContext) -> Document? {
        guard let url = PendingCaptures.attachmentURL(item.attachmentName),
              let data = try? Data(contentsOf: url) else { return nil }
        let parts = PendingCaptures.displayParts(item.attachmentName)
        let document = Document(
            filename: parts.base,
            fileExtension: parts.ext.isEmpty ? "pdf" : parts.ext,
            data: data,
            client: client ?? project?.client,
            project: project
        )
        context.insert(document)
        try? FileManager.default.removeItem(at: url)
        item.attachmentName = ""
        try? context.save()
        return document
    }
}
