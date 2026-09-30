import Foundation

// Pure logic for the Tasks page (table, board, calendar): rows, filters, sorting, grouping,
// presets. No SwiftData, no SwiftUI. Unit-tested.

enum TaskStatus: String, CaseIterable, Identifiable, Codable {
    case none = ""
    case inProgress, waitingClient, waitingAgency, onHold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:          return "No status"
        case .inProgress:    return "In progress"
        case .waitingClient: return "Waiting for client"
        case .waitingAgency: return "Waiting for agency"
        case .onHold:        return "On hold"
        }
    }

    var state: SemanticState {
        switch self {
        case .none:          return .neutral
        case .inProgress:    return .info
        case .waitingClient: return .caution
        case .waitingAgency: return .alert
        case .onHold:        return .neutral
        }
    }
}

enum TaskTab: String, CaseIterable, Identifiable {
    case pending = "Pending"
    case completed = "Completed"
    var id: String { rawValue }
}

struct TaskTableRow: Identifiable, Equatable {
    var id: UUID
    var title: String
    var jobID: UUID?
    var jobTitle: String
    var clientID: UUID?
    var clientName: String
    var stageName: String
    var serviceTypeRaw: String
    var status: TaskStatus
    var priority: Priority
    var dueDate: Date?
    var startDate: Date?
    var createdAt: Date
    var completedAt: Date?
    var isDone: Bool
    /// Waiting for another task to be completed first.
    var isBlocked: Bool
    var subtasksDone: Int
    var subtasksTotal: Int

    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard !isDone, let dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}

// MARK: - Due buckets

enum TaskDueBucket: Int, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, later, none

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later:    return "Later"
        case .none:     return "No due date"
        }
    }

    static func bucket(for due: Date?, now: Date = .now, calendar: Calendar = .current) -> TaskDueBucket {
        guard let due else { return .none }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        if day < today { return .overdue }
        if day == today { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), day == tomorrow { return .tomorrow }
        if let week = calendar.dateInterval(of: .weekOfYear, for: today), day < week.end { return .thisWeek }
        return .later
    }
}

enum TaskDueRange: String, CaseIterable, Identifiable, Codable {
    case overdue, today, thisWeek, next7, noDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Due today"
        case .thisWeek: return "Due this week"
        case .next7:    return "Next 7 days"
        case .noDate:   return "No due date"
        }
    }

    func matches(_ due: Date?, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let due else { return self == .noDate }
        let day = calendar.startOfDay(for: due)
        switch self {
        case .overdue:  return day < today
        case .today:    return day == today
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return false }
            return day >= week.start && day < week.end
        case .next7:
            guard let end = calendar.date(byAdding: .day, value: 7, to: today) else { return false }
            return day >= today && day < end
        case .noDate:   return false
        }
    }
}

// MARK: - Filter, sort, group

struct TaskFilter: Equatable, Codable {
    var search = ""
    var clientID: UUID? = nil
    var jobID: UUID? = nil
    var serviceTypeRaw: String? = nil
    var stageName: String? = nil
    var priority: Priority? = nil
    var status: TaskStatus? = nil
    var due: TaskDueRange? = nil
    var hideBlocked = false

    /// How many filters are on (search counts as one).
    var activeCount: Int {
        var count = 0
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        if clientID != nil { count += 1 }
        if jobID != nil { count += 1 }
        if serviceTypeRaw != nil { count += 1 }
        if stageName != nil { count += 1 }
        if priority != nil { count += 1 }
        if status != nil { count += 1 }
        if due != nil { count += 1 }
        if hideBlocked { count += 1 }
        return count
    }

    var isEmpty: Bool { activeCount == 0 }

    func matches(_ row: TaskTableRow, now: Date = .now, calendar: Calendar = .current) -> Bool {
        if let clientID, row.clientID != clientID { return false }
        if let jobID, row.jobID != jobID { return false }
        if let serviceTypeRaw, row.serviceTypeRaw != serviceTypeRaw { return false }
        if let stageName, row.stageName != stageName { return false }
        if let priority, row.priority != priority { return false }
        if let status, row.status != status { return false }
        if let due, !due.matches(row.dueDate, now: now, calendar: calendar) { return false }
        if hideBlocked && row.isBlocked { return false }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hit = row.title.localizedCaseInsensitiveContains(q)
                || row.jobTitle.localizedCaseInsensitiveContains(q)
                || row.clientName.localizedCaseInsensitiveContains(q)
            if !hit { return false }
        }
        return true
    }
}

enum TaskSortKey: String, CaseIterable, Identifiable, Codable {
    case name, job, account, status, due, priority, created, start, completed
    var id: String { rawValue }
}

