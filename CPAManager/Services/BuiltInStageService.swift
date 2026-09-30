import Foundation
import SwiftData

/// Store-facing side of `BuiltInSetup`: reads and saves the per-stage tasks of the built-in
/// pipelines.
enum BuiltInSetupService {
    static func resolved(_ context: ModelContext) -> [String: StageAutomation] {
        let records = (try? context.fetch(FetchDescriptor<BuiltInStageSetup>())) ?? []
        return BuiltInSetup.resolve(records.map {
            BuiltInSetupInput(serviceTypeRaw: $0.serviceTypeRaw, stageKey: $0.stageKey, automation: $0.automation, updatedAt: $0.updatedAt)
        })
    }

    static func automation(for service: ServiceType, stageKey: String, context: ModelContext) -> StageAutomation {
        BuiltInSetup.automation(serviceTypeRaw: service.rawValue, stageKey: stageKey, in: resolved(context))
    }

    /// Saves one stage's setup: updates the newest record, removes stray duplicates, and
    /// removes the record entirely when the setup is empty.
    static func save(_ automation: StageAutomation, service: ServiceType, stageKey: String,
                     context: ModelContext, now: Date = .now) {
        let cleaned = BuiltInSetup.cleaned(automation)
        let matching = ((try? context.fetch(FetchDescriptor<BuiltInStageSetup>())) ?? [])
            .filter { $0.serviceTypeRaw == service.rawValue && $0.stageKey == stageKey }
            .sorted { $0.updatedAt > $1.updatedAt }
        if cleaned.isEmpty {
            for record in matching { context.delete(record) }
            return
        }
        if let keep = matching.first {
            if keep.automation != cleaned {
                keep.automation = cleaned
                keep.updatedAt = now
            }
            for extra in matching.dropFirst() { context.delete(extra) }
        } else {
            context.insert(BuiltInStageSetup(service: service, stageKey: stageKey, automation: cleaned, now: now))
        }
    }
}
