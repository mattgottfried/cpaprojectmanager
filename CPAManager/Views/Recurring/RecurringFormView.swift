import SwiftUI
import SwiftData

struct RecurringFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]

    var engagement: RecurringEngagement?

    @State private var name = ""
    @State private var frequency: Frequency = .monthly
    @State private var serviceType: ServiceType = .bookkeeping
    @State private var selectedClientID: UUID?
    @State private var selectedTemplateID: UUID?
    @State private var nextDueDate = Date.now
    @State private var leadTimeDays = 14
    @State private var isActive = true
    @State private var loaded = false

    private var isEditing: Bool { engagement != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Monthly Bookkeeping — Acme)", text: $name)
                    Picker("Client", selection: $selectedClientID) {
                        Text("No client").tag(UUID?.none)
                        ForEach(clients) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                }

                Section {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Service", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Template", selection: $selectedTemplateID) {
                        Text("None").tag(UUID?.none)
                        ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                    }
                }

                Section {
                    DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
                    Stepper("Start \(leadTimeDays) days before", value: $leadTimeDays, in: 0...90)
                    Toggle("Active", isOn: $isActive)
                } footer: {
                    Text("A project is created automatically \(leadTimeDays) days before each due date, then the schedule advances.")
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
            .navigationBarTitleDisplayMode(.inline)
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
        guard let engagement else { return }
        name = engagement.name
        frequency = engagement.frequency
        serviceType = engagement.serviceType
        selectedClientID = engagement.client?.id
        selectedTemplateID = engagement.template?.id
        nextDueDate = engagement.nextDueDate
        leadTimeDays = engagement.leadTimeDays
        isActive = engagement.isActive
    }

    private func save() {
        let client = selectedClientID.flatMap { id in clients.first { $0.id == id } }
        let template = selectedTemplateID.flatMap { id in templates.first { $0.id == id } }

        let target: RecurringEngagement
        if let engagement {
            target = engagement
        } else {
            target = RecurringEngagement()
            context.insert(target)
        }

        target.name = name
        target.frequency = frequency
        target.serviceType = serviceType
        target.client = client
        target.template = template
        target.nextDueDate = nextDueDate
        target.leadTimeDays = leadTimeDays
        target.isActive = isActive

        try? context.save()
        // Generate immediately if the lead-time window is already open.
        RecurrenceService.run(context: context)
        SnapshotBuilder.rebuild(context: context)
        dismiss()
    }
}
