import Foundation
import SwiftData

/// Writes parsed import plans into the store. The parsing/mapping rules are pure and
/// live in `ImportLogic.swift`.
enum ImportService {
    struct ExistingKeys {
        var emails: Set<String>
        var names: Set<String>
    }

    static func existingKeys(context: ModelContext) -> ExistingKeys {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        return ExistingKeys(
            emails: Set(clients.map { $0.email.lowercased() }.filter { !$0.isEmpty }),
            names: Set(clients.map { $0.displayName.lowercased() })
        )
    }

    @discardableResult
    static func importClients(_ plan: ClientImportPlan, context: ModelContext) -> Int {
        for record in plan.records {
            let client = Client(
                name: record.name, company: record.company,
                entityType: EntityType(rawValue: record.entityTypeRaw) ?? .other,
                status: .active, email: record.email, phone: record.phone, notes: record.notes
            )
            client.tagsRaw = TagSet.encode(record.tags)
            context.insert(client)
        }
        try? context.save()
        return plan.records.count
    }

    struct TimeResult: Equatable {
        var imported = 0
        var unmatchedClients = 0
    }

    static func importTime(_ plan: TimeImportPlan, defaultRate: Double, context: ModelContext) -> TimeResult {
        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var result = TimeResult()

        for record in plan.records {
            let clientKey = record.clientName.lowercased()
            let client = clientKey.isEmpty ? nil : clients.first {
                $0.displayName.lowercased() == clientKey || $0.name.lowercased() == clientKey
            }
            if !clientKey.isEmpty && client == nil { result.unmatchedClients += 1 }

            let projectKey = record.projectTitle.lowercased()
            let project = projectKey.isEmpty ? nil : projects.first { candidate in
                candidate.title.lowercased() == projectKey && (client == nil || candidate.client?.id == client?.id)
            }

            let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: record.date) ?? record.date
            let end = start.addingTimeInterval(record.hours * 3600)
            let rate = record.rate ?? RateResolver.rate(
                clientOverride: (project?.client ?? client)?.hourlyRateOverride ?? 0, defaultRate: defaultRate
            )
            let entry = TimeEntry(startedAt: start, endedAt: end, notes: record.notes, isBillable: record.isBillable, hourlyRate: rate, project: project)
            if project == nil {
                entry.projectTitle = record.projectTitle
                entry.clientName = client?.displayName ?? record.clientName
            }
            context.insert(entry)
            result.imported += 1
        }
        try? context.save()
        return result
    }
}
