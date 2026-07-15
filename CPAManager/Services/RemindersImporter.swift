import Foundation
import EventKit
import SwiftData

// MARK: - Preview data (staged, not yet written to SwiftData)

struct ImportPreview {
    var newClientNames: [String]
    var projects: [ProposedProject]
    var recurring: [ProposedRecurring]
    /// Entity types inferred from tax-return titles (e.g. "1120-S"), keyed by
    /// lowercased client name — used by `commit` when creating new clients.
    var entityHints: [String: EntityType]

    var isEmpty: Bool { projects.isEmpty && recurring.isEmpty }
}

struct ProposedProject: Identifiable {
    let id = UUID()
    var title: String
    var clientName: String?
    var status: ProjectStatus
    var serviceType: ServiceType
    var dueDate: Date?
    var receivedDate: Date?
    var nextAction: String
    var holdReason: HoldReason?
    var holdDetail: String
    var holdResumeStatus: ProjectStatus?
    var taxYear: Int?
    var sourceList: String
    var isDuplicate: Bool = false
    var isIncluded: Bool = true
}

struct ProposedRecurring: Identifiable {
    let id = UUID()
    var name: String
    var clientName: String?
    var frequency: Frequency
    var serviceType: ServiceType
    var nextDueDate: Date
    var sourceList: String
    var isDuplicate: Bool = false
    var isIncluded: Bool = true
}

/// One-time migration from the firm's existing Apple Reminders workflow into
/// SwiftData. Read-only against Reminders — it never modifies or completes
/// anything there, and never re-imports items that already appear to exist.
enum RemindersImporter {

    // MARK: Access