struct TaskSort: Equatable, Codable {
    var key: TaskSortKey = .due
    var ascending = true
}

enum TaskGrouping: String, CaseIterable, Identifiable, Codable {
    case none, due, client, job, stage, priority, status

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     return "No grouping"
        case .due:      return "Due date"
        case .client:   return "Client"
        case .job:      return "Job"
        case .stage:    return "Stage"
        case .priority: return "Priority"
        case .status:   return "Status"
        }
    }
}

struct TaskGroup: Identifiable, Equatable {
    var id: String
    var title: String
    var rows: [TaskTableRow]
}

enum TaskTable {
    /// Filter, sort and group the rows for one tab.
    static func apply(
        _ rows: [TaskTableRow], tab: TaskTab, filter: TaskFilter, sort: TaskSort, grouping: TaskGrouping,
        now: Date = .now, calendar: Calendar = .current
    ) -> [TaskGroup] {
        let shown = rows
            .filter { tab == .pending ? !$0.isDone : $0.isDone }
            .filter { filter.matches($0, now: now, calendar: calendar) }
            .sorted { isOrdered($0, $1, by: sort) }
        return group(shown, by: grouping, now: now, calendar: calendar)
    }

    /// Strictly "a comes before b". Undated rows always sort last, in either direction.
    static func isOrdered(_ a: TaskTableRow, _ b: TaskTableRow, by sort: TaskSort) -> Bool {
        func text(_ x: String, _ y: String) -> Bool? {
            let order = x.localizedCaseInsensitiveCompare(y)
            if order == .orderedSame { return nil }
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        }
        func date(_ x: Date?, _ y: Date?) -> Bool? {
            switch (x, y) {
            case (nil, nil):        return nil
            case (nil, _?):         return false
            case (_?, nil):         return true
            case let (p?, q?):
                if p == q { return nil }
                return sort.ascending ? p < q : p > q
            }
        }
        let primary: Bool?
        switch sort.key {
        case .name:      primary = text(a.title, b.title)
        case .job:       primary = text(a.jobTitle, b.jobTitle)
        case .account:   primary = text(a.clientName, b.clientName)
        case .status:    primary = text(a.status.label, b.status.label)
        case .priority:
            primary = a.priority.order == b.priority.order ? nil : (sort.ascending ? a.priority.order < b.priority.order : a.priority.order > b.priority.order)
        case .due:       primary = date(a.dueDate, b.dueDate)
        case .created:   primary = date(a.createdAt, b.createdAt)
        case .start:     primary = date(a.startDate, b.startDate)
        case .completed: primary = date(a.completedAt, b.completedAt)
        }
        if let primary { return primary }
        if let byTitle = text(a.title, b.title), sort.key != .name { return byTitle }
        return a.id.uuidString < b.id.uuidString
    }

    static func group(_ rows: [TaskTableRow], by grouping: TaskGrouping, now: Date, calendar: Calendar) -> [TaskGroup] {
        guard grouping != .none else {
            return rows.isEmpty ? [] : [TaskGroup(id: "all", title: "", rows: rows)]
        }
        var buckets: [String: [TaskTableRow]] = [:]
        var titles: [String: String] = [:]
        var order: [String: Int] = [:]

        for row in rows {
            let key: String, title: String, rank: Int
            switch grouping {
            case .none:
                continue
            case .due:
                let b = TaskDueBucket.bucket(for: row.dueDate, now: now, calendar: calendar)
                key = "due-\(b.rawValue)"; title = b.label; rank = b.rawValue
            case .client:
                key = "client-\(row.clientName)"; title = row.clientName.isEmpty ? "No client" : row.clientName
                rank = row.clientName.isEmpty ? 1 : 0
            case .job:
                key = "job-\(row.jobID?.uuidString ?? "")"; title = row.jobTitle.isEmpty ? "No job" : row.jobTitle
                rank = row.jobTitle.isEmpty ? 1 : 0
            case .stage:
                key = "stage-\(row.stageName)"; title = row.stageName.isEmpty ? "No job" : row.stageName
                rank = row.stageName.isEmpty ? 1 : 0
            case .priority:
                key = "priority-\(row.priority.rawValue)"; title = row.priority.label; rank = row.priority.order
            case .status:
                key = "status-\(row.status.rawValue)"; title = row.status.label
                rank = TaskStatus.allCases.firstIndex(of: row.status) ?? 0
            }
            buckets[key, default: []].append(row)
            titles[key] = title
            order[key] = rank
        }
        return buckets.keys.sorted { a, b in
            let ra = order[a] ?? 0, rb = order[b] ?? 0
            if ra != rb { return ra < rb }
            return (titles[a] ?? "").localizedCaseInsensitiveCompare(titles[b] ?? "") == .orderedAscending
        }
        .map { TaskGroup(id: $0, title: titles[$0] ?? "", rows: buckets[$0] ?? []) }
    }
}

