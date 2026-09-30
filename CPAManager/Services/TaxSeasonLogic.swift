import Foundation

enum TaxSeasonMode: String, CaseIterable, Identifiable {
    case auto, on, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic (Jan–Apr 20, Oct 1–20)"
        case .on:   return "Always on"
        case .off:  return "Off"
        }
    }
}

struct SeasonProject: Equatable {
    var statusRaw: String
    var taxYear: Int
    var isTaxReturn: Bool
}

struct SeasonClient: Equatable {
    var isActive: Bool
    var extensionYears: Set<Int>
    var hasReturnForYear: Bool
}

struct TaxSeasonSummary: Equatable {
    struct StageCount: Equatable, Identifiable {
        var status: ProjectStatus
        var count: Int
        var id: String { status.rawValue }
    }

    var taxYear: Int
    var deadline: Date
    var daysToDeadline: Int
    var stages: [StageCount]
    var openReturns: Int
    var noReturnStarted: Int
    var onExtension: Int
    var documentsOutstanding: Int
}

enum TaxSeason {
    /// Automatic season: Jan 1 – Apr 20, and the extension push Oct 1 – Oct 20.
    static func isActive(mode: TaxSeasonMode, now: Date = .now, calendar: Calendar = .current) -> Bool {
        switch mode {
        case .on:  return true
        case .off: return false
        case .auto:
            let month = calendar.component(.month, from: now)
            let day = calendar.component(.day, from: now)
            if month <= 3 { return true }
            if month == 4 { return day <= 20 }
            if month == 10 { return day <= 20 }
            return false
        }
    }

    /// The tax year being worked on: the prior calendar year (2026 season → 2025 returns).
    static func workingTaxYear(now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: now) - 1
    }

    /// The next filing deadline on or after `now`: April 15 (individual/C-corp-style) until
    /// it passes, then October 15 (extended), then next April. Shifted off weekends/holidays.
    static func nextDeadline(now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        for candidateYear in [year, year + 1] {
            for month in [4, 10] {
                guard let base = calendar.date(from: DateComponents(year: candidateYear, month: month, day: 15)) else { continue }
                let due = TaxCalendar.nextBusinessDay(onOrAfter: base, calendar: calendar)
                if due >= today { return due }
            }
        }
        return today
    }

    static func summary(
        projects: [SeasonProject],
        clients: [SeasonClient],
        documentsOutstanding: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaxSeasonSummary {
        let taxYear = workingTaxYear(now: now, calendar: calendar)
        let deadline = nextDeadline(now: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: deadline).day ?? 0

        let flow = StatusFlow.taxReturn
        // Older statuses (Awaiting Docs, In Review) are counted under the stage they map to.
        let open = projects.filter { $0.isTaxReturn && $0.taxYear == taxYear }
            .map { flow.normalize(ProjectStatus(rawValue: $0.statusRaw) ?? .notStarted) }
            .filter { $0 != .complete }
        let stages: [TaxSeasonSummary.StageCount] = flow.statuses
            .filter { $0 != .complete }
            .compactMap { status -> TaxSeasonSummary.StageCount? in
                let count = open.filter { $0 == status }.count
                return count > 0 ? TaxSeasonSummary.StageCount(status: status, count: count) : nil
            }

        return TaxSeasonSummary(
            taxYear: taxYear,
            deadline: deadline,
            daysToDeadline: max(0, days),
            stages: stages,
            openReturns: open.count,
            noReturnStarted: clients.filter { $0.isActive && !$0.hasReturnForYear && !$0.extensionYears.contains(taxYear) }.count,
            onExtension: clients.filter { $0.isActive && $0.extensionYears.contains(taxYear) }.count,
            documentsOutstanding: documentsOutstanding
        )
    }
}
