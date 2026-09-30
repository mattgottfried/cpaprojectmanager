import SwiftUI
import SwiftData

/// Sets up the same recurring work for many clients at once (e.g. monthly bookkeeping
/// for every bookkeeping client). Clients that already have recurring work with the same
/// name are skipped, so running it twice is harmless.
struct RecurringBulkSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \WorkflowTemplate.name) private var templates: [WorkflowTemplate]
    @Query private var existing: [RecurringEngagement]

    @State private var name = ""
    @State private var frequency: Frequency = .monthly
    @State private var serviceType: ServiceType = .bookkeeping
    @State private var templateID: UUID?
    @State private var firstDue = Date.now
    @State private var leadTimeDays = 14
    @State private var adjustForWeekends = true
    @State private var namingPattern = "{client} - {period}"
    @State private var selected: Set<UUID> = []

    private var candidates: [Client] {
        clients.filter { $0.status != .inactive }
    }

    private func alreadyHas(_ client: Client) -> Bool {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return existing.contains { $0.client?.id == client.id && $0.name.lowercased() == key }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Monthly Bookkeeping)", text: $name)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Service", selection: $serviceType) {
                        ForEach(ServiceType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Template", selection: $templateID) {
                        Text("None").tag(UUID?.none)
                        ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    DatePicker("First due", selection: $firstDue, displayedComponents: .date)
                    Stepper("Start \(leadTimeDays) days before", value: $leadTimeDays, in: 0...90)
                    Toggle("Adjust for weekends", isOn: $adjustForWeekends)
                    TextField(RecurringNaming.defaultPattern, text: $namingPattern)
                        .noAutocapitalization()
                } footer: {
                    Text("Every client gets the same schedule. Titles use the naming pattern, e.g. \"\(sampleTitle)\".")
                }
                Section {
                    ForEach(candidates) { client in
                        let taken = !name.isEmpty && alreadyHas(client)
                        Button {
                            if selected.contains(client.id) { selected.remove(client.id) } else { selected.insert(client.id) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(client.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(client.id) ? Theme.brand : .secondary)
                                Text(client.displayName).foregroundStyle(.primary)
                                Spacer()
                                if taken { Text("Already set up").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .disabled(taken)
                    }
                } header: {
                    HStack {
                        Text("Clients (\(selected.count))")
                        Spacer()
                        Button("All") { selected = Set(candidates.filter { !alreadyHas($0) }.map(\.id)) }
                        Button("None") { selected = [] }
                    }
                }
            }
            .navigationTitle("Set Up Recurring Work")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: save).disabled(!canSave) }
            }
        }
        .macSheetFrame()
    }

    private var sampleTitle: String {
        RecurringNaming.title(
            pattern: namingPattern,
            name: name.isEmpty ? "Work" : name,
            clientName: candidates.first?.displayName ?? "Client",
            frequency: frequency,
            due: firstDue
        )
    }

    private func save() {
        let template = templateID.flatMap { id in templates.first { $0.id == id } }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        for client in candidates where selected.contains(client.id) && !alreadyHas(client) {
            let engagement = RecurringEngagement(
                name: trimmedName,
                frequency: frequency,
                serviceType: serviceType,
                nextDueDate: firstDue,
                leadTimeDays: leadTimeDays,
                adjustForWeekends: adjustForWeekends,
                client: client,
                template: template
            )
            engagement.namingPattern = namingPattern.trimmingCharacters(in: .whitespaces)
            context.insert(engagement)
        }
        try? context.save()
        RecurrenceService.run(context: context)
        SnapshotBuilder.rebuild(context: context)
        dismiss()
    }
}
