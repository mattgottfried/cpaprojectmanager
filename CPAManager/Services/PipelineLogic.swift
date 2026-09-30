import Foundation

// Pure pipeline logic (custom stages, entry automations, moves). No SwiftData, no SwiftUI.
// Unit-tested.

/// What a stage *means*, independent of its name. Legacy features (overdue, complete,
/// reports) read the coarse `ProjectStatus` derived from this.
enum StageKind: String, Codable, CaseIterable, Identifiable {
    case notStarted, working, waiting, review, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notStarted: return "Not started"
        case .working:    return "Working"
        case .waiting:    return "Waiting on someone"
        case .review:     return "Review"
        case .done:       return "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: return "circle"
        case .working:    return "circle.lefthalf.filled"
        case .waiting:    return "hourglass"
        case .review:     return "magnifyingglass"
        case .done:       return "checkmark.circle.fill"
        }
    }

    var isDone: Bool { self == .done }

    /// The closest built-in status, so reports, overdue checks and widgets keep working
    /// for custom pipelines.
    var legacyStatus: ProjectStatus {
        switch self {
        case .notStarted: return .notStarted
        case .working:    return .inProgress
        case .waiting:    return .waitingOnClient
        case .review:     return .inProgress
        case .done:       return .complete
        }
    }
}

enum StageColor: String, Codable, CaseIterable, Identifiable {
    case gray, blue, teal, green, yellow, orange, red, purple
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A task that appears when a job enters a stage.
struct StageTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// Days after the job enters the stage.
    var dueInDays: Int = 1
}

/// What happens automatically when a job enters a stage.
struct StageAutomation: Codable, Equatable {
    var tasks: [StageTask] = []
    /// Reset the job's due date to this many days from now.
    var setDueInDays: Int? = nil

    var isEmpty: Bool { tasks.isEmpty && setDueInDays == nil }
}

struct PipelineStage: Codable, Equatable, Identifiable {
    /// Stable key stored on `Project.stageKey` (a UUID string for custom stages; the
    /// `ProjectStatus` raw value for the built-in pipeline).
    var id: String
    var name: String
    var kind: StageKind
    var color: StageColor
    var automation = StageAutomation()

    init(id: String = UUID().uuidString, name: String, kind: StageKind = .working, color: StageColor = .blue, automation: StageAutomation = StageAutomation()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.color = color
        self.automation = automation
    }
}

struct PipelineDefinition: Equatable {
    var name: String
    var systemImage: String = "rectangle.split.3x1"
    var stages: [PipelineStage]

    // MARK: Lookup

    func index(of key: String) -> Int? { stages.firstIndex { $0.id == key } }
    func stage(withKey key: String) -> PipelineStage? { stages.first { $0.id == key } }
    var firstStage: PipelineStage? { stages.first }

    /// Where a new job starts: the first stage that isn't a waiting stage (waiting is
    /// something you choose, never somewhere a job lands by itself).
    var firstStartStage: PipelineStage? { stages.first { $0.kind != .waiting } ?? stages.first }

    /// The stage "Advance" moves to: the next one that isn't a waiting stage, so waiting /
    /// on-hold stages are only ever entered by choosing them. From a waiting stage it
    /// resumes at the next real stage. Nil at the end (or if the key is unknown).
    func next(after key: String) -> PipelineStage? {
        guard let index = index(of: key) else { return nil }
        return stages.dropFirst(index + 1).first { $0.kind != .waiting }
    }

    /// Columns for a board: finished jobs leave it.
    var boardStages: [PipelineStage] { stages.filter { !$0.kind.isDone } }

    // MARK: Validation

