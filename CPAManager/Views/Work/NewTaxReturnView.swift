import SwiftUI
import SwiftData

/// Quick intake for a new tax return, mirroring the firm's "New Tax Return"
/// Shortcut: client, return type, and the date documents were received compute a
/// due date (received + 9 days, weekend-adjusted) and file the project under
/// Awaiting Docs with a standard next action.
struct NewTaxReturnView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var templates: [WorkflowTemplate]

    @State private var selectedClientID: UUID?
    @State private var newClientName = ""
    @State private var returnType: EntityType = .individual1040
    @State private var receivedDate = Date.now

    private let returnTypes = EntityType.allCases.filter { $0 != .other }

    private var isNewClient: Bool { selectedClientID == nil }
    private var canSave: Bool {
        isNewClient ? !newClientName.trimmingCharacters(in: .whitespaces).isEmpty : true
    }
    private var computedDueDate: Date {
        DateMath.addingDaysWeekendAdjusted(9, to: receivedDate)
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
                }

                Section {
                    Text("Due \(Format.mediumDate.string(from: computedDueDate)) · filed under Awaiting Docs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Tax Return")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: save).disabled(!canSave) }
            }
        }
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

        if let routingSheet = templates.first(where: { $0.name == "Tax Return Routing Sheet" }) {
            WorkflowEngine.applyTemplate(routingSheet, to: project, startDate: receivedDate, into: context)
        }

        try? context.save()
        SnapshotBuilder.rebuild(context: context)
        NotificationScheduler.rescheduleAll(context: context)
        dismiss()
    }
}
