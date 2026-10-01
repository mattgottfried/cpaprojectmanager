import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @Query private var invoices: [Invoice]
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.firmTagline) private var firmTagline = ""
    @AppStorage(SettingsKeys.firmContact) private var firmContact = ""

    @State private var newTaskTitle = ""
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var showingBill = false
    @State private var toast: UndoToastState?
    @Environment(\.dismiss) private var dismiss
    @State private var showingTemplatePicker = false
    @State private var showingHoldSheet = false
    @State private var detailTask: TaskItem?
    @State private var calendarRequest: CalendarEventRequest?
    @State private var routingSheetURL: URL?
    @State private var showingRoutingSheetShare = false

    private var isTimingThisProject: Bool {
        timer.isRunning && timer.runningEntryID != nil && timer.label == project.title
    }

    var body: some View {
        GroupedList {
            headerSection
            workflowSection
            billingSection
            statusSection
            tasksSection
            if !project.detail.isEmpty {
                Section("Notes") { Text(project.detail) }
            }
            timeSection
            StageRulesCard(project: project)

            DriveFolderSection(folderID: $project.driveFolderID, folderName: $project.driveFolderName, subject: "job")
            DocumentsSectionView(project: project)
        }
        .navigationTitle("Project")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Image(systemName: "trash").accessibilityLabel("Delete project")
                }
            }
        }
        .confirmationDialog("Delete this project and its tasks?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                context.delete(project)
                persist()
                dismiss()
            }
        }
        .undoToast($toast)
        .sheet(isPresented: $showingEdit) { ProjectFormView(project: project) }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerSheet { template in
                WorkflowEngine.applyTemplate(template, to: project, into: context)
                persist()
            }
        }
        .sheet(isPresented: $showingHoldSheet) { HoldSheetView(project: project) }
        .sheet(isPresented: $showingBill) { BillJobSheet(project: project) }
        .sheet(item: $detailTask) { TaskDetailSheet(task: $0) }
        .sheet(item: $calendarRequest) { CalendarEventView(request: $0) }
        .sheet(isPresented: $showingRoutingSheetShare) {
            if let routingSheetURL {
                ShareSheet(items: [routingSheetURL])
            }
        }
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
                    LabeledContent(project.statusFlow == .taxReturn ? "On hold" : "Waiting", value: reason.label)
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
                    Label(project.statusFlow == .taxReturn ? "Take off hold" : "Resume", systemImage: "play.circle.fill")
                }
            } else {
                if !project.nextAction.isEmpty {
                    Label(project.nextAction, systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.alert)
                }
                if let next = PipelineEngine.nextStageName(for: project, in: pipelines) {
                    Button {
                        PipelineEngine.advanceAny(project, pipelines: pipelines, context: context)
                        persist()
                    } label: {
                        Label("Advance to \(next)", systemImage: "arrow.right.circle.fill")
                    }
                }
                if !project.status.isComplete && project.pipelineID == nil {
                    Button {
                        showingHoldSheet = true
                    } label: {
                        Label(project.statusFlow == .taxReturn ? "Put on hold…" : "Waiting on client…", systemImage: "pause.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var billingSection: some View {
        if project.client != nil {
            Section("Billing") {
                if let invoice = invoices.first(where: { $0.id == project.invoiceID }) {
                    NavigationLink {
                        InvoiceDetailView(invoice: invoice)
                    } label: {
                        LabeledContent("Invoice", value: "\(invoice.displayNumber) · \(invoice.status.label)")
                    }
                } else if let state = BillingState(rawValue: project.billingStateRaw) {
                    LabeledContent("Billing", value: state.label)
                    Button("Undo this") {
                        BillingService.markSettled(project, as: nil)
                        persist()
                    }
                } else {
                    Button { showingBill = true } label: {
                        Label("Create invoice…", systemImage: "doc.badge.plus")
                    }
                    if project.status.isComplete {
                        Menu {
                            Button("Not billable") { settle(.notBillable) }
                            Button("Billed elsewhere") { settle(.billedElsewhere) }
                        } label: {
                            Label("Mark as settled", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
        }
    }

    private func settle(_ state: BillingState) {
        BillingService.markSettled(project, as: state)
        persist()
    }

    private var statusSection: some View {
        Section {
            if !pipelines.isEmpty {
                Picker("Pipeline", selection: pipelineBinding) {
                    Text(project.serviceType.label).tag(UUID?.none)
                    ForEach(pipelines) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let custom = PipelineEngine.pipeline(for: project, in: pipelines) {
                Picker("Stage", selection: stageBinding(custom)) {
                    ForEach(custom.stages) { Label($0.name, systemImage: $0.kind.systemImage).tag($0.id) }
                }
            } else {
                Picker("Status", selection: statusBinding) {
                    ForEach(project.statusFlow.statuses) { Label(project.statusFlow.label($0), systemImage: $0.systemImage).tag($0) }
                }
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
                TaskRowView(task: task, onToggle: { toggle(task) }, onOpen: { detailTask = task })
                    .deleteMenu(of: task, in: project.taskList, title: "Delete Task", perform: deleteTasks)
            }
            .onDelete(perform: deleteTasks)

            HStack {
                TextField("Add a task", text: $newTaskTitle)
                    .onSubmit(addTask)
                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                        .accessibilityLabel("Add task")
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Button {
                showingTemplatePicker = true
            } label: {
                Label("Apply template", systemImage: "square.stack.3d.up")
            }

            if !project.taskList.isEmpty {
                Menu {
                    Button {
                        printRoutingSheet()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    Button {
                        shareRoutingSheet()
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Routing Sheet", systemImage: "printer")
                }
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
                    timer.start(
                        project: project,
                        hourlyRate: RateResolver.rate(clientOverride: project.client?.hourlyRateOverride ?? 0, defaultRate: defaultHourlyRate),
                        isBillable: !(project.client?.isFlatFee ?? false),
                        context: context
                    )
                } label: {
                    Label("Start timer", systemImage: "play.circle.fill")
                }
                .disabled(timer.isRunning)
            }
        }
    }

    // MARK: Bindings that persist on change

    private var statusBinding: Binding<ProjectStatus> {
        Binding(get: { project.statusFlow.normalize(project.status) }, set: { PipelineEngine.setBuiltInStatus(project, to: $0, context: context); persist() })
    }
    private var pipelineBinding: Binding<UUID?> {
        Binding(
            get: { project.pipelineID },
            set: { id in
                PipelineEngine.assign(project, to: pipelines.first { $0.id == id }, context: context)
                persist()
            }
        )
    }
    private func stageBinding(_ pipeline: Pipeline) -> Binding<String> {
        Binding(
            get: { project.stageKey },
            set: { key in
                guard let stage = pipeline.definition.stage(withKey: key) else { return }
                PipelineEngine.enter(project, stage: stage, context: context)
                persist()
            }
        )
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
        if task.isDone {
            TaskCompletion.undo(task, spawned: nil, context: context)
        } else {
            TaskCompletion.complete(task, context: context)
        }
        persist()
    }

    private func deleteTasks(_ offsets: IndexSet) {
        let list = project.taskList
        let doomed = offsets.map { list[$0] }
        toast = context.deleteWithUndo(doomed.count == 1 ? "Deleted task" : "Deleted \(doomed.count) tasks") {
            for task in doomed { context.delete(task) }
        }
        NotificationScheduler.rescheduleAll(context: context)
    }

    private func persist() {
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
    }

    private func generateRoutingSheet() -> URL? {
        RoutingSheetPDF.generate(
            project: project,
            firmName: firmName.isEmpty ? "My Firm" : firmName,
            firmTagline: firmTagline,
            firmContact: firmContact
        )
    }

    private func printRoutingSheet() {
        guard let url = generateRoutingSheet() else { return }
        PrintHelper.printPDF(at: url, jobName: "Routing Sheet - \(project.title)")
    }

    private func shareRoutingSheet() {
        let url = generateRoutingSheet()
        routingSheetURL = url
        showingRoutingSheetShare = url != nil
    }
}

struct TaskRowView: View {
    let task: TaskItem
    var onToggle: () -> Void
    var onOpen: (() -> Void)? = nil
    @Query private var openTasks: [TaskItem]

    private var isBlocked: Bool {
        TaskDependencies.isBlocked(blockedByID: task.blockedByID, openTaskIDs: Set(openTasks.filter { !$0.isDone }.map(\.id)))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? .green : .secondary)
                    .accessibilityLabel(task.isDone ? "Mark not done" : "Mark done")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let due = task.dueDate, !task.isDone {
                    DueDatePill(date: due)
                }
                HStack(spacing: 8) {
                    if let summary = TaskChecklist.summary(task.checklist) {
                        Label(summary, systemImage: "checklist").font(.caption2).foregroundStyle(.secondary)
                    }
                    if isBlocked && !task.isDone {
                        Label("Blocked", systemImage: "lock.fill").font(.caption2).foregroundStyle(Theme.color(.caution))
                    }
                    if !task.waitingOn.isEmpty && !task.isDone {
                        Label("Waiting: \(task.waitingOn)", systemImage: "hourglass").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            if let onOpen {
                Button(action: onOpen) { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Task details")
            }
        }
        .padding(.vertical, 2)
    }
}