    /// Human-readable problems that should block saving.
    func validationErrors() -> [String] {
        var errors: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { errors.append("Give the pipeline a name.") }
        if stages.count < 2 { errors.append("Add at least two stages.") }
        if stages.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) {
            errors.append("Every stage needs a name.")
        }
        let names = stages.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }
        if Set(names).count != names.count { errors.append("Stage names must be different.") }
        if !stages.contains(where: { $0.kind.isDone }) {
            errors.append("Add a Done stage so finished jobs leave the board.")
        }
        return errors
    }

    // MARK: Built-in pipeline

    /// The built-in pipelines. They are virtual (never stored): a project with no
    /// `pipelineID` lives in the one for its service type, and its stage *is* its
    /// `ProjectStatus` (stage id = the status raw value).
    static let standardName = ServiceType.taxReturn.label

    /// Every service type has its own built-in pipeline (Tax Return, Bookkeeping, Payroll,
    /// Advisory, IRS Notice, Other). Tax returns use the tax stages; the rest start with the
    /// short general list. Replace any of them with a custom pipeline in More ▸ Pipelines.
    static func builtIn(for serviceType: ServiceType) -> PipelineDefinition {
        let flow = StatusFlow.flow(for: serviceType)
        let stages: [PipelineStage] = flow.statuses.map { status in
            PipelineStage(id: status.rawValue, name: flow.label(status), kind: standardKind(status), color: standardColor(status))
        }
        return PipelineDefinition(name: serviceType.label, systemImage: serviceType.systemImage, stages: stages)
    }

    /// The tax-return pipeline.
    static var standard: PipelineDefinition { builtIn(for: .taxReturn) }

    private static func standardKind(_ status: ProjectStatus) -> StageKind {
        switch status {
        case .notStarted:                               return .notStarted
        case .awaitingDocs, .waitingOnClient:           return .waiting
        case .inProgress, .readyToFile, .filed:         return .working
        case .review, .awaitingSignature:               return .review
        case .complete:                                 return .done
        }
    }

    private static func standardColor(_ status: ProjectStatus) -> StageColor {
        switch status {
        case .notStarted:        return .gray
        case .awaitingDocs:      return .orange
        case .inProgress:        return .blue
        case .waitingOnClient:   return .red
        case .review:            return .purple
        case .awaitingSignature: return .yellow
        case .readyToFile:       return .teal
        case .filed:             return .green
        case .complete:          return .green
        }
    }
}

/// How a job looks on a card or badge, for either kind of pipeline.
struct StageInfo: Equatable {
    var name: String
    var color: StageColor
    var systemImage: String
    var isDone: Bool
}

enum PipelineResolver {
    /// - Parameters:
    ///   - definition: the job's custom pipeline, or nil for the built-in one.
    ///   - stageKey: `Project.stageKey`.
    ///   - status: the job's legacy status (authoritative for the built-in pipeline, and
    ///     the fallback when a custom stage has since been deleted).
    static func info(definition: PipelineDefinition?, stageKey: String, status rawStatus: ProjectStatus, flow: StatusFlow = .taxReturn) -> StageInfo {
        let status = flow.normalize(rawStatus)
        if let definition {
            if let stage = definition.stage(withKey: stageKey) {
                return StageInfo(name: stage.name, color: stage.color, systemImage: stage.kind.systemImage, isDone: stage.kind.isDone)
            }
            // The stage was removed from the pipeline — fall back to the coarse status.
        }
        let standard = PipelineDefinition.standard.stage(withKey: status.rawValue)
        return StageInfo(
            name: flow.label(status),
            color: standard?.color ?? .gray,
            systemImage: status.systemImage,
            isDone: status.isComplete
        )
    }
}

/// What entering a stage changes. Applied by `PipelineEngine`.
enum PipelineMove {
    struct NewTask: Equatable {
        var title: String
        var dueDate: Date
        /// The stage's own offset; a task chained behind another is dated from this once
        /// the earlier task is completed, not from `dueDate`.
        var dueInDays: Int = 0
    }

    struct Plan: Equatable {
        var status: ProjectStatus
        var isDone: Bool
        /// New due date for the job, if the stage resets it.
        var dueDate: Date?
        var tasks: [NewTask]
    }

    static func plan(entering stage: PipelineStage, now: Date = .now, calendar: Calendar = .current) -> Plan {
        let today = calendar.startOfDay(for: now)
        func date(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }

        let tasks = stage.automation.tasks
            .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { NewTask(title: $0.title, dueDate: date(max(0, $0.dueInDays)), dueInDays: max(0, $0.dueInDays)) }
        return Plan(
            status: stage.kind.legacyStatus,
            isDone: stage.kind.isDone,
            dueDate: stage.automation.setDueInDays.map { date(max(0, $0)) },
            tasks: tasks
        )
    }
}

