import Foundation
import SwiftData

/// A reusable checklist for a standard engagement (e.g. "1040 Individual Return").
/// Instantiating a template produces a `Project` plus `TaskItem`s — see `WorkflowEngine`.
@Model
final class WorkflowTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var detail: String = ""
    var serviceTypeRaw: String = ServiceType.taxReturn.rawValue
    /// Default number of days from start to the project due date.
    var defaultDurationDays: Int = 30
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TemplateTask.template)
    var tasks: [TemplateTask]? = []

    init(
        name: String = "",
        detail: String = "",
        serviceType: ServiceType = .taxReturn,
        defaultDurationDays: Int = 30
    ) {
        self.id = UUID()
        self.name = name
        self.detail = detail
        self.serviceTypeRaw = serviceType.rawValue
        self.defaultDurationDays = defaultDurationDays
        self.createdAt = .now
    }

    var serviceType: ServiceType {
        get { ServiceType(rawValue: serviceTypeRaw) ?? .other }
        set { serviceTypeRaw = newValue.rawValue }
    }

    var taskList: [TemplateTask] {
        (tasks ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// A step within a `WorkflowTemplate`.
@Model
final class TemplateTask {
    var id: UUID = UUID()
    var title: String = ""
    var sortIndex: Int = 0
    /// Days after the project start date that this task is due.
    var dayOffset: Int = 0

    var template: WorkflowTemplate? = nil

    init(title: String = "", sortIndex: Int = 0, dayOffset: Int = 0, template: WorkflowTemplate? = nil) {
        self.id = UUID()
        self.title = title
        self.sortIndex = sortIndex
        self.dayOffset = dayOffset
        self.template = template
    }
}
