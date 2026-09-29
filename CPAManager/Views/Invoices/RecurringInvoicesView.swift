import SwiftUI
import SwiftData

/// Standing bills (retainers). Each one drafts an invoice on its schedule for you to review.
struct RecurringInvoicesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringInvoice.nextIssueDate) private var templates: [RecurringInvoice]
    @State private var editing: RecurringInvoice?
    @State private var showingNew = false

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("No recurring invoices", systemImage: "arrow.triangle.2.circlepath.circle")
                } description: {
                    Text("Set up a retainer once and a draft invoice appears each period for you to review and send.")
                } actions: {
                    Button("New recurring invoice") { showingNew = true }.buttonStyle(.borderedProminent)
                }
                .cardListRow()
            }
            ForEach(templates) { template in
                Button { editing = template } label: { row(template) }
                    .buttonStyle(.plain)
                    .cardListRow()
            }
            .onDelete { offsets in
                for index in offsets { context.delete(templates[index]) }
                try? context.save()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .navigationTitle("Recurring Invoices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New recurring invoice")
            }
        }
        .sheet(isPresented: $showingNew) { RecurringInvoiceFormView() }
        .sheet(item: $editing) { RecurringInvoiceFormView(template: $0) }
    }

    private func row(_ template: RecurringInvoice) -> some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: "arrow.triangle.2.circlepath", state: template.isActive ? .info : .neutral)
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name.isEmpty ? (template.client?.displayName ?? "Recurring invoice") : template.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(template.client?.displayName ?? "No client") · \(template.frequency.label)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Label("Next draft \(Format.relativeDay(template.nextIssueDate).lowercased())", systemImage: "calendar")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.currency(template.total)).font(.subheadline.weight(.semibold).monospacedDigit())
                if !template.isActive { CapsuleBadge(text: "Paused", systemImage: "pause.fill", state: .neutral) }
            }
        }
        .rowCard(dimmed: !template.isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(template.name.isEmpty ? (template.client?.displayName ?? "Recurring invoice") : template.name)
        .accessibilityValue("\(template.frequency.label), \(Format.currency(template.total)), next draft \(Format.relativeDay(template.nextIssueDate))\(template.isActive ? "" : ", paused")")
        .accessibilityHint("Opens the recurring invoice")
    }
}

struct RecurringInvoiceFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]

    var template: RecurringInvoice?

    @State private var name = ""
    @State private var client: Client?
    @State private var frequency: Frequency = .monthly
    @State private var nextIssue = Calendar.current.startOfDay(for: .now)
    @State private var termsDays = 30
    @State private var isActive = true
    @State private var notes = ""
    @State private var lines: [RecurringInvoiceLine] = [RecurringInvoiceLine(detail: "", quantity: 1, rate: 0)]

    private var total: Double {
        Double(lines.reduce(0) { $0 + InvoiceMath.cents($1.amount) }) / 100
    }
    private var canSave: Bool {
        client != nil && lines.contains { !$0.detail.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Client", selection: $client) {
                        Text("Choose…").tag(Client?.none)
                        ForEach(clients) { c in Text(c.displayName).tag(Client?.some(c)) }
                    }
                    TextField("Name (e.g. Monthly bookkeeping retainer)", text: $name)
                    Picker("Repeats", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Next invoice", selection: $nextIssue, displayedComponents: .date)
                    Stepper("Due \(termsDays) days after issue", value: $termsDays, in: 0...120, step: 5)
                    Toggle("Active", isOn: $isActive)
                }

                Section("Line items") {
                    ForEach($lines) { $line in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Description", text: $line.detail)
                            HStack {
                                TextField("Qty", value: $line.quantity, format: .number)
                                    .decimalKeyboard()
                                    .frame(maxWidth: 70)
                                Text("×").foregroundStyle(.secondary)
                                TextField("Rate", value: $line.rate, format: .currency(code: "USD"))
                                    .decimalKeyboard()
                                Spacer()
                                Text(Format.currency(line.amount)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    Button { lines.append(RecurringInvoiceLine(detail: "", quantity: 1, rate: 0)) } label: {
                        Label("Add line", systemImage: "plus")
                    }
                    LabeledContent("Total per invoice", value: Format.currency(total))
                        .font(.headline)
                }

                Section("Notes on each invoice") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
                }

                Section {
                    Text("Invoices are created as drafts for you to review — nothing is sent for you.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(template == nil ? "New Recurring Invoice" : "Edit Recurring Invoice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let template else { return }
        name = template.name
        client = template.client
        frequency = template.frequency
        nextIssue = template.nextIssueDate
        termsDays = template.termsDays
        isActive = template.isActive
        notes = template.notes
        lines = template.lines.isEmpty ? lines : template.lines
    }

    private func save() {
        let cleaned = lines.filter { !$0.detail.trimmingCharacters(in: .whitespaces).isEmpty }
        if let template {
            template.name = name
            template.client = client
            template.frequency = frequency
            template.nextIssueDate = Calendar.current.startOfDay(for: nextIssue)
            template.termsDays = termsDays
            template.isActive = isActive
            template.notes = notes
            template.lines = cleaned
        } else {
            let created = RecurringInvoice(name: name, frequency: frequency, nextIssueDate: Calendar.current.startOfDay(for: nextIssue), termsDays: termsDays, lines: cleaned, client: client)
            created.isActive = isActive
            created.notes = notes
            context.insert(created)
        }
        try? context.save()
        RecurringInvoiceService.run(context: context)
        dismiss()
    }
}
