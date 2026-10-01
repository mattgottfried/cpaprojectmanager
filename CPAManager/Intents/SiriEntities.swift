import AppIntents
import SwiftData
import Foundation

/// A client, as Siri and Shortcuts see one.
struct ClientEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Client"
    static var defaultQuery = ClientEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ClientEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ClientEntity] {
        await MainActor.run {
            Self.allClients().filter { identifiers.contains($0.id) }.map { ClientEntity(id: $0.id, name: $0.displayName) }
        }
    }

    func entities(matching string: String) async throws -> [ClientEntity] {
        await MainActor.run {
            let needle = GlobalSearch.normalize(string)
            return Self.allClients()
                .filter { GlobalSearch.normalize($0.displayName).contains(needle) || GlobalSearch.normalize($0.company).contains(needle) }
                .map { ClientEntity(id: $0.id, name: $0.displayName) }
        }
    }

    func suggestedEntities() async throws -> [ClientEntity] {
        await MainActor.run {
            Self.allClients()
                .filter { $0.status == .active }
                .sorted { ($0.lastContactedAt ?? .distantPast) > ($1.lastContactedAt ?? .distantPast) }
                .prefix(10)
                .map { ClientEntity(id: $0.id, name: $0.displayName) }
        }
    }

    @MainActor
    private static func allClients() -> [Client] {
        (try? Persistence.shared.container.mainContext.fetch(FetchDescriptor<Client>())) ?? []
    }
}

/// "Hey Siri, what's up with Dana Lee in CPA Manager?"
struct ClientStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Client Status"
    static var description = IntentDescription(
        "Hear a quick summary of a client: open work, last contact, follow-up, and what they owe.",
        categoryName: "Clients"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Client")
    var client: ClientEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the status of \(\.$client)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let id = client.id
        guard let record = try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.id == id })).first else {
            return .result(dialog: IntentDialog(stringLiteral: "I couldn't find that client."))
        }
        let outstanding = record.invoiceList
            .filter { $0.status == .sent }
            .reduce(0.0) { $0 + $1.balance }
        let text = Briefing.client(
            name: record.displayName,
            openProjects: record.openProjects.count,
            lastContact: ClientActivity.lastContactLabel(record.lastContactedAt),
            followUp: record.followUpDate,
            outstanding: outstanding
        )
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// "Open Dana Lee in CPA Manager."
struct OpenClientIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Client"
    static var description = IntentDescription("Opens a client in CPA Manager.", categoryName: "Clients")
    static var openAppWhenRun = true

    @Parameter(title: "Client")
    var client: ClientEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$client)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app picks this up as it comes forward (see RootView.applyHandoffs).
        PendingCaptures.requestOpen(DeepLink.client(client.id).identifier)
        return .result()
    }
}

/// "Hey Siri, what's on my plate in CPA Manager?"
struct TodaySummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "What's on My Plate"
    static var description = IntentDescription("Hear what's overdue, due today, and next up.", categoryName: "Today")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        SnapshotBuilder.rebuild(context: context)
        let snapshot = DashboardSnapshot.load()
        let text = Briefing.today(
            overdue: snapshot.overdueCount,
            dueToday: snapshot.dueTodayCount,
            inbox: snapshot.inboxCount ?? 0,
            next: (snapshot.todayItems ?? []).map { $0.title }
        )
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// "Hey Siri, what's due this week in CPA Manager?"
struct WeekSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Due This Week"
    static var description = IntentDescription("Hear what's overdue and what's due in the next seven days.", categoryName: "Today")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.shared.container.mainContext
        let tasks = ((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).filter { $0.project?.status.isComplete != true }
        let openIDs = Set(tasks.filter { !$0.isDone }.map(\.id))
        let inputs = tasks.map { task in
            WeekTaskInput(
                id: task.id, title: task.title, subtitle: task.project?.title ?? "", dueDate: task.dueDate, isDone: task.isDone,
                isBlocked: TaskDependencies.isBlocked(blockedByID: task.blockedByID, openTaskIDs: openIDs),
                isHigh: task.priority == .high, snoozedUntil: task.snoozedUntil
            )
        }
        let text = Briefing.week(overdue: WeekAgenda.overdueCount(inputs), entries: WeekAgenda.entries(inputs))
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}
