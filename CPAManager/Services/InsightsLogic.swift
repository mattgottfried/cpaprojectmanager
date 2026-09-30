import Foundation

// Pure logic for the Insights dashboard: job counters, jobs by stage, tasks to do, planned vs
// done per week, and which widgets are shown. No SwiftData, no SwiftUI. Unit-tested.

struct InsightsJob: Identifiable, Equatable {
    var id: UUID
    var title: String
    var clientName: String
    var serviceTypeRaw: String
    var stageName: String
    /// Position of the stage within its pipeline (for ordering bars).
    var stageOrder: Int
    var isComplete: Bool
    var isInProgress: Bool
    var dueDate: Date?
    /// The latest thing that happened on the job: a task added or finished, time logged, a
    /// document added, or the job itself created.
    var lastActivity: Date
}

struct StageCount: Identifiable, Equatable {
    var serviceTypeRaw: String
    var stageName: String
    var order: Int
    var count: Int
    var id: String { "\(serviceTypeRaw)|\(stageName)" }
}

enum JobInsights {
    /// TaxDome's "approaching deadline" asks for jobs due on one specific day.
    enum ApproachingDay: Int, CaseIterable, Identifiable {
        case today = 0, tomorrow = 1, dayAfter = 2, inAWeek = 7

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .today:    return "Today"
            case .tomorrow: return "Tomorrow"
            case .dayAfter: return "Day after tomorrow"
            case .inAWeek:  return "In a week"
            }
        }
    }

    static let noActivityChoices = [3, 7, 14, 30]

    static func open(_ jobs: [InsightsJob]) -> [InsightsJob] { jobs.filter { !$0.isComplete } }

    static func approaching(_ jobs: [InsightsJob], on day: ApproachingDay, now: Date = .now, calendar: Calendar = .current) -> [InsightsJob] {
        guard let target = calendar.date(byAdding: .day, value: day.rawValue, to: calendar.startOfDay(for: now)) else { return [] }
        return open(jobs)
            .filter { job in job.dueDate.map { calendar.isDate($0, inSameDayAs: target) } ?? false }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func overdue(_ jobs: [InsightsJob], now: Date = .now, calendar: Calendar = .current) -> [InsightsJob] {
        let today = calendar.startOfDay(for: now)
        return open(jobs)
            .filter { job in job.dueDate.map { calendar.startOfDay(for: $0) < today } ?? false }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    static func inProgress(_ jobs: [InsightsJob]) -> [InsightsJob] {
        open(jobs).filter(\.isInProgress)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Open jobs where nothing has happened for more than `days` days, oldest first.
    static func noActivity(_ jobs: [InsightsJob], overDays days: Int, now: Date = .now, calendar: Calendar = .current) -> [InsightsJob] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return [] }
        return open(jobs).filter { $0.lastActivity < cutoff }.sorted { $0.lastActivity < $1.lastActivity }
    }

    /// Open jobs per stage, service by service, in pipeline order.
    static func byStage(_ jobs: [InsightsJob]) -> [StageCount] {
        var counts: [String: StageCount] = [:]
        for job in open(jobs) {
            let key = "\(job.serviceTypeRaw)|\(job.stageName)"
            if var existing = counts[key] { existing.count += 1; counts[key] = existing }
            else { counts[key] = StageCount(serviceTypeRaw: job.serviceTypeRaw, stageName: job.stageName, order: job.stageOrder, count: 1) }
        }
        return counts.values.sorted { a, b in
            if a.serviceTypeRaw != b.serviceTypeRaw { return a.serviceTypeRaw < b.serviceTypeRaw }
            if a.order != b.order { return a.order < b.order }
            return a.stageName < b.stageName
        }
    }
}

struct PriorityGroup: Identifiable, Equatable {
    var priority: Priority
    var rows: [TaskTableRow]
    var id: String { priority.rawValue }
}

struct WeekPoint: Identifiable, Equatable {
    var weekStart: Date
    /// Tasks due that week.
    var planned: Int
    /// Tasks completed that week.
    var done: Int
    var id: Date { weekStart }
}

