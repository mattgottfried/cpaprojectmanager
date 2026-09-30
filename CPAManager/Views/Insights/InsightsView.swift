import SwiftUI
import SwiftData
import Charts

/// The dashboard: tasks to do for a day by priority, job counters, jobs by stage, planned vs
/// done, money and time. Widgets can be hidden and reordered (Edit widgets).
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Query private var tasks: [TaskItem]
    @Query private var projects: [Project]
    @Query private var invoices: [Invoice]
    @Query private var timeEntries: [TimeEntry]
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]

    @AppStorage("insightsWidgets") private var widgetsRaw = ""
    @AppStorage(TodayMode.storageKey) private var todayMode = TodayMode.insights.rawValue
    @AppStorage("tasksLayout") private var tasksLayout = TasksPageView.ViewMode.table.rawValue

    @State private var day = Date.now
    @State private var approaching: JobInsights.ApproachingDay = .today
    @State private var quietDays = 3
    @State private var editingWidgets = false
    @State private var jobList: JobList?
    @State private var detailTask: TaskItem?

    struct JobList: Identifiable {
        let id = UUID()
        let title: String
        let jobs: [InsightsJob]
    }

    private var rows: [TaskTableRow] { TaskTableService.rows(tasks: tasks, pipelines: pipelines) }
    private var jobs: [InsightsJob] { InsightsService.jobs(projects: projects, pipelines: pipelines) }

    var body: some View {
        let currentJobs = self.jobs
        let currentRows = self.rows
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Insights").font(.largeTitle.bold())
                        Button("Edit widgets") { editingWidgets = true }.buttonStyle(.borderless)
                        Spacer()
                    }
                    ForEach(InsightsLayout.visible(from: widgetsRaw)) { widget in
                        widgetView(widget, jobs: currentJobs, rows: currentRows)
                    }
                    if InsightsLayout.visible(from: widgetsRaw).isEmpty {
                        ContentUnavailableView("No widgets", systemImage: "square.grid.2x2",
                                               description: Text("Tap Edit widgets to turn some on."))
                    }
                }
                .padding(16)
            }
            .background(Color.appGroupedBackground)
            .macReadableWidth(1200)
            .navigationTitle("Insights")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .principal) { TodayModePicker() } }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $editingWidgets) { EditInsightsWidgetsSheet(raw: $widgetsRaw) }
            .sheet(item: $jobList) { list in JobListSheet(title: list.title, jobs: list.jobs, projects: projects) }
            .sheet(item: $detailTask) { TaskDetailSheet(task: $0) }
        }
    }

    @ViewBuilder
    private func widgetView(_ widget: InsightsWidget, jobs: [InsightsJob], rows: [TaskTableRow]) -> some View {
        switch widget {
        case .tasksToDo:     tasksToDoWidget(rows)
        case .jobs:          jobsWidget(jobs)
        case .jobsByStage:   jobsByStageWidget(jobs)
        case .plannedVsDone: plannedVsDoneWidget(rows)
        case .moneyTime:     moneyTimeWidget()
        }
    }

    // MARK: Tasks: to do

    private func tasksToDoWidget(_ rows: [TaskTableRow]) -> some View {
        let todo = TaskInsights.toDo(rows, on: day)
        let groups = TaskInsights.byPriority(todo)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tasks: to do").font(.title3.weight(.semibold))
                DatePicker("Day", selection: $day, displayedComponents: .date).labelsHidden()
                Spacer()
                Button {
                    tasksLayout = TasksPageView.ViewMode.calendar.rawValue
                    todayMode = TodayMode.tasks.rawValue
                } label: { Label("Calendar view", systemImage: "calendar") }
                .buttonStyle(.borderless)
            }

            if groups.isEmpty {
                card { Text("Nothing to do on this day.").font(.subheadline).foregroundStyle(.secondary) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        taskGroups(groups)
                        donut(groups, total: todo.count).frame(width: 220)
                    }
                    VStack(spacing: 14) {
                        donut(groups, total: todo.count).frame(height: 200)
                        taskGroups(groups)
                    }
                }
            }
        }
    }

    private func taskGroups(_ groups: [PriorityGroup]) -> some View {
        VStack(spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(group.priority.color).frame(width: 4, height: 18)
                        Text(group.priority.label).font(.headline)
                        Text("\(group.rows.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    .padding(12)
                    Divider()
                    ForEach(group.rows) { row in
                        HStack(spacing: 12) {
                            Text(row.title).font(.subheadline).foregroundStyle(Theme.brand).lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.clientName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                .frame(width: 130, alignment: .leading)
                            TaskDueLabel(row: row).frame(width: 110, alignment: .leading)
                            TaskStatusChip(status: row.status)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { detailTask = tasks.first { $0.id == row.id } }
                        Divider()
                    }
                }
                .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func donut(_ groups: [PriorityGroup], total: Int) -> some View {
        card {
            ZStack {
                Chart(groups) { group in
                    SectorMark(angle: .value("Tasks", group.rows.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(group.priority.color)
                }
                .chartLegend(.hidden)
                VStack(spacing: 2) {
                    Text("\(total)").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Remaining tasks").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 170)
            HStack(spacing: 12) {
                ForEach(groups) { group in
                    HStack(spacing: 4) {
                        Circle().fill(group.priority.color).frame(width: 8, height: 8)
                        Text(group.priority.label).font(.caption)
                    }
                }
            }
        }
    }

    // MARK: Jobs

    private func jobsWidget(_ jobs: [InsightsJob]) -> some View {
        let approachingJobs = JobInsights.approaching(jobs, on: approaching)
        let quiet = JobInsights.noActivity(jobs, overDays: quietDays)
        let overdue = JobInsights.overdue(jobs)
        let inProgress = JobInsights.inProgress(jobs)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Jobs").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                counterCard(count: approachingJobs.count, title: "Approaching deadline", tint: .caution) {
                    Picker("Day", selection: $approaching) {
                        ForEach(JobInsights.ApproachingDay.allCases) { Text($0.label).tag($0) }
                    }
                } onTap: { jobList = JobList(title: "Approaching deadline · \(approaching.label)", jobs: approachingJobs) }

                counterCard(count: quiet.count, title: "No activity", tint: .neutral) {
                    Picker("Over", selection: $quietDays) {
                        ForEach(JobInsights.noActivityChoices, id: \.self) { Text("Over \($0) days").tag($0) }
                    }
                } onTap: { jobList = JobList(title: "No activity for over \(quietDays) days", jobs: quiet) }

                counterCard(count: overdue.count, title: "Overdue", tint: .bad) { EmptyView() } onTap: {
                    jobList = JobList(title: "Overdue jobs", jobs: overdue)
                }

                counterCard(count: inProgress.count, title: "In progress", tint: .info) { EmptyView() } onTap: {
                    jobList = JobList(title: "Jobs in progress", jobs: inProgress)
                }
            }
        }
    }

    private func counterCard<Options: View>(
        count: Int, title: String, tint: SemanticState,
        @ViewBuilder options: () -> Options, onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(count)").font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(count > 0 && tint == .bad ? Theme.color(.bad) : Color.primary)
                Spacer()
                options().labelsHidden().pickerStyle(.menu).font(.caption)
            }
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.brand)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Jobs by stage

    private func jobsByStageWidget(_ jobs: [InsightsJob]) -> some View {
        let counts = JobInsights.byStage(jobs)
        let services = Array(Set(counts.map(\.serviceTypeRaw))).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Jobs by stage").font(.title3.weight(.semibold))
            if counts.isEmpty {
                card { Text("No open jobs.").font(.subheadline).foregroundStyle(.secondary) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(services, id: \.self) { raw in
                    let stageCounts = counts.filter { $0.serviceTypeRaw == raw }
                    let peak = max(1, stageCounts.map(\.count).max() ?? 1)
                    card {
                        Label((ServiceType(rawValue: raw) ?? .other).label, systemImage: (ServiceType(rawValue: raw) ?? .other).systemImage)
                            .font(.headline)
                        ForEach(stageCounts) { stage in
                            Button {
                                jobList = JobList(
                                    title: "\((ServiceType(rawValue: raw) ?? .other).label) · \(stage.stageName)",
                                    jobs: JobInsights.open(jobs).filter { $0.serviceTypeRaw == raw && $0.stageName == stage.stageName }
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Text(stage.stageName).font(.subheadline).lineLimit(1).frame(width: 130, alignment: .leading)
                                    GeometryReader { proxy in
                                        RoundedRectangle(cornerRadius: 4).fill(Theme.brand.opacity(0.75))
                                            .frame(width: max(6, proxy.size.width * CGFloat(stage.count) / CGFloat(peak)))
                                    }
                                    .frame(height: 14)
                                    Text("\(stage.count)").font(.subheadline.monospacedDigit()).frame(width: 30, alignment: .trailing)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Planned vs done

    private func plannedVsDoneWidget(_ rows: [TaskTableRow]) -> some View {
        let points = TaskInsights.weekly(rows, weeks: 8)
        let rate = TaskInsights.completionRate(points)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Planned vs done").font(.title3.weight(.semibold))
            card {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Week", point.weekStart, unit: .weekOfYear), y: .value("Tasks", point.planned))
                            .position(by: .value("Kind", "Planned"))
                            .foregroundStyle(by: .value("Kind", "Planned"))
                        BarMark(x: .value("Week", point.weekStart, unit: .weekOfYear), y: .value("Tasks", point.done))
                            .position(by: .value("Kind", "Done"))
                            .foregroundStyle(by: .value("Kind", "Done"))
                    }
                }
                .chartForegroundStyleScale(["Planned": Color.gray.opacity(0.5), "Done": Theme.brand])
                .frame(height: 190)
                .accessibilityLabel("Tasks planned and done per week, last 8 weeks")
                if let rate {
                    Text("\(Int((rate * 100).rounded()))% of the tasks planned in the last 8 weeks are done.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Money and time

    private func moneyTimeWidget() -> some View {
        let m = InsightsService.moneyTime(projects: projects, invoices: invoices, timeEntries: timeEntries)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Money and time").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                stat(Format.currency(Double(m.unbilledCents) / 100), "Unbilled work", m.unbilledCents > 0 ? .caution : .neutral)
                stat(Format.currency(Double(m.outstandingCents) / 100), "Outstanding invoices", .info)
                stat(Format.currency(Double(m.overdueCents) / 100), "Overdue invoices", m.overdueCents > 0 ? .bad : .neutral)
                stat(Format.hoursMinutes(m.weekSeconds), "Hours this week", .neutral)
                stat(Format.hoursMinutes(m.monthSeconds), "Hours this month", .neutral)
                stat(Format.currency(Double(m.monthBillableCents) / 100), "Billable this month", .good)
            }
        }
    }

    private func stat(_ value: String, _ title: String, _ tint: SemanticState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(tint == .neutral ? Color.primary : Theme.color(tint))
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// The jobs behind a counter, each opening the job.
struct JobListSheet: View {
    let title: String
    let jobs: [InsightsJob]
    let projects: [Project]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if jobs.isEmpty { Text("None.").foregroundStyle(.secondary) }
                ForEach(jobs) { job in
                    if let project = projects.first(where: { $0.id == job.id }) {
                        NavigationLink(value: project) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.title).lineLimit(2)
                                Text([job.clientName, job.stageName].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let due = job.dueDate {
                                    Text("Due \(Format.relativeDay(due))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .inlineNavigationTitle()
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .macSheetFrame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
    }
}

/// Show, hide and reorder the Insights widgets.
struct EditInsightsWidgetsSheet: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [InsightsSlot] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach($slots) { $slot in
                    Toggle(slot.widget.title, isOn: $slot.isVisible)
                }
                .onMove { slots.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationTitle("Widgets")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        raw = InsightsLayout.encode(slots)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .leading) { EditButton() }
                #endif
            }
            .onAppear { slots = InsightsLayout.slots(from: raw) }
        }
        .macSheetFrame(minWidth: 380, idealWidth: 420, minHeight: 360, idealHeight: 400)
    }
}
