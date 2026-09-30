import Foundation
import SwiftData

/// Moves jobs between pipeline stages and runs each stage's entry automation. All the
/// *rules* are in `PipelineLogic.swift`; this only touches the store.
enum PipelineEngine {
    /// Puts `project` into `stage`: updates its stage key and coarse status, resets the
    /// due date if the stage says so, and creates the stage's tasks.
    static func enter(_ project: Project, stage: PipelineStage, context: ModelContext, now: Date = .now) {
        let plan = PipelineMove.plan(entering: stage, now: now)
        project.stageKey = stage.id
        project.status = plan.status          // also stamps/clears completedAt
        if let due = plan.dueDate { project.dueDate = due }

        var index = (project.tasks ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        // Only the first task gets a due date. Each later one waits for the task before it
        // and is dated when that one is completed (`TaskCompletion.complete`).
        var previous: TaskItem?
        for task in plan.tasks {
            // A job that re-enters a stage shouldn't grow duplicate automation tasks.
            if let existing = (project.tasks ?? []).first(where: { $0.title == task.title && !$0.isDone }) {
                previous = existing
                continue
            }
            let item = TaskItem(title: task.title, dueDate: previous == nil ? task.dueDate : nil, sortIndex: index, project: project)
            if let previous {
                item.blockedByID = previous.id
                item.dueInDaysAfterBlocker = task.dueInDays
            }
            context.insert(item)
            previous = item
            index += 1
        }
    }

    /// Assigns a job to a pipeline (nil = the built-in one) and enters the given stage
    /// (default: the first). Switching to the built-in pipeline keeps the current status.
    static func assign(_ project: Project, to pipeline: Pipeline?, startStageKey: String = "", context: ModelContext) {
        guard let pipeline else {
            project.pipelineID = nil
            project.stageKey = ""
            return
        }
        let definition = pipeline.definition
        // A chosen start stage is honored (even a waiting one); otherwise the first real stage.
        guard let stage = definition.stage(withKey: startStageKey) ?? definition.firstStartStage else { return }
        project.pipelineID = pipeline.id
        enter(project, stage: stage, context: context)
    }

    /// Puts new work in the custom pipeline chosen for its service type (More ▸ Pipelines),
    /// if one is set. Built-in pipelines need nothing.
    static func applyDefault(to project: Project, context: ModelContext, defaults: UserDefaults = .standard) {
        guard project.pipelineID == nil,
              let id = PipelineDefaults.pipelineID(for: project.serviceType, defaults: defaults) else { return }
        let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
        guard let pipeline = pipelines.first(where: { $0.id == id }) else { return }
        assign(project, to: pipeline, context: context)
    }

    /// Moves a custom-pipeline job to the next stage (never into a waiting stage).
    /// Returns false at the end.
    @discardableResult
    static func advance(_ project: Project, in pipeline: Pipeline, context: ModelContext) -> Bool {
        guard let next = pipeline.definition.next(after: project.stageKey) else { return false }
        enter(project, stage: next, context: context)
        return true
    }

    /// The pipeline (definition) a job belongs to, or nil for the built-in one.
    static func pipeline(for project: Project, in pipelines: [Pipeline]) -> Pipeline? {
        guard let id = project.pipelineID else { return nil }
        return pipelines.first { $0.id == id }
    }

    static func info(for project: Project, in pipelines: [Pipeline]) -> StageInfo {
        PipelineResolver.info(
            definition: pipeline(for: project, in: pipelines)?.definition,
            stageKey: project.stageKey,
            status: project.status,
            flow: project.statusFlow
        )
    }

    /// Name of the stage an "Advance" would move the job to (either kind of pipeline).
    static func nextStageName(for project: Project, in pipelines: [Pipeline]) -> String? {
        if let custom = pipeline(for: project, in: pipelines) {
            return custom.definition.next(after: project.stageKey)?.name
        }
        return project.nextStatusPreview.map { project.statusFlow.label($0) }
    }

    /// One-tap advance for either kind of pipeline.
    static func advanceAny(_ project: Project, pipelines: [Pipeline], context: ModelContext) {
        if let custom = pipeline(for: project, in: pipelines) {
            advance(project, in: custom, context: context)
        } else {
            project.advance()
        }
    }
}