enum TaskInsights {
    /// Pending tasks due on `date` (and, when that's today, anything overdue). Tasks waiting
    /// on another task aren't "to do" yet.
    static func toDo(_ rows: [TaskTableRow], on date: Date, now: Date = .now, calendar: Calendar = .current) -> [TaskTableRow] {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let today = calendar.startOfDay(for: now)
        return rows.filter { row in
            guard !row.isDone, !row.isBlocked, let due = row.dueDate else { return false }
            if calendar.isDate(due, inSameDayAs: date) { return true }
            return isToday && calendar.startOfDay(for: due) < today
        }
        .sorted { TaskTable.isOrdered($0, $1, by: TaskSort(key: .due, ascending: true)) }
    }

    /// High, normal, low — only the groups that have tasks.
    static func byPriority(_ rows: [TaskTableRow]) -> [PriorityGroup] {
        Priority.allCases.sorted { $0.order < $1.order }.compactMap { (priority: Priority) -> PriorityGroup? in
            let inGroup = rows.filter { $0.priority == priority }
            return inGroup.isEmpty ? nil : PriorityGroup(priority: priority, rows: inGroup)
        }
    }

    /// The last `weeks` weeks (oldest first, the current week last): tasks planned (due) and
    /// done (completed) in each.
    static func weekly(_ rows: [TaskTableRow], weeks: Int = 8, now: Date = .now, calendar: Calendar = .current) -> [WeekPoint] {
        guard weeks > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<weeks).reversed().compactMap { (back: Int) -> WeekPoint? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: current.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let planned = rows.filter { row in row.dueDate.map { $0 >= start && $0 < end } ?? false }.count
            let done = rows.filter { row in row.completedAt.map { $0 >= start && $0 < end } ?? false }.count
            return WeekPoint(weekStart: start, planned: planned, done: done)
        }
    }

    /// Done ÷ planned over the points; nil when nothing was planned.
    static func completionRate(_ points: [WeekPoint]) -> Double? {
        let planned = points.reduce(0) { $0 + $1.planned }
        guard planned > 0 else { return nil }
        let done = points.reduce(0) { $0 + min($1.done, $1.planned) }
        return Double(done) / Double(planned)
    }
}

// MARK: - Which widgets show

enum InsightsWidget: String, CaseIterable, Identifiable {
    case tasksToDo, jobs, jobsByStage, plannedVsDone, moneyTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasksToDo:     return "Tasks to do"
        case .jobs:          return "Jobs"
        case .jobsByStage:   return "Jobs by stage"
        case .plannedVsDone: return "Planned vs done"
        case .moneyTime:     return "Money and time"
        }
    }
}

struct InsightsSlot: Identifiable, Equatable {
    var widget: InsightsWidget
    var isVisible: Bool
    var id: String { widget.id }
}

enum InsightsLayout {
    /// "tasksToDo,jobs,…" in order; "-" = everything hidden; empty = the default (all, in order).
    static func slots(from raw: String) -> [InsightsSlot] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return InsightsWidget.allCases.map { InsightsSlot(widget: $0, isVisible: true) } }
        let shown = trimmed == "-" ? [] : trimmed.split(separator: ",").compactMap { InsightsWidget(rawValue: String($0)) }
        var seen = Set<InsightsWidget>()
        var slots: [InsightsSlot] = []
        for widget in shown where seen.insert(widget).inserted { slots.append(InsightsSlot(widget: widget, isVisible: true)) }
        // Widgets added in a later version appear at the end, hidden until switched on.
        for widget in InsightsWidget.allCases where !seen.contains(widget) { slots.append(InsightsSlot(widget: widget, isVisible: false)) }
        return slots
    }

    static func encode(_ slots: [InsightsSlot]) -> String {
        let visible = slots.filter(\.isVisible).map(\.widget.rawValue)
        return visible.isEmpty ? "-" : visible.joined(separator: ",")
    }

    static func visible(from raw: String) -> [InsightsWidget] {
        slots(from: raw).filter(\.isVisible).map(\.widget)
    }
}
