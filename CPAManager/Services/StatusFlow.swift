import Foundation

/// Which set of statuses a piece of work uses. Tax returns have their own stages; every
/// other kind of work (bookkeeping, payroll, advisory, IRS notices…) uses a short generic
/// list. The stored `ProjectStatus` values are shared, so nothing about the data model or
/// CloudKit changes — the flow only decides which statuses are offered and how they read.
enum StatusFlow: String, CaseIterable, Identifiable {
    case taxReturn
    case general

    var id: String { rawValue }

    static func flow(for serviceType: ServiceType) -> StatusFlow {
        serviceType == .taxReturn ? .taxReturn : .general
    }

    /// Statuses offered, in display order (the on-hold / waiting status sits after In Progress).
    var statuses: [ProjectStatus] {
        switch self {
        case .taxReturn:
            return [.notStarted, .inProgress, .waitingOnClient, .awaitingSignature, .readyToFile, .filed, .complete]
        case .general:
            return [.notStarted, .inProgress, .waitingOnClient, .complete]
        }
    }

    /// The straight-through path "Advance" follows (the waiting / on-hold status is a side
    /// state, not a step).
    var advanceSequence: [ProjectStatus] {
        statuses.filter { $0 != .waitingOnClient }
    }

    func label(_ status: ProjectStatus) -> String {
        switch (self, status) {
        case (.taxReturn, .waitingOnClient): return "On Hold"
        case (.general, .waitingOnClient):   return "Waiting on Client"
        case (.general, .complete):          return "Completed"
        default:                             return status.label
        }
    }

    /// Maps a status that isn't part of this flow (older data, or a change of service type)
    /// to the closest one that is. Statuses already in the flow are returned unchanged.
    func normalize(_ status: ProjectStatus) -> ProjectStatus {
        if statuses.contains(status) { return status }
        switch (self, status) {
        case (.taxReturn, .awaitingDocs): return .notStarted      // docs not in yet → not started
        case (.general, .awaitingDocs):   return .waitingOnClient
        case (_, .review):                return .inProgress
        case (.general, .filed):          return .complete
        case (.general, .awaitingSignature), (.general, .readyToFile): return .inProgress
        default:                          return .inProgress
        }
    }

    /// The step after `status` on the straight-through path; nil at the end or when waiting.
    func next(after status: ProjectStatus) -> ProjectStatus? {
        let current = normalize(status)
        guard current != .waitingOnClient,
              let index = advanceSequence.firstIndex(of: current),
              index + 1 < advanceSequence.count else { return nil }
        return advanceSequence[index + 1]
    }
}
