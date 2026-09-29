import SwiftUI
import SwiftData

/// Create or edit a project. When creating, optionally seed it from a template.
struct ProjectFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]

    var project: Project?
    var defaultClient: Client?

    @State private var title = ""
    @State private var detail = ""
    @State private var status: ProjectStatus = .notStarted
    @State private var serviceType: ServiceType = .taxReturn
    @State private var priority: Priority = .normal
    @State private var selectedClientID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var selectedTemplateID: UUID?
    @State private var nextAction = ""
    @State private var hasReceivedDate = false
    @State private var receivedDate = Date.now
    @State private var loaded = false

    private var isEditing: Bool { project != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Client", selection: $selectedClientID) {
                        Text("No client").tag(UUID?.none)
                        ForEach(clients) { client in
                            Text(client.displayName).tag(Optional(client.id))
                        }
                    }
                }

                if !isEditing && !templates.isEmpty {
                    Section {
                        Picker("Start from template", selection: $selectedTemplateID) {
                            Text("None").tag(UUID?.none)
                            ForEach(templates) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                    } footer: {
                        Text("A template fills in the task checklist and a suggested due date.")
                    }
                }

                Section {
                    Picker("Service", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ProjectStatus.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Workflow") {
                    TextField("Next action", text: $nextAction)
                    Toggle("Has received date", isOn: $hasReceivedDate)
                    if hasReceivedDate {
                        DatePicker("Received", selection: $receivedDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $detail, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Project" : "New Project")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let project {
            title = project.title
            detail = project.detail
            status = project.status
            serviceType = project.serviceType
            priority = project.priority
            selectedClientID = project.client?.id
            hasDueDate = project.dueDate != nil
            dueDate = project.dueDate ?? .now
            nextAction = project.nextAction
            hasReceivedDate = project.receivedDate != nil
            receivedDate = project.receivedDate ?? .now
        } else if let defaultClient {
            selectedClientID = defaultClient.id
        }
    }

    private func resolvedClient() -> Client? {
        guard let selectedClientID else { return nil }
        return clients.first { $0.id == selectedClientID }
    }

    private func save() {
        let client = resolvedClient()

        let trimmedNextAction = nextAction.trimmingCharacters(in: .whitespaces)

        if let project {
            project.title = title
            project.detail = detail
            project.status = status
            project.serviceType = serviceType
            project.priority = priority
            project.client = client
            project.dueDate = hasDueDate ? dueDate : nil
            project.nextAction = trimmedNextAction
            project.receivedDate = hasReceivedDate ? receivedDate : nil
        } else if let templateID = selectedTemplateID,
                  let template = templates.first(where: { $0.id == templateID }) {
            let created = WorkflowEngine.instantiate(
                template: template,
                for: client,
                startDate: .now,
                into: context,
                titleOverride: title
            )
            created.detail = detail
            created.status = status
            created.priority = priority
            if hasDueDate { created.dueDate = dueDate }
            created.nextAction = trimmedNextAction
            created.receivedDate = hasReceivedDate ? receivedDate : nil
        } else {
            let created = Project(
                title: title,
                detail: detail,
                status: status,
                serviceType: serviceType,
                priority: priority,
                dueDate: hasDueDate ? dueDate : nil,
                client: client
            )
            created.nextAction = trimmedNextAction
            created.receivedDate = hasReceivedDate ? receivedDate : nil
            context.insert(created)
        }

        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
        dismiss()
    }
}
