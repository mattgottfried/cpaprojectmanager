import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0

    @State private var newTaskTitle = ""
    @State private var showingEdit = false
    @State private var showingTemplatePicker = false
    @State private var showingHoldSheet = false
    @State private var calendarRequest: CalendarEventRequest?

    private var isTimingThisProject: Bool {
        timer.isRunning && timer.runningEntryID != nil && timer.label == project.title
    }

    var body: some View {
        List {
            headerSection
            workflowSection
            statusSection
            tasksSection
            if !project.detail.isEmpty {
                Section("Notes") { Text(project.detail) }
            }
            timeSection
            DocumentsSectionView(project: project)
        }
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) { ProjectFormView(project: project) }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet { template in
                WorkflowEngine.applyTemplate(template, to: project, into: context)
                persist()
            }
        }
        .sheet(isPresented: $showingHoldSheet) { HoldSheetView(project: project) }
        .sheet(item: $calendarRequest) { CalendarEventView(request: $0) }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                ServiceTypeIcon(serviceType: project.serviceType, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title).font(.headline)
                    Text(project.clientName).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if project.totalTaskCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: project.progress)
                        .tint(Theme.brand)
                    Text("\(project.completedTaskCount) of \(project.totalTaskCount) tasks complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var workflowSection: some View {
        Section("Workflow") {
            if let received = project.receivedDate {
                LabeledContent("Received", value: Format.mediumDate.string(from: received))
            }

            if project.isOnHold {
                if let reason = project.holdReason {
                    LabeledContent("On hold", value: reason.label)
                }
                if !project.holdDetail.isEmpty {
                    Text(project.holdDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    project.takeOffHold()
                    persist()
                } label: {
                    Label("Take off hold", systemImage: "play.circle.fill")
                }
            } else {
                if !project.nextAction.isEmpty {
                    Label(project.nextAction, systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                if let next = project.nextStatusPreview {
                    Button {
                        project.advance()
                        persist()
                    } label: {
                        Label("Advance to \(next.label)", systemImage: "arrow.right.circle.fill")
                    }
                }
                if !project.status.isComplete {
                    Button {
                        showingHoldSheet = true
                    } label: {
                        Label("Put on hold…", systemImage: "pause.circle")
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: statusBinding) {
                ForEach(ProjectStatus.allCases) { Label($0.label, systemImage: $0.systemImage).tag($0) }
            }
            Picker("Priority", selection: priorityBinding) {
                ForEach(Priority.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Has due date", isOn: hasDueDateBinding)
            if let due = project.dueDate {
                DatePicker("Due", selection: dueDateBinding, displayedComponents: .date)
                Button {
                    calendarRequest = CalendarEventRequest(title: project.title, date: due, notes: project.clientName)
                } label: {
                    Label("Add to Calendar", systemImage: "calendar.badge.plus")
                }
            }
        }
    }

    private var tasksSection: some View {
        Section("Tasks") {
            if project.taskList.isEmpty {
                Text("No tasks. Add one below or apply a template.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(project.taskList) { task in
                TaskRowView(task: task) { toggle(task) }
            }
            .onDelete(perform: deleteTasks)

            HStack {
                TextField("Add a task", text: $newTaskTitle)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                showingTemplatePicker = true
            } label: {
                Label("Apply template", systemImage: "square.stack.3d.up")
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            LabeledContent("Tracked", value: Format.hoursMinutes(project.totalTrackedSeconds))
            if isTimingThisProject {
                Button(role: .destructive) {
                    timer.stop(context: context)
                } label: {
                    Label("Stop timer", systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    timer.start(project: project, hourlyRate: defaultHourlyRate, isBillable: true, context: context)
                } label: {
                    Label("Start timer", systemImage: "play.circle.fill")
                }
                .disabled(timer.isRunning)
            }
        }
    }

    // MARK: Bindings that persist on change

    private var statusBinding: Binding<ProjectStatus> {
        Binding(get: { project.status }, set: { project.status = $0; persist() })
    }
    private var priorityBinding: Binding<Priority> {
        Binding(get: { project.priority }, set: { project.priority = $0; persist() })
    }
    private var dueDateBinding: Binding<Date> {
        Binding(get: { project.dueDate ?? .now }, set: { project.dueDate = $0; persist() })
    }
    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { project.dueDate != nil },
            set: { on in
                project.dueDate = on ? (project.dueDate ?? .now) : nil
                persist()
            }
        )
    }

    // MARK: Actions

    private func addTask() {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let nextIndex = (project.taskList.map(\.sortIndex).max() ?? -1) + 1
        let task = TaskItem(title: trimmed, sortIndex: nextIndex, project: project)
        context.insert(task)
        newTaskTitle = ""
        persist()
    }

    private func toggle(_ task: TaskItem) {
        task.toggle()
        persist()
    }

    private func deleteTasks(_ offsets: IndexSet) {
        let list = project.taskList
        for index in offsets { context.delete(list[index]) }
        persist()
    }

    private func persist() {
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
    }
}

struct TaskRowView: View {
    let task: TaskItem
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let due = task.dueDate, !task.isDone {
                    DueDatePill(date: due)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
