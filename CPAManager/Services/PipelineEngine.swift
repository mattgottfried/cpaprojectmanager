import Foundation
import SwiftData

/// Moves jobs between pipeline stages and runs each stage's entry automation. All the
/// *rules* are in `PipelineLogic.swift`; this only touches the store.
enum PipelineEngine {
    /// Puts `project` into `stage`: updates its stage key and coarse status, resets the due
    /// date if the stage says so, and creates the stage's tasks.
    static func enter(_ project: Project, stage: PipelineStage, context: ModelContext, now: Date = .now) {
        let plan = PipelineMove.plan(entering: stage, now: now)
        project.stageKey = stage.id
        project.status = plan.status          // also stamps/clears completedAt
        runAutomation(stage.automation, stageKey: stage.id, for: project, context: context, now: now)
    }

    /// A stage's entry automation: reset the job's due date and create the stage's tasks.
    /// Only the first task gets a due date; each later one waits on the one before it and is
    /// dated when that one is completed (`TaskCompletion.complete`).
    static func runAutomation(_ automation: StageAutomation, stageKey: String, for project: Project, context: ModelContext, now: Date = .now) {
        let plan = PipelineMove.plan(entering: PipelineStage(name: "", automation: automation), now: now)
        if let due = plan.dueDate { project.dueDate = due }
        StageRules.stamp(project, now: now)

        var index = (project.tasks ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        var previous: TaskItem?
        for task in plan.tasks {
            // A job that re-enters a stage shouldn't grow duplicate automation tasks.
            if let existing = (project.tasks ?? []).first(where: { $0.title == task.title && !$0.isDone }) {
                previous = existing
                continue
            }
            let item = TaskItem(title: task.title, dueDate: previous == nil ? task.dueDate : nil, sortIndex: index, project: project)
            item.startDate = previous == nil ? now : nil
            item.stageKey = stageKey
            if let previous {
                item.blockedByID = previous.id
                item.dueInDaysAfterBlocker = task.dueInDays
            }
            context.insert(item)
            previous = item
            index += 1
        }
    }

    // MARK: Built-in pipelines

    /// The tasks set up for the stage a built-in-pipeline job is in.
    static func builtInAutomation(for project: Project, context: ModelContext) -> StageAutomation {
        let stage = project.statusFlow.normalize(project.status).rawValue
        return BuiltInSetupService.automation(for: project.serviceType, stageKey: stage, context: context)
    }

    /// Runs the current stage's setup for a job in its service's built-in pipeline (no-op
    /// for custom-pipeline jobs, which run their own stage automation).
    static func runBuiltInAutomation(_ project: Project, context: ModelContext, now: Date = .now) {
        guard project.pipelineID == nil else { return }
        runAutomation(builtInAutomation(for: project, context: context),
                      stageKey: project.statusFlow.normalize(project.status).rawValue,
                      for: project, context: context, now: now)
    }

    /// Moves a built-in-pipeline job to `status` and runs that stage's setup. Setting the
    /// stage a job is already in does nothing.
    static func setBuiltInStatus(_ project: Project, to status: ProjectStatus, context: ModelContext, now: Date = .now) {
        guard project.status != status else { return }
        project.status = status
        runBuiltInAutomation(project, context: context, now: now)
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
        guard project.pipelineID == nil else { return }
        if let id = PipelineDefaults.pipelineID(for: project.serviceType, defaults: defaults) {
            let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
            if let pipeline = pipelines.first(where: { $0.id == id }) {
                assign(project, to: pipeline, context: context)
                return
            }
        }
        // Still in the service's built-in pipeline: start it with its first stage's tasks.
        runBuiltInAutomation(project, context: context)
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

    /// Finishes a job: the built-in "complete" status, or a custom pipeline's last done stage.
    static func complete(_ project: Project, pipelines: [Pipeline], context: ModelContext) {
        if let custom = pipeline(for: project, in: pipelines),
           let done = custom.definition.stages.last(where: { $0.kind.isDone }) {
            enter(project, stage: done, context: context)
        } else {
            setBuiltInStatus(project, to: .complete, context: context)
        }
    }

    /// Automove: after a stage task is completed, moves the job to the next stage if its
    /// current stage has automove on and all the tasks the stage created are done. Returns
    /// whether the job moved.
    @discardableResult
    static func autoMoveIfReady(after task: TaskItem, context: ModelContext, now: Date = .now) -> Bool {
        guard let project = task.project, !task.stageKey.isEmpty, !project.status.isComplete else { return false }
        let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
        let custom = pipeline(for: project, in: pipelines)

        let currentKey: String
        let automation: StageAutomation
        if let custom {
            currentKey = project.stageKey
            automation = custom.definition.stage(withKey: currentKey)?.automation ?? StageAutomation()
        } else {
            currentKey = project.statusFlow.normalize(project.status).rawValue
            automation = builtInAutomation(for: project, context: context)
        }
        let done = project.taskList.filter { $0.stageKey == currentKey }.map(\.isDone)
        guard StageAutoMove.shouldMove(autoMove: automation.autoMove, completedTaskStageKey: task.stageKey,
                                       currentStageKey: currentKey, stageTasksDone: done) else { return false }
        // Conditions (invoice paid, documents received…) must also hold; the sweep moves the job
        // later if they become true after the last task is done.
        guard StageConditions.allMet(automation.conditions, facts: StageRules.facts(for: project, context: context)) else { return false }

        if let custom {
            return advance(project, in: custom, context: context)
        }
        guard project.advance() else { return false }
        runBuiltInAutomation(project, context: context, now: now)
        return true
    }

    /// One-tap advance for either kind of pipeline.
    static func advanceAny(_ project: Project, pipelines: [Pipeline], context: ModelContext) {
        if let custom = pipeline(for: project, in: pipelines) {
            advance(project, in: custom, context: context)
        } else if project.advance() {
            runBuiltInAutomation(project, context: context)
        }
    }
}