/// Ready-made pipelines to start from (the user can edit them freely).
enum PipelineStarters {
    static var all: [PipelineDefinition] { [bookkeeping, onboarding, payroll, irsNotice] }

    // Waiting stages are side states: "Advance" skips them, so they are only entered by
    // choosing them. Entry tasks therefore live on the regular stages.

    static var bookkeeping: PipelineDefinition {
        PipelineDefinition(name: "Bookkeeping", systemImage: "books.vertical.fill", stages: [
            PipelineStage(name: "Not started", kind: .notStarted, color: .gray, automation: StageAutomation(
                tasks: [StageTask(title: "Request bank and card statements", dueInDays: 1)], setDueInDays: nil)),
            PipelineStage(name: "Reconciling", kind: .working, color: .blue),
            PipelineStage(name: "Waiting on client", kind: .waiting, color: .orange),
            PipelineStage(name: "Review", kind: .review, color: .purple, automation: StageAutomation(
                tasks: [StageTask(title: "Send reports to client", dueInDays: 2)], setDueInDays: nil)),
            PipelineStage(name: "Delivered", kind: .done, color: .green),
        ])
    }

    static var onboarding: PipelineDefinition {
        PipelineDefinition(name: "Client Onboarding", systemImage: "person.badge.plus", stages: [
            PipelineStage(name: "Engagement letter", kind: .working, color: .blue, automation: StageAutomation(
                tasks: [StageTask(title: "Send engagement letter", dueInDays: 1)], setDueInDays: 7)),
            PipelineStage(name: "Documents & setup", kind: .working, color: .orange, automation: StageAutomation(
                tasks: [
                    StageTask(title: "Collect prior-year return and IDs", dueInDays: 3),
                    StageTask(title: "Set up in accounting software", dueInDays: 5),
                ], setDueInDays: 14)),
            PipelineStage(name: "Waiting on client", kind: .waiting, color: .red),
            PipelineStage(name: "Kickoff", kind: .working, color: .teal),
            PipelineStage(name: "Active client", kind: .done, color: .green),
        ])
    }

    static var payroll: PipelineDefinition {
        PipelineDefinition(name: "Payroll", systemImage: "banknote.fill", stages: [
            PipelineStage(name: "Collect hours", kind: .notStarted, color: .gray),
            PipelineStage(name: "Run payroll", kind: .working, color: .blue),
            PipelineStage(name: "Waiting on client", kind: .waiting, color: .orange),
            PipelineStage(name: "Deposits & filings", kind: .review, color: .purple),
            PipelineStage(name: "Complete", kind: .done, color: .green),
        ])
    }

    static var irsNotice: PipelineDefinition {
        PipelineDefinition(name: "IRS Notice Response", systemImage: "envelope.badge.shield.half.filled", stages: [
            PipelineStage(name: "Notice received", kind: .notStarted, color: .gray, automation: StageAutomation(
                tasks: [StageTask(title: "Confirm the response deadline on the notice", dueInDays: 1)], setDueInDays: nil)),
            PipelineStage(name: "Gathering information", kind: .working, color: .blue),
            PipelineStage(name: "Waiting on client", kind: .waiting, color: .orange),
            PipelineStage(name: "Drafting response", kind: .working, color: .teal),
            PipelineStage(name: "Review", kind: .review, color: .purple),
            PipelineStage(name: "Response sent", kind: .working, color: .yellow),
            PipelineStage(name: "Resolved", kind: .done, color: .green),
        ])
    }
}

/// Which pipeline new work of each service type starts in. Empty = the built-in one.
enum PipelineDefaults {
    static func key(for serviceType: ServiceType) -> String { "defaultPipeline." + serviceType.rawValue }

    static func pipelineID(for serviceType: ServiceType, defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: key(for: serviceType)).flatMap { UUID(uuidString: $0) }
    }
}
