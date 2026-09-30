import Foundation

// Pure rules for the tasks each stage of a built-in pipeline creates. No SwiftData.

struct BuiltInSetupInput: Equatable {
    var serviceTypeRaw: String
    var stageKey: String
    var automation: StageAutomation
    var updatedAt: Date
}

enum BuiltInSetup {
    static func key(_ serviceTypeRaw: String, _ stageKey: String) -> String { "\(serviceTypeRaw)|\(stageKey)" }

    /// One automation per (service, stage). If devices created duplicates, the most recently
    /// updated one wins (ties: the one with tasks).
    static func resolve(_ inputs: [BuiltInSetupInput]) -> [String: StageAutomation] {
        var best: [String: BuiltInSetupInput] = [:]
        for input in inputs {
            let k = key(input.serviceTypeRaw, input.stageKey)
            if let current = best[k] {
                let newer = input.updatedAt > current.updatedAt
                let tie = input.updatedAt == current.updatedAt && !input.automation.isEmpty && current.automation.isEmpty
                if newer || tie { best[k] = input }
            } else {
                best[k] = input
            }
        }
        return best.mapValues(\.automation)
    }

    static func automation(serviceTypeRaw: String, stageKey: String, in resolved: [String: StageAutomation]) -> StageAutomation {
        resolved[key(serviceTypeRaw, stageKey)] ?? StageAutomation()
    }

    /// "2 tasks · due in 14 days" / "No tasks" for the editor's stage rows.
    static func summary(_ automation: StageAutomation) -> String {
        let count = automation.tasks.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count
        var parts: [String] = []
        if count > 0 { parts.append("\(count) task\(count == 1 ? "" : "s")") }
        if let days = automation.setDueInDays { parts.append("due in \(days) days") }
        if automation.autoMove { parts.append("automove") }
        return parts.isEmpty ? "No tasks" : parts.joined(separator: " · ")
    }

    /// Blank task titles are dropped before saving.
    static func cleaned(_ automation: StageAutomation) -> StageAutomation {
        var copy = automation
        copy.tasks.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        return copy
    }
}
