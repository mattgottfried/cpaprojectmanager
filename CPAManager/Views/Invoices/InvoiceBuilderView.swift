import SwiftUI
import SwiftData

/// Builds an invoice from a client's unbilled, completed time entries. Each
/// selected entry becomes its own line item (hours x its recorded rate).
struct InvoiceBuilderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var timeEntries: [TimeEntry]
    @Query(sort: \Invoice.number, order: .reverse) private var existingInvoices: [Invoice]

    @State private var selectedClientID: UUID?
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var dueInDays = 30

    private var client: Client? {
        guard let selectedClientID else { return nil }
        return clients.first { $0.id == selectedClientID }
    }

    private var unbilledEntries: [TimeEntry] {
        guard let client else { return [] }
        return timeEntries
            .filter { $0.isUnbilled && $0.project?.client?.id == client.id }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var selectedTotal: Double {
        unbilledEntries
            .filter { selectedEntryIDs.contains($0.id) }
            .reduce(0) { $0 + $1.billableAmount }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Client", selection: $selectedClientID) {
                        Text("Select a client").tag(UUID?.none)
                        ForEach(clients) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Stepper("Due in \(dueInDays) days", value: $dueInDays, in: 0...90)
                }

                if client != nil {
                    Section("Unbilled Time") {
                        if unbilledEntries.isEmpty {
                            Text("No unbilled time for this client.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(unbilledEntries) { entry in
                                entryRow(entry)
                            }
                        }
                    }

                    if !unbilledEntries.isEmpty {
                        Section {
                            LabeledContent("Selected total", value: Format.currency(selectedTotal))
                        }
                    }
                }
            }
            .navigationTitle("New Invoice")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: createInvoice)
                        .disabled(client == nil || selectedEntryIDs.isEmpty)
                }
            }
        }
        .macSheetFrame()
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        Button {
            toggle(entry)
        } label: {
            HStack {
                Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedEntryIDs.contains(entry.id) ? Theme.brand : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.projectTitle.isEmpty ? "General time" : entry.projectTitle)
                        .foregroundStyle(.primary)
                    Text("\(Format.shortDate.string(from: entry.startedAt)) · \(Format.hoursMinutes(entry.durationSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.currency(entry.billableAmount))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ entry: TimeEntry) {
        if selectedEntryIDs.contains(entry.id) {
            selectedEntryIDs.remove(entry.id)
        } else {
            selectedEntryIDs.insert(entry.id)
        }
    }

    private func createInvoice() {
        guard let client else { return }
        let nextNumber = (existingInvoices.map(\.number).max() ?? 1000) + 1
        let invoice = Invoice(
            number: nextNumber,
            issueDate: .now,
            dueDate: Calendar.current.date(byAdding: .day, value: dueInDays, to: .now) ?? .now,
            client: client
        )
        context.insert(invoice)

        let selected = unbilledEntries.filter { selectedEntryIDs.contains($0.id) }
        for (index, entry) in selected.enumerated() {
            let hours = (entry.billedHours() * 100).rounded() / 100
            let projectLabel = entry.projectTitle.isEmpty ? "General time" : entry.projectTitle
            let line = InvoiceLine(
                detail: "\(Format.shortDate.string(from: entry.startedAt)) — \(projectLabel)",
                quantity: hours,
                rate: entry.hourlyRate,
                sortIndex: index,
                timeEntryID: entry.id,
                invoice: invoice
            )
            context.insert(line)
            entry.invoiceID = invoice.id
        }

        try? context.save()
        dismiss()
    }
}
