import SwiftUI
import SwiftData

/// Every task in one place, TaxDome-style: Pending / Completed tabs, presets and filters,
/// sortable columns, grouping, bulk actions, plus a board by status and a calendar.
struct TasksPageView: View {
    enum ViewMode: String, CaseIterable, Identifiable {
        case table = "Table", board = "Board", calendar = "Calendar"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .table:    return "tablecells"
            case .board:    return "rectangle.split.3x1"
            case .calendar: return "calendar"
            }
        }
    }

    enum Column: String, CaseIterable, Identifiable {
        case job, account, status, due, priority, subtasks, created, start, completed
        var id: String { rawValue }

        var title: String {
            switch self {
            case .job: return "Job"
            case .account: return "Account"
            case .status: return "Status"
            case .due: return "Due date"
            case .priority: return "Priority"
            case .subtasks: return "Subtasks"
            case .created: return "Date created"
            case .start: return "Start date"
            case .completed: return "Completed"
            }
        }

        var width: CGFloat {
            switch self {
            case .job: return 190
            case .account: return 170
            case .status: return 140
            case .due: return 120
            case .priority: return 90
            case .subtasks: return 76
            case .created, .start: return 110
            case .completed: return 120
            }
        }

        var sortKey: TaskSortKey? {
            switch self {
            case .job: return .job
            case .account: return .account
            case .status: return .status
            case .due: return .due
            case .priority: return .priority
            case .created: return .created
            case .start: return .start
            case .completed: return .completed
            case .subtasks: return nil
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @Query private var tasks: [TaskItem]
    @Query private var projects: [Project]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]

    @AppStorage("tasksLayout") private var layoutRaw = ViewMode.table.rawValue
    @AppStorage("tasksHiddenColumns") private var hiddenRaw = "created,start"
    @AppStorage(SettingsKeys.taskPresets) private var presetsJSON = ""

    @State private var tab: TaskTab = .pending
    @State private var filter = TaskFilter()
    @State private var sort = TaskSort()
    @State private var grouping: TaskGrouping = .none
    @State private var selection = ListSelection<UUID>()
    @State private var toast: UndoToastState?
    @State private var detailTask: TaskItem?
    @State private var showingNewTask = false
    @State private var showingBulkDate = false
    @State private var dateTask: TaskItem?
    @State private var showingSavePreset = false
    @State private var presetName = ""
    @State private var exportURL: URL?
    @State private var showingExport = false

    private var layout: ViewMode { ViewMode(rawValue: layoutRaw) ?? .table }
    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }
    private var customPresets: [TaskPreset] { TaskPresets.decode(presetsJSON) }

    private var isWide: Bool {
        #if os(macOS)
        return true
        #else
        return sizeClass == .regular
        #endif
    }

    private var allRows: [TaskTableRow] { TaskTableService.rows(tasks: tasks, pipelines: pipelines) }

    private var visibleColumns: [Column] {
        Column.allCases.filter { column in
            if column == .completed { return tab == .completed }
            return !hidden.contains(column.rawValue)
        }
    }

    var body: some View {
        let rows = allRows
        let groups = TaskTable.apply(rows, tab: tab, filter: filter, sort: sort, grouping: grouping)
        NavigationStack {
            VStack(spacing: 0) {
                header(rows: rows, shown: groups.flatMap(\.rows))
                content(rows: rows, groups: groups)
            }
            .background(Color.appGroupedBackground)
            .macReadableWidth(1400)
            .safeAreaInset(edge: .bottom) {
                if selection.isSelecting && layout == .table { bulkBar }
            }
            .navigationTitle("Tasks")
            .inlineNavigationTitle()
            .searchable(text: $filter.search, prompt: "Search tasks")
            .toolbar {
                ToolbarItem(placement: .principal) { TodayModePicker() }
            }
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
            .onChange(of: tab) { _, newTab in
                selection.finish()
                sort = newTab == .completed ? TaskSort(key: .completed, ascending: false) : TaskSort()
            }
            .sheet(item: $detailTask) { TaskDetailSheet(task: $0) }
            .sheet(isPresented: $showingNewTask) { NewTaskSheet() }
            .sheet(isPresented: $showingBulkDate) {
                BulkDateSheet(title: "Set Due Date") { date in
                    let chosen = selectedTasks
                    toast = context.performUndoable("Updated \(chosen.count) tasks", overwrite: true) {
                        BulkActions.setDueDate(chosen, to: date)
                    }
                }
            }
            .sheet(item: $dateTask) { task in
                BulkDateSheet(title: "Due Date") { date in
                    toast = context.performUndoable("Due date set", overwrite: true) { task.dueDate = date }
                }
            }
            .sheet(isPresented: $showingExport) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            .alert("Save this view", isPresented: $showingSavePreset) {
                TextField("Name", text: $presetName)
                Button("Save") { savePreset() }
                Button("Cancel", role: .cancel) { presetName = "" }
            } message: {
                Text("Keeps the current filters, sorting and grouping as a preset.")
            }
            .undoToast($toast)
        }
    }

    // MARK: Header (tabs, presets, filter, actions)

    private func header(rows: [TaskTableRow], shown: [TaskTableRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Tab", selection: $tab) {
                    ForEach(TaskTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Picker("View as", selection: $layoutRaw) {
                    ForEach(ViewMode.allCases) { Label($0.rawValue, systemImage: $0.systemImage).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 150)

                Spacer(minLength: 0)
                Button { showingNewTask = true } label: { Label("New task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetsMenu
                    filterMenu(rows: rows)
                    groupMenu
                    sortMenu
                    if layout == .table && isWide { columnsMenu }
                    if layout == .table {
                        Button {
                            if selection.isSelecting { selection.finish() } else { selection.isSelecting = true }
                        } label: {
                            Label(selection.isSelecting ? "Done" : "Select", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button { export(shown) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                    Text("\(shown.count) task\(shown.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var presetsMenu: some View {
        Menu {
            Section("Views") {
                ForEach(TaskPresets.builtIn) { preset in
                    Button(preset.name) { apply(preset) }
                }
            }
            if !customPresets.isEmpty {
                Section("Saved") {
                    ForEach(customPresets) { preset in
                        Button(preset.name) { apply(preset) }
                    }
                }
                Menu("Delete a saved view") {
                    ForEach(customPresets) { preset in
                        Button(preset.name, role: .destructive) { deletePreset(preset) }
                    }
                }
            }
            Divider()
            Button { showingSavePreset = true } label: { Label("Save current view…", systemImage: "star") }
            Button(role: .destructive) { reset() } label: { Label("Clear filters", systemImage: "xmark.circle") }
        } label: {
            Label("Presets", systemImage: "star")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private func filterMenu(rows: [TaskTableRow]) -> some View {
        let clientChoices = clientChoices(from: rows)
        let stages = Array(Set(rows.map(\.stageName).filter { !$0.isEmpty })).sorted()
        return Menu {
            Picker("Client", selection: $filter.clientID) {
                Text("Any client").tag(UUID?.none)
                ForEach(clientChoices) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Service", selection: $filter.serviceTypeRaw) {
                Text("Any service").tag(String?.none)
                ForEach(ServiceType.allCases) { Text($0.label).tag(Optional($0.rawValue)) }
            }
            Picker("Stage", selection: $filter.stageName) {
                Text("Any stage").tag(String?.none)
                ForEach(stages, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Picker("Status", selection: $filter.status) {
                Text("Any status").tag(TaskStatus?.none)
                ForEach(TaskStatus.allCases) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Priority", selection: $filter.priority) {
                Text("Any priority").tag(Priority?.none)
                ForEach(Priority.allCases) { Text($0.label).tag(Optional($0)) }
            }
            Picker("Due", selection: $filter.due) {
                Text("Any date").tag(TaskDueRange?.none)
                ForEach(TaskDueRange.allCases) { Text($0.label).tag(Optional($0)) }
            }
            Toggle("Hide tasks waiting on another task", isOn: $filter.hideBlocked)
            Divider()
            Button(role: .destructive) { filter = TaskFilter(search: filter.search) } label: { Label("Clear filters", systemImage: "xmark.circle") }
        } label: {
            Label(filter.activeCount == 0 ? "Filter" : "Filter (\(filter.activeCount))", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private struct ClientChoice: Identifiable {
        let id: UUID
        let name: String
    }

    /// Clients that have at least one task in `rows`, by name.
    private func clientChoices(from rows: [TaskTableRow]) -> [ClientChoice] {
        var seen = Set<UUID>()
        var choices: [ClientChoice] = []
        for row in rows {
            if let id = row.clientID, seen.insert(id).inserted { choices.append(ClientChoice(id: id, name: row.clientName)) }
        }
        return choices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var groupMenu: some View {
        Menu {
            Picker("Group by", selection: $grouping) {
                ForEach(TaskGrouping.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            Label(grouping == .none ? "Group" : "Group: \(grouping.label)", systemImage: "rectangle.3.group")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort.key) {
                ForEach(TaskSortKey.allCases) { Text(sortTitle($0)).tag($0) }
            }
            Toggle("Ascending", isOn: $sort.ascending)
        } label: {
            Label("Sort: \(sortTitle(sort.key)) \(sort.ascending ? "↑" : "↓")", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(Column.allCases.filter { $0 != .completed }) { column in
                Toggle(column.title, isOn: Binding(
                    get: { !hidden.contains(column.rawValue) },
                    set: { show in
                        var set = hidden
                        if show { set.remove(column.rawValue) } else { set.insert(column.rawValue) }
                        hiddenRaw = set.sorted().joined(separator: ",")
                    }
                ))
            }
        } label: {
            Label("Columns", systemImage: "gearshape")
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
    }

    private func sortTitle(_ key: TaskSortKey) -> String {
        switch key {
        case .name: return "Task name"
        case .job: return "Job"
        case .account: return "Account"
        case .status: return "Status"
        case .due: return "Due date"
        case .priority: return "Priority"
        case .created: return "Date created"
        case .start: return "Start date"
        case .completed: return "Completed"
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(rows: [TaskTableRow], groups: [TaskRowGroup]) -> some View {
        switch layout {
        case .table:
            if groups.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? (tab == .pending ? "Nothing pending" : "Nothing completed yet") : "No tasks match",
                    systemImage: "checklist",
                    description: Text(filter.isEmpty ? "Add a task with New task." : "Try clearing a filter.")
                )
            } else {
                taskList(groups)
            }
        case .board:
            TaskBoardView(rows: TaskTable.apply(rows, tab: .pending, filter: filter, sort: sort, grouping: .none).flatMap(\.rows),
                          onOpen: openDetails, onMove: moveToStatus)
        case .calendar:
            TaskCalendarView(rows: TaskTable.apply(rows, tab: .pending, filter: filter, sort: sort, grouping: .none).flatMap(\.rows),
                             jobs: projects.filter { !$0.status.isComplete },
                             onOpen: openDetails, onComplete: complete)
        }
    }

    private func taskList(_ groups: [TaskRowGroup]) -> some View {
        List {
            if layout == .table && isWide { columnHeader }
            ForEach(groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        taskRow(row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.visible)
                            .contextMenu { rowMenu(row) }
                    }
                } header: {
                    if !group.title.isEmpty {
                        Text("\(group.title) (\(group.rows.count))").font(.headline).textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listKeyboard(
            move: { selection.cursor = ListSelection.moved(from: selection.cursor, in: groups.flatMap(\.rows).map(\.id), by: $0) },
            open: { if let id = selection.cursor, let task = tasks.first(where: { $0.id == id }) { detailTask = task } },
            toggle: { if let id = selection.cursor { selection.toggle(id) } },
            delete: { deleteTasks(selectedOrCursor) }
        )
    }

    // MARK: Table pieces

    private var columnHeader: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 22)
            headerButton("Task name", key: .name).frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            ForEach(visibleColumns) { column in
                if let key = column.sortKey {
                    headerButton(column.title, key: key).frame(width: column.width, alignment: .leading)
                } else {
                    Text(column.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: column.width, alignment: .leading)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(.isHeader)
    }

    private func headerButton(_ title: String, key: TaskSortKey) -> some View {
        Button {
            if sort.key == key { sort.ascending.toggle() } else { sort = TaskSort(key: key, ascending: true) }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if sort.key == key { Image(systemName: sort.ascending ? "chevron.up" : "chevron.down").font(.caption2) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(sort.key == key ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskRow(_ row: TaskTableRow) -> some View {
        let selected = selection.selected.contains(row.id)
        Group {
            if isWide { wideRow(row, selected: selected) } else { compactRow(row, selected: selected) }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.isSelecting { selection.toggle(row.id) } else { openDetails(row) }
        }
        .overlay(alignment: .leading) {
            if selection.cursor == row.id { Rectangle().fill(Theme.brand).frame(width: 3) }
        }
    }

    private func checkbox(_ row: TaskTableRow, selected: Bool) -> some View {
        Button {
            if selection.isSelecting { selection.toggle(row.id) } else { complete(row) }
        } label: {
            Image(systemName: selection.isSelecting ? (selected ? "checkmark.circle.fill" : "circle") : (row.isDone ? "checkmark.circle.fill" : "circle"))
                .font(.title3)
                .foregroundStyle(selected || row.isDone ? Theme.brand : Color.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 22)
        .accessibilityLabel(row.isDone ? "Mark not done" : "Complete task")
    }

    private func wideRow(_ row: TaskTableRow, selected: Bool) -> some View {
        HStack(spacing: 12) {
            checkbox(row, selected: selected)
            Text(row.title).lineLimit(2)
                .strikethrough(row.isDone)
                .foregroundStyle(row.isDone ? Color.secondary : Color.primary)
                .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            ForEach(visibleColumns) { column in
                cell(column, row).frame(width: column.width, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func cell(_ column: Column, _ row: TaskTableRow) -> some View {
        switch column {
        case .job:
            if let project = projects.first(where: { $0.id == row.jobID }) {
                NavigationLink(value: project) { Text(row.jobTitle).lineLimit(2).font(.subheadline) }
                    .buttonStyle(.plain).foregroundStyle(Theme.brand)
            } else { Text("—").foregroundStyle(.secondary) }
        case .account:
            if let client = clients.first(where: { $0.id == row.clientID }) {
                NavigationLink(value: client) { Text(row.clientName).lineLimit(2).font(.subheadline) }
                    .buttonStyle(.plain).foregroundStyle(Theme.brand)
            } else { Text("—").foregroundStyle(.secondary) }
        case .status:
            statusMenu(row)
        case .due:
            TaskDueLabel(row: row)
        case .priority:
            priorityMenu(row)
        case .subtasks:
            Text(row.subtasksTotal == 0 ? "" : "\(row.subtasksDone)/\(row.subtasksTotal)").font(.subheadline.monospacedDigit())
        case .created:
            Text(row.createdAt.formatted(.dateTime.month(.abbreviated).day().year())).font(.subheadline.monospacedDigit())
        case .start:
            Text(row.startDate.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "").font(.subheadline.monospacedDigit())
        case .completed:
            Text(row.completedAt.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "").font(.subheadline.monospacedDigit())
        }
    }

    private func compactRow(_ row: TaskTableRow, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox(row, selected: selected)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title).lineLimit(2).strikethrough(row.isDone)
                Text([row.jobTitle, row.clientName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    TaskStatusChip(status: row.status, isWaitingOnTask: row.isBlocked && row.status == .none)
                    if row.priority != .normal { TaskPriorityChip(priority: row.priority) }
                    Spacer(minLength: 0)
                    TaskDueLabel(row: row)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusMenu(_ row: TaskTableRow) -> some View {
        Menu {
            ForEach(TaskStatus.allCases) { status in
                Button(status.label) { setStatus(status, for: row) }
            }
        } label: {
            TaskStatusChip(status: row.status, isWaitingOnTask: row.isBlocked && row.status == .none)
        }
        .menuStyle(.button).buttonStyle(.plain)
    }

    private func priorityMenu(_ row: TaskTableRow) -> some View {
        Menu {
            ForEach(Priority.allCases) { priority in
                Button(priority.label) { setPriority(priority, for: row) }
            }
        } label: {
            TaskPriorityChip(priority: row.priority)
        }
        .menuStyle(.button).buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowMenu(_ row: TaskTableRow) -> some View {
        Button { openDetails(row) } label: { Label("Details…", systemImage: "info.circle") }
        if !row.isDone { Button { complete(row) } label: { Label("Mark done", systemImage: "checkmark.circle") } }
        else { Button { complete(row) } label: { Label("Mark not done", systemImage: "arrow.uturn.backward") } }
        Button { dateTask = task(for: row) } label: { Label("Set due date…", systemImage: "calendar") }
        Menu("Priority") { ForEach(Priority.allCases) { p in Button(p.label) { setPriority(p, for: row) } } }
        Menu("Status") { ForEach(TaskStatus.allCases) { s in Button(s.label) { setStatus(s, for: row) } } }
        Divider()
        Button(role: .destructive) { deleteTasks(task(for: row).map { [$0] } ?? []) } label: { Label("Delete Task", systemImage: "trash") }
    }

    // MARK: Bulk bar

    private var selectedTasks: [TaskItem] { tasks.filter { selection.selected.contains($0.id) } }

    private var selectedOrCursor: [TaskItem] {
        if !selection.selected.isEmpty { return selectedTasks }
        return tasks.filter { $0.id == selection.cursor }
    }

    private var bulkBar: some View {
        BulkBar(count: selection.count, done: { selection.finish() }) {
            Button {
                let chosen = selectedTasks
                toast = context.performUndoable("Completed \(chosen.count) tasks", overwrite: true) {
                    BulkActions.complete(chosen, context: context)
                }
                selection.finish()
            } label: { Label("Complete", systemImage: "checkmark.circle") }
            Menu {
                Button { showingBulkDate = true } label: { Label("Set due date…", systemImage: "calendar") }
                Menu("Priority") {
                    ForEach(Priority.allCases) { p in
                        Button(p.label) {
                            let chosen = selectedTasks
                            toast = context.performUndoable("Updated \(chosen.count) tasks", overwrite: true) { BulkActions.setPriority(p, for: chosen) }
                        }
                    }
                }
                Menu("Status") {
                    ForEach(TaskStatus.allCases) { s in
                        Button(s.label) {
                            let chosen = selectedTasks
                            toast = context.performUndoable("Updated \(chosen.count) tasks", overwrite: true) { BulkActions.setStatus(s, for: chosen) }
                        }
                    }
                }
            } label: { Label("Update", systemImage: "ellipsis.circle") }
            Button(role: .destructive) { deleteTasks(selectedTasks) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Actions

    private func task(for row: TaskTableRow) -> TaskItem? { tasks.first { $0.id == row.id } }

    private func openDetails(_ row: TaskTableRow) { detailTask = task(for: row) }

    private func complete(_ row: TaskTableRow) {
        guard let task = task(for: row) else { return }
        if task.isDone {
            toast = context.performUndoable("Reopened", overwrite: true) { TaskCompletion.undo(task, spawned: nil, context: context) }
        } else {
            toast = context.performUndoable("Completed \"\(task.title)\"", overwrite: true) { TaskCompletion.complete(task, context: context) }
        }
        NotificationScheduler.rescheduleAll(context: context)
    }

    private func setStatus(_ status: TaskStatus, for row: TaskTableRow) {
        guard let task = task(for: row) else { return }
        task.status = status
        try? context.save()
    }

    private func moveToStatus(_ id: UUID, _ status: TaskStatus) {
        guard let task = tasks.first(where: { $0.id == id }), task.status != status else { return }
        toast = context.performUndoable("Moved to \(status.label.lowercased())", overwrite: true) { task.status = status }
    }

    private func setPriority(_ priority: Priority, for row: TaskTableRow) {
        guard let task = task(for: row) else { return }
        task.priority = priority
        try? context.save()
    }

    private func deleteTasks(_ doomed: [TaskItem]) {
        guard !doomed.isEmpty else { return }
        toast = context.deleteWithUndo(doomed.count == 1 ? "Deleted task" : "Deleted \(doomed.count) tasks") {
            for task in doomed { context.delete(task) }
        }
        selection.finish()
        NotificationScheduler.rescheduleAll(context: context)
    }

    private func apply(_ preset: TaskPreset) {
        let searched = filter.search
        filter = preset.filter
        filter.search = searched
        sort = preset.sort
        grouping = preset.grouping
    }

    private func reset() {
        filter = TaskFilter()
        sort = tab == .completed ? TaskSort(key: .completed, ascending: false) : TaskSort()
        grouping = .none
    }

    private func savePreset() {
        var saved = filter
        saved.search = ""
        presetsJSON = TaskPresets.encode(TaskPresets.saving(presetName, filter: saved, sort: sort, grouping: grouping, to: customPresets))
        presetName = ""
    }

    private func deletePreset(_ preset: TaskPreset) {
        presetsJSON = TaskPresets.encode(customPresets.filter { $0.id != preset.id })
    }

    private func export(_ shown: [TaskTableRow]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CPA Tasks \(CSVWriter.date(.now)).csv")
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(TaskTableService.csv(shown).utf8)
        if (try? data.write(to: url, options: .atomic)) != nil {
            exportURL = url
            showingExport = true
        }
    }
}
