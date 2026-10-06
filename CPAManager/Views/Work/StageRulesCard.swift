import SwiftUI
import SwiftData

/// On a job: how long it has been in its stage against the stage's time limit, and what it is
/// still waiting for before automove would move it on. Shows nothing for stages with neither.
struct StageRulesCard: View {
    let project: Project

    @Environment(\.modelContext) private var context
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]

    var body: some View {
        let setup = StageRules.automation(for: project, pipelines: pipelines, context: context)
        let over = StageClock.isOver(limitDays: setup.timeLimitDays, enteredAt: project.stageEnteredAt)
        let clock = setup.timeLimitDays == nil ? nil
            : StageClock.summary(limitDays: setup.timeLimitDays, enteredAt: project.stageEnteredAt)
        let waiting = setup.conditions.isEmpty ? nil
            : StageConditions.waitingSummary(setup.conditions, facts: StageRules.facts(for: project, context: context))
        let remindDays = StageRules.reminderDays(for: project, pipelines: pipelines, context: context)
        let reminded = project.stageRemindedAt != nil && project.stageRemindedAt == project.stageEnteredAt
        if !project.status.isComplete, clock != nil || waiting != nil || remindDays != nil {
            Section {
                if let clock {
                    Label(clock, systemImage: over ? "exclamationmark.triangle.fill" : "clock")
                        .foregroundStyle(over ? Theme.color(.bad) : Color.secondary)
                }
                if let remindDays {
                    Label(reminded ? "Follow-up reminder made" : "Reminds you after \(remindDays) day\(remindDays == 1 ? "" : "s") here",
                          systemImage: reminded ? "bell.badge.fill" : "bell")
                        .foregroundStyle(.secondary)
                }
                if let waiting {
                    Label(waiting + (setup.autoMove ? " — then it moves on by itself" : ""), systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Stage")
            }
        }
    }
}
