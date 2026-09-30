import Foundation
import SwiftData

/// Store-facing helpers for acting on several jobs or clients at once, and for making
/// any such change undoable.
enum BulkActions {
    static func complete(_ projects: [Project], pipelines: [Pipeline], context: ModelContext) {
        for project in projects { PipelineEngine.complete(project, pipelines: pipelines, context: context) }
    }

    /// Moves each job one stage forward (jobs at the end stay put).
    static func advance(_ projects: [Project], pipelines: [Pipeline], context: ModelContext) {
        for project in projects { PipelineEngine.advanceAny(project, pipelines: pipelines, context: context) }
    }

    static func setDueDate(_ projects: [Project], to date: Date) {
        for project in projects { project.dueDate = date }
    }

    static func addTag(_ tag: String, to clients: [Client]) {
        for client in clients { client.tagsRaw = TagSet.adding(tag, to: client.tagsRaw) }
    }

    static func setStatus(_ status: ClientStatus, for clients: [Client]) {
        for client in clients { client.status = status }
    }
}

extension ModelContext {
    /// Runs `work` (typically deletes or bulk edits), saves, and returns a toast whose Undo
    /// puts everything back from a snapshot taken first.
    ///
    /// - Parameters:
    ///   - includeFiles: keep document/receipt bytes in the snapshot (needed when deleting
    ///     something that owns files, such as a client or a job).
    ///   - overwrite: restore over records that changed (edits) rather than only re-adding
    ///     missing ones (deletes).
    @MainActor
    @discardableResult
    func performUndoable(
        _ message: String,
        systemImage: String = "checkmark.circle.fill",
        includeFiles: Bool = false,
        overwrite: Bool = false,
        _ work: () -> Void
    ) -> UndoToastState {
        let snapshot = BackupService.export(context: self, includeFiles: includeFiles)
        work()
        try? save()
        SnapshotBuilder.rebuild(context: self)
        return UndoToastState(message: message, systemImage: systemImage) { [self] in
            // Undo is tapped on the main thread; the toast's closure type just doesn't say so.
            MainActor.assumeIsolated {
                _ = BackupService.restore(snapshot, into: self, overwrite: overwrite)
                try? save()
                SnapshotBuilder.rebuild(context: self)
            }
        }
    }

    /// `performUndoable` for deletes.
    @MainActor
    @discardableResult
    func deleteWithUndo(_ message: String, includeFiles: Bool = false, _ work: () -> Void) -> UndoToastState {
        performUndoable(message, systemImage: "trash", includeFiles: includeFiles, overwrite: false, work)
    }
}