// MARK: - Presets

struct TaskPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var filter: TaskFilter
    var sort: TaskSort
    var grouping: TaskGrouping
}

enum TaskPresets {
    static let builtIn: [TaskPreset] = [
        TaskPreset(id: "overdue", name: "Overdue",
                   filter: TaskFilter(due: .overdue), sort: TaskSort(key: .due, ascending: true), grouping: .none),
        TaskPreset(id: "this-week", name: "Due this week",
                   filter: TaskFilter(due: .thisWeek), sort: TaskSort(key: .due, ascending: true), grouping: .due),
        TaskPreset(id: "waiting-client", name: "Waiting for client",
                   filter: TaskFilter(status: .waitingClient), sort: TaskSort(key: .due, ascending: true), grouping: .client),
        TaskPreset(id: "high", name: "High priority",
                   filter: TaskFilter(priority: .high), sort: TaskSort(key: .due, ascending: true), grouping: .none),
        TaskPreset(id: "ready", name: "Ready to work",
                   filter: TaskFilter(hideBlocked: true), sort: TaskSort(key: .due, ascending: true), grouping: .due),
    ]

    static func decode(_ json: String) -> [TaskPreset] {
        guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
        return (try? JSONDecoder().decode([TaskPreset].self, from: data)) ?? []
    }

    static func encode(_ presets: [TaskPreset]) -> String {
        (try? JSONEncoder().encode(presets)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Adds a saved view (same name replaces it). Blank names are ignored.
    static func saving(_ name: String, filter: TaskFilter, sort: TaskSort, grouping: TaskGrouping, to presets: [TaskPreset]) -> [TaskPreset] {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return presets }
        var result = presets.filter { $0.name.caseInsensitiveCompare(clean) != .orderedSame }
        result.append(TaskPreset(id: UUID().uuidString, name: clean, filter: filter, sort: sort, grouping: grouping))
        return result
    }
}

// MARK: - Board and calendar

struct TaskBoardColumn: Identifiable, Equatable {
    var status: TaskStatus
    var rows: [TaskTableRow]
    var id: String { status.rawValue.isEmpty ? "none" : status.rawValue }
}

enum TaskBoard {
    /// One column per status, rows ordered by due date (undated last).
    static func columns(_ rows: [TaskTableRow]) -> [TaskBoardColumn] {
        TaskStatus.allCases.map { status in
            let inColumn = rows.filter { $0.status == status }
                .sorted { TaskTable.isOrdered($0, $1, by: TaskSort(key: .due, ascending: true)) }
            return TaskBoardColumn(status: status, rows: inColumn)
        }
    }
}

struct CalendarDay: Identifiable, Equatable {
    var date: Date
    var inMonth: Bool
    var taskCount: Int
    var overdueCount: Int
    var jobDueCount: Int
    var id: Date { date }
}

enum TaskCalendar {
    /// Six weeks (42 days) covering `month`, starting on the calendar's first weekday.
    static func monthGrid(for month: Date, rows: [TaskTableRow], jobDueDates: [Date], now: Date = .now,
                          calendar: Calendar = .current) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -lead, to: interval.start) else { return [] }
        let today = calendar.startOfDay(for: now)

        var taskCounts: [Date: Int] = [:]
        var overdueCounts: [Date: Int] = [:]
        for row in rows where !row.isDone {
            guard let due = row.dueDate else { continue }
            let day = calendar.startOfDay(for: due)
            taskCounts[day, default: 0] += 1
            if day < today { overdueCounts[day, default: 0] += 1 }
        }
        var jobCounts: [Date: Int] = [:]
        for due in jobDueDates { jobCounts[calendar.startOfDay(for: due), default: 0] += 1 }

        return (0..<42).compactMap { (offset: Int) -> CalendarDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let start = calendar.startOfDay(for: day)
            return CalendarDay(
                date: start, inMonth: calendar.isDate(start, equalTo: interval.start, toGranularity: .month),
                taskCount: taskCounts[start] ?? 0, overdueCount: overdueCounts[start] ?? 0, jobDueCount: jobCounts[start] ?? 0
            )
        }
    }

    static func rows(on day: Date, from rows: [TaskTableRow], calendar: Calendar = .current) -> [TaskTableRow] {
        rows.filter { row in
            guard !row.isDone, let due = row.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
        .sorted { TaskTable.isOrdered($0, $1, by: TaskSort(key: .priority, ascending: true)) }
    }
}
