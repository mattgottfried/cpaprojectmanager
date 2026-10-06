import Foundation
import SwiftData

/// Store-facing side of stage time limits and stage conditions: the stage clock on each job,
/// the facts conditions are checked against, and the sweep that moves jobs on when a stage's
/// automove rule becomes true without a task being completed (a payment arriving, a
/// signature, a document request ticked off).
enum StageRules {
    /// The stage a job is in: the stage key for a custom pipeline, the (normalized) status for a built-in one.
    static func currentKey(_ project: Project) -> String {
        project.pipelineID != nil ? project.stageKey : project.statusFlow.normalize(project.status).rawValue
    }

    /// The setup of the stage the job is in now.
    static func automation(for project: Project, pipelines: [Pipeline], context: ModelContext) -> StageAutomation {
        if let custom = PipelineEngine.pipeline(for: project, in: pipelines) {
            return custom.definition.stage(withKey: project.stageKey)?.automation ?? StageAutomation()
        }
        return PipelineEngine.builtInAutomation(for: project, context: context)
    }

    static func timeLimit(for project: Project, pipelines: [Pipeline], context: ModelContext) -> Int? {
        automation(for: project, pipelines: pipelines, context: context).timeLimitDays
    }

    // MARK: The stage clock

    /// Starts the clock if the job is in a different stage than the one it was stamped with.
    static func stamp(_ project: Project, now: Date = .now) {
        let key = currentKey(project)
        if StageClock.needsStamp(storedKey: project.stageEnteredKey, currentKey: key, enteredAt: project.stageEnteredAt) {
            project.stageEnteredKey = key
            project.stageEnteredAt = now
        }
    }

    /// Stamps every open job whose stage changed (or never had a clock). Returns how many changed.
    @discardableResult
    static func reconcileAll(context: ModelContext, now: Date = .now) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var changed = 0
        for project in projects where !project.status.isComplete {
            let before = project.stageEnteredKey
            stamp(project, now: now)
            if project.stageEnteredKey != before { changed += 1 }
        }
        if changed > 0 { try? context.save() }
        return changed
    }

    // MARK: Waiting reminders

    /// Whether the job's stage is one where you're waiting on someone else: a custom stage of
    /// kind "waiting", or the built-in Waiting on Client / Awaiting Signature statuses.
    static func isWaitingStage(_ project: Project, pipelines: [Pipeline]) -> Bool {
        if let custom = PipelineEngine.pipeline(for: project, in: pipelines) {
            return custom.definition.stage(withKey: project.stageKey)?.kind == .waiting
        }
        let status = project.statusFlow.normalize(project.status)
        return status == .waitingOnClient || status == .awaitingSignature
    }

    /// Days before the stage makes a reminder task, if any.
    static func reminderDays(for project: Project, pipelines: [Pipeline], context: ModelContext) -> Int? {
        let setup = automation(for: project, pipelines: pipelines, context: context)
        return StageReminder.effectiveDays(configured: setup.remindAfterDays, isWaiting: isWaitingStage(project, pipelines: pipelines))
    }

    /// Creates a follow-up task (due today) for every open job that has sat in a stage past its
    /// reminder days, once per stay. Returns how many were made.
    @discardableResult
    static func fireReminders(context: ModelContext, now: Date = .now) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
        var made = 0
        for project in projects where !project.status.isComplete {
            let days = reminderDays(for: project, pipelines: pipelines, context: context)
            guard StageReminder.isDue(days: days, enteredAt: project.stageEnteredAt, remindedFor: project.stageRemindedAt, now: now),
                  let days else { continue }
            let task = TaskItem(
                title: StageReminder.title(client: project.clientName == "No client" ? "" : project.clientName, job: project.title, days: days),
                dueDate: now, sortIndex: (project.tasks ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0, project: project
            )
            context.insert(task)
            project.stageRemindedAt = project.stageEnteredAt
            made += 1
        }
        if made > 0 {
            try? context.save()
            SnapshotBuilder.rebuild(context: context)
            NotificationScheduler.rescheduleAll(context: context)
        }
        return made
    }

    // MARK: Conditions

    static func facts(for project: Project, context: ModelContext) -> JobFacts {
        var facts = JobFacts()
        facts.openTaskCount = project.taskList.filter { !$0.isDone }.count

        var requests: [UUID: DocumentRequest] = [:]
        for request in project.documentRequests ?? [] { requests[request.id] = request }
        for request in project.client?.documentRequestList ?? [] where request.project == nil || request.project?.id == project.id {
            requests[request.id] = request
        }
        facts.openRequestCount = requests.values.filter { !$0.isReceived }.count

        if let invoiceID = project.invoiceID {
            let invoices = (try? context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate<Invoice> { $0.id == invoiceID }))) ?? []
            if let invoice = invoices.first {
                facts.hasInvoice = true
                facts.invoicePaid = invoice.status == .paid
            }
        }

        var documents: [UUID: Document] = [:]
        for document in project.documents ?? [] { documents[document.id] = document }
        for document in project.client?.documents ?? [] where document.project == nil || document.project?.id == project.id {
            documents[document.id] = document
        }
        facts.awaitingSignatureCount = documents.values.filter { $0.signatureStatus == .sent }.count
        return facts
    }

    /// What an open job is still waiting for before its stage would move it on ("Waiting for the
    /// invoice to be paid"), or nil when there are no conditions or they're all met.
    static func waitingSummary(for project: Project, pipelines: [Pipeline], context: ModelContext) -> String? {
        let conditions = automation(for: project, pipelines: pipelines, context: context).conditions
        guard !conditions.isEmpty else { return nil }
        return StageConditions.waitingSummary(conditions, facts: facts(for: project, context: context))
    }

    // MARK: Sweep

    /// Moves every open job whose stage has automove on and whose tasks and conditions are all
    /// satisfied. A job can move through several stages in one sweep; at most `maxMoves` per job.
    /// Returns the number of moves made.
    @discardableResult
    static func sweep(context: ModelContext, maxMovesPerJob: Int = 8, now: Date = .now) -> Int {
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        let pipelines = (try? context.fetch(FetchDescriptor<Pipeline>())) ?? []
        var moves = 0
        for project in projects where !project.status.isComplete {
            var stepsLeft = maxMovesPerJob
            while stepsLeft > 0, stepAutoMove(project, pipelines: pipelines, context: context, now: now) {
                moves += 1
                stepsLeft -= 1
            }
        }
        if moves > 0 {
            try? context.save()
            SnapshotBuilder.rebuild(context: context)
        }
        return moves
    }

    /// One automove step for a job if its current stage's rule is satisfied.
    @discardableResult
    static func stepAutoMove(_ project: Project, pipelines: [Pipeline], context: ModelContext, now: Date = .now) -> Bool {
        let setup = automation(for: project, pipelines: pipelines, context: context)
        let key = currentKey(project)
        let stageTasksDone = project.taskList.filter { $0.stageKey == key }.map(\.isDone)
        guard StageSweep.shouldMove(autoMove: setup.autoMove, stageTasksDone: stageTasksDone,
                                    conditions: setup.conditions, facts: facts(for: project, context: context)) else { return false }
        if let custom = PipelineEngine.pipeline(for: project, in: pipelines) {
            return PipelineEngine.advance(project, in: custom, context: context)
        }
        guard project.advance() else { return false }
        PipelineEngine.runBuiltInAutomation(project, context: context, now: now)
        return true
    }
}
