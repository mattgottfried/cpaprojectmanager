import SwiftUI
import SwiftData

/// Quick intake for a new tax return, mirroring the firm's "New Tax Return"
/// Shortcut: client, return type, and the date documents were received compute a
/// due date (received + 9 days, weekend-adjusted) and file the project under
/// Awaiting Docs with a standard next action.
struct NewTaxReturnView: View {
    @Environment(\.modelContext) private var context
    @Environment(GoogleAuthService.self) private var google
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var templates: [WorkflowTemplate]

    @State private var selectedClientID: UUID?
    @State private var newClientName = ""
    @State private var returnType: EntityType = .individual1040
    @State private var receivedDate = Date.now
    @State private var copyNotes = true
    @State private var copyTasks = true
    @AppStorage(SettingsKeys.defaultReturnTemplate) private var defaultTemplateRaw = ""
    @State private var templateChoice: UUID?
    @State private var templateLoaded = false

    private let returnTypes = EntityType.allCases.filter { $0 != .other }

    private var isNewClient: Bool { selectedClientID == nil }
    private var canSave: Bool {
        isNewClient ? !newClientName.trimmingCharacters(in: .whitespaces).isEmpty : true
    }
    private var computedDueDate: Date {
        DateMath.addingDaysWeekendAdjusted(9, to: receivedDate)
    }

    // MARK: Year-over-year carryover

    private var taxYear: Int { Calendar.current.component(.year, from: receivedDate) - 1 }
    private var selectedClient: Client? { clients.first { $0.id == selectedClientID } }
    /// The checklist applied to the new return: the one picked here, which starts as the
    /// default chosen in Settings (else the built-in "Tax Return Routing Sheet").
    private var chosenTemplate: WorkflowTemplate? { templates.first { $0.id == templateChoice } }

    private var defaultTemplateID: UUID? {
        if let id = UUID(uuidString: defaultTemplateRaw), templates.contains(where: { $0.id == id }) { return id }
        return templates.first { $0.name == "Tax Return Routing Sheet" }?.id
    }

    private var returnTemplates: [WorkflowTemplate] {
        templates.filter { $0.serviceType == .taxReturn || $0.id == templateChoice }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var prior: Project? {
        selectedClient.flatMap { CarryoverService.priorJob(for: $0, serviceType: .taxReturn, taxYear: taxYear) }
    }
    private var extraTasks: [String] {
        prior.map { CarryoverService.extraTasks(from: $0, newTemplate: chosenTemplate, newYear: taxYear) } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    Picker("Client", selection: $selectedClientID) {
                        Text("New Client").tag(UUID?.none)
                        ForEach(clients) { client in
                            Text(client.displayName).tag(Optional(client.id))
                        }
                    }
                    if isNewClient {
                        TextField("Client name", text: $newClientName)
                    }
                }

                Section("Return") {
                    Picker("Return type", selection: $returnType) {
                        ForEach(returnTypes) { Text($0.code).tag($0) }
                    }
                    DatePicker("Date received", selection: $receivedDate, displayedComponents: .date)
                    Picker("Checklist template", selection: $templateChoice) {
                        Text("None").tag(UUID?.none)
                        ForEach(returnTemplates) { Text($0.name).tag(Optional($0.id)) }
                    }
                }

                if let prior {
                    Section {
                        if let cents = CarryoverService.priorFeeCents(prior) {
                            LabeledContent("Last year's fee", value: Format.currency(Double(cents) / 100))
                        }
                        if !prior.detail.isEmpty {
                            Toggle("Copy last year's notes", isOn: $copyNotes)
                        }
                        if !extraTasks.isEmpty {
                            Toggle("Repeat \(extraTasks.count) extra task\(extraTasks.count == 1 ? "" : "s")", isOn: $copyTasks)
                            ForEach(extraTasks.prefix(6), id: \.self) { title in
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("From \(prior.taxYear)")
                    } footer: {
                        Text("Extra tasks are steps last year's return had that the routing sheet doesn't create.")
                    }
                }

                Section {
                    Text("Due \(Format.mediumDate.string(from: computedDueDate)) · filed under Awaiting Docs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Tax Return")
            .inlineNavigationTitle()
            .onAppear {
                guard !templateLoaded else { return }
                templateLoaded = true
                templateChoice = defaultTemplateID
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: save).disabled(!canSave) }
            }
        }
        .macSheetFrame()
    }

    private func save() {
        let client: Client
        if let selectedClientID, let existing = clients.first(where: { $0.id == selectedClientID }) {
            client = existing
        } else {
            let created = Client(name: newClientName.trimmingCharacters(in: .whitespaces), entityType: returnType)
            context.insert(created)
            client = created
        }

        let taxYear = Calendar.current.component(.year, from: receivedDate) - 1
        let project = Project(
            title: "\(taxYear) - \(client.displayName) - \(returnType.code)",
            status: .notStarted,
            serviceType: .taxReturn,
            dueDate: computedDueDate,
            taxYear: taxYear,
            client: client
        )
        project.receivedDate = receivedDate
        project.nextAction = "Request documents from client"
        context.insert(project)
        PipelineEngine.applyDefault(to: project, context: context)

        if let chosenTemplate {
            WorkflowEngine.applyTemplate(chosenTemplate, to: project, startDate: receivedDate, into: context)
        }

        if let prior {
            if copyNotes, project.detail.isEmpty { project.detail = prior.detail }
            if copyTasks {
                let have = Set(project.taskList.map { $0.title.lowercased() })
                var index = (project.taskList.map(\.sortIndex).max() ?? -1) + 1
                for title in extraTasks where !have.contains(title.lowercased()) {
                    context.insert(TaskItem(title: title, sortIndex: index, project: project))
                    index += 1
                }
            }
        }

        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
        let auth = google, store = context
        Task { await DriveFolders.autoCreateIfNeeded(client, auth: auth, context: store) }
        dismiss()
    }
}