    static func requestAccess() async -> Bool {
        let store = EKEventStore()
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: Build preview

    static func buildPreview(
        existingClientNames: Set<String>,
        existingProjectTitles: Set<String>,
        existingRecurringNames: Set<String>
    ) async -> ImportPreview {
        let store = EKEventStore()
        let calendars = store.calendars(for: .reminder)

        var projects: [ProposedProject] = []
        var recurring: [ProposedRecurring] = []
        var entityHints: [String: EntityType] = [:]

        for calendar in calendars {
            let listName = calendar.title.trimmingCharacters(in: .whitespaces)
            let reminders = await fetchIncompleteReminders(store: store, calendar: calendar)

            switch listKind(for: listName) {
            case .stage(let status):
                for reminder in reminders {
                    guard let project = parseStageReminder(reminder, listStatus: status, listName: listName) else { continue }
                    if let name = project.clientName, let type = project.inferredEntityType {
                        entityHints[name.lowercased()] = type
                    }
                    projects.append(project.proposed)
                }
            case .bookkeeping:
                for reminder in reminders {
                    if let item = parseBookkeeping(reminder, listName: listName) { recurring.append(item) }
                }
            case .recurringSchedule(let serviceType):
                for reminder in reminders {
                    if let item = parseSchedule(reminder, serviceType: serviceType, listName: listName) { recurring.append(item) }
                }
            case .unknown:
                for reminder in reminders {
                    projects.append(genericProject(reminder, listName: listName))
                }
            }
        }

        // Flag likely duplicates so the user can review rather than blindly re-import.
        for index in projects.indices {
            let key = projects[index].title.trimmingCharacters(in: .whitespaces).lowercased()
            if existingProjectTitles.contains(key) {
                projects[index].isDuplicate = true
                projects[index].isIncluded = false
            }
        }
        for index in recurring.indices {
            let key = recurring[index].name.trimmingCharacters(in: .whitespaces).lowercased()
            if existingRecurringNames.contains(key) {
                recurring[index].isDuplicate = true
                recurring[index].isIncluded = false
            }
        }

        let allClientNames = Set(
            (projects.compactMap(\.clientName) + recurring.compactMap(\.clientName))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let newClientNames = allClientNames
            .filter { !existingClientNames.contains($0.lowercased()) }
            .sorted()

        return ImportPreview(
            newClientNames: newClientNames,
            projects: projects,
            recurring: recurring,
            entityHints: entityHints
        )
    }

    // MARK: Commit

    @discardableResult
    static func commit(
        preview: ImportPreview,
        context: ModelContext
    ) -> (clients: Int, projects: Int, recurring: Int) {
        var clientsByName: [String: Client] = [:]
        if let existing = try? context.fetch(FetchDescriptor<Client>()) {
            for client in existing { clientsByName[client.displayName.lowercased()] = client }
        }

        var clientsCreated = 0
        func resolveClient(_ name: String?) -> Client? {
            guard let name, !name.isEmpty else { return nil }
            let key = name.lowercased()
            if let existing = clientsByName[key] { return existing }
            let entityType = preview.entityHints[key] ?? .other
            let created = Client(name: name, entityType: entityType)
            context.insert(created)
            clientsByName[key] = created
            clientsCreated += 1
            return created
        }

        var projectsCreated = 0
        for proposal in preview.projects where proposal.isIncluded {
            let client = resolveClient(proposal.clientName)
            let project = Project(
                title: proposal.title,
                status: proposal.status,
                serviceType: proposal.serviceType,
                dueDate: proposal.dueDate,
                taxYear: proposal.taxYear,
                client: client
            )
            project.receivedDate = proposal.receivedDate
            project.nextAction = proposal.nextAction
            if let reason = proposal.holdReason {
                project.holdReason = reason
                project.holdDetail = proposal.holdDetail
                project.holdResumeStatusRaw = (proposal.holdResumeStatus ?? .inProgress).rawValue
            }
            context.insert(project)
            projectsCreated += 1
        }

        var recurringCreated = 0
        for proposal in preview.recurring where proposal.isIncluded {
            let client = resolveClient(proposal.clientName)
            let engagement = RecurringEngagement(
                name: proposal.name,
                frequency: proposal.frequency,
                serviceType: proposal.serviceType,
                nextDueDate: proposal.nextDueDate,
                client: client
            )
            context.insert(engagement)
            recurringCreated += 1
        }

        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)

        return (clientsCreated, projectsCreated, recurringCreated)
    }

    // MARK: List classification

    private enum ListKind {
        case stage(ProjectStatus)
        case bookkeeping
        case recurringSchedule(ServiceType)
        case unknown
    }

    private static let stageListNames: [String: ProjectStatus] = [
        "not started": .notStarted,
        "awaiting docs": .awaitingDocs,
        "in progress": .inProgress,
        "on hold": .waitingOnClient,
        "in review": .review,
        "awaiting signature": .awaitingSignature,
        "ready to file": .readyToFile,
        "filed": .filed,
        "complete": .complete,
    ]

    private static func listKind(for listName: String) -> ListKind {
        let key = listName.lowercased()
        if let status = stageListNames[key] { return .stage(status) }
        if key == "bookkeeping" { return .bookkeeping }
        if key == "payroll" { return .recurringSchedule(.payroll) }
        if key == "sales tax" { return .recurringSchedule(.other) }
        return .unknown
    }

    // MARK: Fetching

    private static func fetchIncompleteReminders(store: EKEventStore, calendar: EKCalendar) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    // MARK: Tax-return / generic stage-list parsing

    private static let holdReasonLabels: [(HoldReason, String)] = [
        (.waitingOnClient, "Waiting on Client"),
        (.waitingOnRelatedEntity, "Waiting on Related Entity"),
        (.waitingOnBookkeeping, "Waiting on Bookkeeping"),
        (.other, "Other"),
    ]

    /// Maps the return-type code embedded in a title (e.g. "1120-S") to the entity
    /// type used elsewhere in the app. Matched as a full case-insensitive string
    /// equality, so the list order below doesn't affect correctness.
    private static let returnTypeToEntity: [(String, EntityType)] = [
        ("1120-S", .sCorp1120S),
        ("1040", .individual1040),
        ("1041", .trust1041),
        ("1065", .partnership1065),
        ("1120", .cCorp1120),
        ("990", .nonProfit990),
    ]

    private static func extractHoldSuffix(from title: String) -> (base: String, reason: HoldReason, detail: String)? {
        for (reason, label) in holdReasonLabels {
            let marker = " - \(label) - "
            if let range = title.range(of: marker) {
                let base = String(title[title.startIndex..<range.lowerBound])
                let detail = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (base, reason, detail)
            }
        }
        return nil
    }

    private struct StageParseResult {
        var proposed: ProposedProject
        var clientName: String? { proposed.clientName }
        var inferredEntityType: EntityType?
    }

    private static func parseStageReminder(
        _ reminder: EKReminder,
        listStatus: ProjectStatus,
        listName: String
    ) -> StageParseResult? {
        let rawTitle = (reminder.title ?? "").trimmingCharacters(in: .whitespaces)
        guard !rawTitle.isEmpty else { return nil }

        let holdInfo = extractHoldSuffix(from: rawTitle)
        let baseTitle = holdInfo?.base.trimmingCharacters(in: .whitespaces) ?? rawTitle
        let components = baseTitle.components(separatedBy: " - ")

        var clientName: String?
        var taxYear: Int?
        var serviceType: ServiceType = .other
        var inferredEntity: EntityType?

        if components.count >= 3,
           components[0].count == 4, let year = Int(components[0]),
           let lastComponent = components.last,
           let match = returnTypeToEntity.first(where: { $0.0.caseInsensitiveCompare(lastComponent) == .orderedSame }) {
            taxYear = year
            clientName = components[1..<components.count - 1].joined(separator: " - ")
            serviceType = .taxReturn
            inferredEntity = match.1
        }

        var status = listStatus
        var holdReason: HoldReason?
        var holdDetail = ""
        var holdResumeStatus: ProjectStatus?
        var receivedDate: Date?
        var nextAction = ""

        if let holdInfo {
            status = .waitingOnClient
            holdReason = holdInfo.reason
            holdDetail = holdInfo.detail
            holdResumeStatus = parseResumeStage(from: reminder.notes)
        } else {
            (receivedDate, nextAction) = parseReceivedAndNext(from: reminder.notes)
        }

        let proposed = ProposedProject(
            title: baseTitle,
            clientName: clientName,
            status: status,
            serviceType: serviceType,
            dueDate: dueDate(of: reminder),
            receivedDate: receivedDate,
            nextAction: nextAction,
            holdReason: holdReason,
            holdDetail: holdDetail,
            holdResumeStatus: holdResumeStatus,
            taxYear: taxYear,
            sourceList: listName
        )
        return StageParseResult(proposed: proposed, inferredEntityType: inferredEntity)
    }

    private static func parseResumeStage(from notes: String?) -> ProjectStatus? {
        guard let notes else { return nil }
        let firstLine = notes.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return stageListNames[firstLine]
    }

    private static func parseReceivedAndNext(from notes: String?) -> (Date?, String) {
        guard let notes else { return (nil, "") }
        var received: Date?
        var next = ""
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("received:") {
                let value = trimmed.dropFirst("received:".count).trimmingCharacters(in: .whitespaces)
                received = parseFlexibleDate(String(value))
            } else if let range = trimmed.range(of: "next:", options: .caseInsensitive) {
                next = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return (received, next)
    }

    private static func parseFlexibleDate(_ text: String) -> Date? {
        let formats = ["MMM d, yyyy 'at' h:mm a", "M/d/yy, h:mm a", "MMM d, yyyy", "M/d/yy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func genericProject(_ reminder: EKReminder, listName: String) -> ProposedProject {
        ProposedProject(
            title: (reminder.title ?? "Untitled").trimmingCharacters(in: .whitespaces),
            clientName: nil,
            status: .notStarted,
            serviceType: .other,
            dueDate: dueDate(of: reminder),
            receivedDate: nil,
            nextAction: "",
            holdReason: nil,
            holdDetail: "",
            holdResumeStatus: nil,
            taxYear: nil,
            sourceList: listName
        )
    }

    // MARK: Bookkeeping ("Client - MM/YYYY")

    private static func parseBookkeeping(_ reminder: EKReminder, listName: String) -> ProposedRecurring? {
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var clientName = title
        if let range = title.range(of: " - ", options: .backwards) {
            let candidate = String(title[title.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty { clientName = candidate }
        }

        return ProposedRecurring(
            name: title,
            clientName: clientName,
            frequency: .monthly,
            serviceType: .bookkeeping,
            nextDueDate: dueDate(of: reminder) ?? .now,
            sourceList: listName
        )
    }

    // MARK: Payroll / Sales Tax

    private static let schedulePrefixes = ["Send Preview - ", "Process Payroll - ", "Pay Payroll Tax - "]
    private static let scheduleSuffixes = [" - 401K Deposit"]

    private static func parseSchedule(_ reminder: EKReminder, serviceType: ServiceType, listName: String) -> ProposedRecurring? {
        let title = (reminder.title ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        var clientName = title
        for prefix in schedulePrefixes where clientName.hasPrefix(prefix) {
            clientName = String(clientName.dropFirst(prefix.count))
        }
        for suffix in scheduleSuffixes where clientName.hasSuffix(suffix) {
            clientName = String(clientName.dropLast(suffix.count))
        }
        clientName = clientName.trimmingCharacters(in: .whitespaces)

        let frequency = reminder.recurrenceRules?.first.map(mapFrequency) ?? .monthly

        return ProposedRecurring(
            name: title,
            clientName: clientName.isEmpty ? nil : clientName,
            frequency: frequency,
            serviceType: serviceType,
            nextDueDate: dueDate(of: reminder) ?? .now,
            sourceList: listName
        )
    }

    private static func mapFrequency(_ rule: EKRecurrenceRule) -> Frequency {
        switch rule.frequency {
        case .weekly:  return rule.interval >= 2 ? .biweekly : .weekly
        case .monthly: return rule.interval >= 3 ? .quarterly : .monthly
        case .yearly:  return .annually
        default:       return .monthly
        }
    }

    private static func dueDate(of reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    }
}
