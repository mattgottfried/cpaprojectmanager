import Foundation
import SwiftData

/// A user-defined job pipeline ("Bookkeeping", "Onboarding", "IRS Notice Response"…), like
/// the multiple pipelines in TaxDome. Stages live in one JSON column so CloudKit needs no
/// extra record type. The original tax-return pipeline is built in (see
/// `PipelineDefinition.standard`) and is never stored here.
@Model
final class Pipeline {
    var id: UUID = UUID()
    var name: String = ""
    var systemImage: String = "rectangle.split.3x1"
    var sortIndex: Int = 0
    /// JSON-encoded `[PipelineStage]`.
    var stagesData: Data = Data()
    var createdAt: Date = Date.now

    init(name: String = "", systemImage: String = "rectangle.split.3x1", stages: [PipelineStage] = [], sortIndex: Int = 0) {
        self.id = UUID()
        self.name = name
        self.systemImage = systemImage
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.stages = stages
    }

    convenience init(definition: PipelineDefinition, sortIndex: Int = 0) {
        self.init(name: definition.name, systemImage: definition.systemImage, stages: definition.stages, sortIndex: sortIndex)
    }

    var stages: [PipelineStage] {
        get { (try? JSONDecoder().decode([PipelineStage].self, from: stagesData)) ?? [] }
        set { stagesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var definition: PipelineDefinition {
        get { PipelineDefinition(name: name, systemImage: systemImage, stages: stages) }
        set {
            name = newValue.name
            systemImage = newValue.systemImage
            stages = newValue.stages
        }
    }
}
