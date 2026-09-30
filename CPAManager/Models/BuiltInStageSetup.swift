import Foundation
import SwiftData

/// What a job of one service gets when it enters one stage of that service's *built-in*
/// pipeline: tasks to create and an optional job due date (the same `StageAutomation` custom
/// pipelines use). One record per (service, stage); the stage is the `ProjectStatus` raw value.
/// If two devices create the same one, the newest wins (see `BuiltInSetup.resolve`).
@Model
final class BuiltInStageSetup {
    var id: UUID = UUID()
    var serviceTypeRaw: String = ""
    var stageKey: String = ""
    /// JSON-encoded `StageAutomation`.
    var automationData: Data = Data()
    var updatedAt: Date = Date.now

    init(service: ServiceType = .taxReturn, stageKey: String = "", automation: StageAutomation = StageAutomation(), now: Date = .now) {
        self.id = UUID()
        self.serviceTypeRaw = service.rawValue
        self.stageKey = stageKey
        self.updatedAt = now
        self.automation = automation
    }

    var automation: StageAutomation {
        get { (try? JSONDecoder().decode(StageAutomation.self, from: automationData)) ?? StageAutomation() }
        set { automationData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
