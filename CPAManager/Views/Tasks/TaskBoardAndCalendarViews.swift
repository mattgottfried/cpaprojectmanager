import SwiftUI
import SwiftData

/// Kanban of pending tasks by status. Drag a card to another column to change its status.
struct TaskBoardView: View {
    let rows: [TaskTableRow]
    let onOpen: (TaskTableRow) -> Void
    let onMove: (UUID, TaskStatus) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskBoard.columns(rows)) { column in
                    columnView(column)
                }
            }
            .padding(16)
        }
    }

    private func columnView(_ column: TaskBoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.status.label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(column.rows.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(column.rows) { row in
                        card(row)
                            .onTapGesture { onOpen(row) }
                            .draggable(row.id.uuidString)
                    }
                    if column.rows.isEmpty {
                        Text("No tasks").font(.caption).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
            }
        }
        .frame(width: 260)
        .frame(minHeight: 320, alignment: .top)
        .padding(8)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let id = UUID(uuidString: text) else { return false }
            onMove(id, column.status)
            return true
        }
    }

    private func card(_ row: TaskTableRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.title).font(.subheadline.weight(.medium)).lineLimit(3)
            Text([row.jobTitle, row.clientName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 6) {
                if row.priority != .normal { TaskPriorityChip(priority: row.priority) }
                if row.isBlocked { TaskStatusChip(status: .none, isWaitingOnTask: true) }
                Spacer(minLength: 0)
                TaskDueLabel(row: row)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Month calendar of pending tasks (and job deadlines). Pick a day to see what's due.
struct TaskCalendarView: View {
    let rows: [TaskTableRow]
    let jobs: [Project]
    let onOpen: (TaskTableRow) -> Void
    let onComplete: (TaskTableRow) -> Void

    @State private var month = Date.now
    @State private var selected = Calendar.current.startOfDay(for: .now)

    private var calendar: Calendar { .current }

    private var days: [CalendarDay] {
        TaskCalendar.monthGrid(for: month, rows: rows, jobDueDates: jobs.compactMap(\.dueDate))
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                monthHeader
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(days) { day in dayCell(day) }
                }
                .padding(10)
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                dayList
            }
            .padding(16)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline).frame(maxWidth: .infinity)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            Button("Today") {
                month = .now
                selected = calendar.startOfDay(for: .now)
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selected)
        let isToday = calendar.isDateInToday(day.date)
        return Button {
            selected = day.date
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(day.inMonth ? Color.primary : Color.secondary.opacity(0.5))
                HStack(spacing: 3) {
                    if day.taskCount > 0 {
                        Text("\(day.taskCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .foregroundStyle(.white)
                            .background(day.overdueCount > 0 ? Theme.color(.bad) : Theme.brand, in: Capsule())
                    }
                    if day.jobDueCount > 0 {
                        Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Theme.color(.caution))
                    }
                }
                .frame(height: 16)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isSelected ? Theme.brand.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isToday { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.brand, lineWidth: 1.5) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.taskCount) tasks")
    }

    private var dayList: some View {
        let dayRows = TaskCalendar.rows(on: selected, from: rows)
        let dayJobs = jobs.filter { job in job.dueDate.map { calendar.isDate($0, inSameDayAs: selected) } ?? false }
        return VStack(alignment: .leading, spacing: 8) {
            Text(selected.formatted(date: .complete, time: .omitted)).font(.headline)
            if dayRows.isEmpty && dayJobs.isEmpty {
                Text("Nothing due.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(dayJobs) { job in
                NavigationLink(value: job) {
                    Label(job.title, systemImage: "flag.fill").font(.subheadline).foregroundStyle(Theme.color(.caution))
                }
            }
            ForEach(dayRows) { row in
                HStack(spacing: 10) {
                    Button { onComplete(row) } label: { Image(systemName: "circle").font(.title3) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete task")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.subheadline)
                        Text([row.jobTitle, row.clientName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.priority != .normal { TaskPriorityChip(priority: row.priority) }
                }
                .contentShape(Rectangle())
                .onTapGesture { onOpen(row) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

/// Add a task from the Tasks page: title, client, job, due date, priority, status.
struct NewTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var title = ""
    @State private var clientID: UUID?
    @State private var projectID: UUID?
    @State private var hasDue = true
    @State private var due = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var priority: Priority = .normal
    @State private var status: TaskStatus = .none

    private var jobChoices: [Project] {
        projects.filter { !$0.status.isComplete && (clientID == nil || $0.client?.id == clientID) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task name", text: $title)
                    Picker("Client", selection: $clientID) {
                        Text("None").tag(UUID?.none)
                        ForEach(clients) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("Job", selection: $projectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(jobChoices) { Text($0.title).tag(Optional($0.id)) }
                    }
                }
                Section {
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue { DatePicker("Due", selection: $due, displayedComponents: .date) }
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .navigationTitle("New Task")
            .inlineNavigationTitle()
            .onChange(of: clientID) { _, _ in
                // A job belongs to one client; drop a pick that no longer fits.
                if let projectID, !jobChoices.contains(where: { $0.id == projectID }) { self.projectID = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .macSheetFrame(minWidth: 440, idealWidth: 480, minHeight: 420, idealHeight: 460)
    }

    private func save() {
        let project = projects.first { $0.id == projectID }
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespaces),
            dueDate: hasDue ? due : nil,
            sortIndex: ((project?.taskList.map(\.sortIndex).max() ?? -1) + 1),
            project: project
        )
        task.client = project == nil ? clients.first { $0.id == clientID } : nil
        task.priority = priority
        task.status = status
        task.startDate = .now
        context.insert(task)
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context)
        dismiss()
    }
}
