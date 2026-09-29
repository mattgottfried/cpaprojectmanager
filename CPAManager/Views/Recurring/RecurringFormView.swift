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
    @State private var adjustForWeekends = true
    @State private var isActive = true
    @State private var hasEndDate = false
    @State private var endDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var namingPattern = ""
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
                    Toggle("Adjust for weekends", isOn: $adjustForWeekends)
                    Toggle("Active", isOn: $isActive)
                    Toggle("Ends", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("Last due date", selection: $endDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("A project is created automatically \(leadTimeDays) days before each due date, then the schedule advances.")
                }

                Section {
                    TextField(RecurringNaming.defaultPattern, text: $namingPattern)
                        .noAutocapitalization()
                } header: {
                    Text("Naming")
                } footer: {
                    Text("Tokens: {name} {client} {period} {month} {monthnum} {year} {quarter} {due} {frequency}. Leave blank for \"\(RecurringNaming.defaultPattern)\".")
                }

                Section("Upcoming") {
                    ForEach(previewDates, id: \.self) { due in
                        HStack {
                            Text(previewTitle(due))
                                .lineLimit(1)
                            Spacer()
                            Text(Format.shortDate.string(from: due))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if previewDates.isEmpty {
                        Text("Nothing scheduled — check the end date.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: loadOnce)
        }
    }

    private var previewDates: [Date] {
        RecurrencePreview.dates(
            startingAt: nextDueDate,
            frequency: frequency,
            count: 6,
            adjustForWeekends: adjustForWeekends,
            endDate: hasEndDate ? endDate : nil
        )
    }

    private func previewTitle(_ due: Date) -> String {
        let clientName = selectedClientID.flatMap { id in clients.first { $0.id == id } }?.displayName ?? ""
        return RecurringNaming.title(pattern: namingPattern, name: name.isEmpty ? "Work" : name, clientName: clientName, frequency: frequency, due: due)
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
        adjustForWeekends = engagement.adjustForWeekends
        isActive = engagement.isActive
        hasEndDate = engagement.endDate != nil
        endDate = engagement.endDate ?? endDate
        namingPattern = engagement.namingPattern
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
        target.adjustForWeekends = adjustForWeekends
        target.isActive = isActive
        target.endDate = hasEndDate ? endDate : nil
        target.namingPattern = namingPattern.trimmingCharacters(in: .whitespaces)

        try? context.save()
        // Generate immediately if the lead-time window is already open.
        RecurrenceService.run(context: context)
        SnapshotBuilder.rebuild(context: context)
        dismiss()
    }
}
