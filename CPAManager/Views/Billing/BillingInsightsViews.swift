import SwiftUI
import SwiftData

/// Turns a finished job into a draft invoice: its unbilled time plus any fee-schedule items.
struct BillJobSheet: View {
    let project: Project
    var onCreated: ((Invoice) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FeeItem.sortIndex) private var feeItems: [FeeItem]
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var feeQuantities: [UUID: Double] = [:]
    @State private var dueInDays = 30
    @State private var preselected = false

    private var entries: [TimeEntry] { BillingService.unbilledEntries(for: project) }
    private var selectedEntries: [TimeEntry] { entries.filter { selectedEntryIDs.contains($0.id) } }

    private var fees: [BillFeeInput] {
        feeItems.map { BillFeeInput(name: $0.name, unitPrice: $0.unitPrice, quantity: feeQuantities[$0.id] ?? 0) }
    }

    private var draftLines: [BillLine] {
        let inputs = selectedEntries.map {
            BillEntryInput(id: $0.id, label: project.title, hours: $0.billedHours(), rate: $0.hourlyRate)
        }
        return BillFromJob.lines(entries: inputs, fees: fees)
    }

    private var total: Double { Double(BillFromJob.totalCents(draftLines)) / 100 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Bill to", value: project.clientName)
                    Stepper("Due in \(dueInDays) days", value: $dueInDays, in: 0...90)
                }

                Section("Unbilled time") {
                    if entries.isEmpty {
                        Text("No unbilled time on this job.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        Button { toggle(entry) } label: {
                            HStack {
                                Image(systemName: selectedEntryIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedEntryIDs.contains(entry.id) ? Theme.brand : Color.secondary)
                                Text("\(Format.shortDate.string(from: entry.startedAt)) · \(Format.hoursMinutes(entry.durationSeconds))")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(Format.currency(entry.billableAmount)).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !feeItems.isEmpty {
                    Section {
                        ForEach(feeItems) { item in
                            Stepper(value: quantityBinding(item), in: 0...100, step: item.isHourly ? 0.5 : 1) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(item.isHourly ? "\(Format.currency(item.unitPrice))/hr" : Format.currency(item.unitPrice))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Fee schedule")
                    } footer: {
                        Text("Set a quantity to add an item to the invoice.")
                    }
                }

                Section {
                    LabeledContent("Invoice total", value: Format.currency(total))
                        .font(.headline)
                }
            }
            .navigationTitle("Invoice for Job")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(draftLines.isEmpty || project.client == nil)
                }
            }
            .onAppear {
                guard !preselected else { return }
                preselected = true
                selectedEntryIDs = Set(entries.map(\.id))
            }
        }
        .macSheetFrame()
    }

    private func quantityBinding(_ item: FeeItem) -> Binding<Double> {
        Binding(get: { feeQuantities[item.id] ?? 0 }, set: { feeQuantities[item.id] = $0 })
    }

    private func toggle(_ entry: TimeEntry) {
        if selectedEntryIDs.contains(entry.id) { selectedEntryIDs.remove(entry.id) } else { selectedEntryIDs.insert(entry.id) }
    }

    private func create() {
        if let invoice = BillingService.createInvoice(for: project, entries: selectedEntries, fees: fees,
                                                      dueInDays: dueInDays, context: context) {
            onCreated?(invoice)
        }
        dismiss()
    }
}

/// Reports card: finished jobs that never went on an invoice.
struct UnbilledWorkCard: View {
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]
    @State private var billing: Project?

    private var jobs: [UnbilledJob] { UnbilledWork.find(BillingService.unbilledInputs(projects)) }

    var body: some View {
        let list = jobs
        if !list.isEmpty {
            SectionCard(title: "Finished, not billed", systemImage: "exclamationmark.circle.fill", state: .caution) {
                if UnbilledWork.totalCents(list) > 0 {
                    Text("\(Format.currency(Double(UnbilledWork.totalCents(list)) / 100)) of billable time isn't on an invoice yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(list) { job in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title).lineLimit(1)
                            Text(detail(job)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if job.amountCents > 0 {
                            Text(Format.currency(Double(job.amountCents) / 100)).font(.subheadline.monospacedDigit())
                        }
                        Menu {
                            Button { billing = project(job) } label: { Label("Create invoice…", systemImage: "doc.badge.plus") }
                            Divider()
                            Button { settle(job, as: .notBillable) } label: { Label("Not billable", systemImage: "hand.raised") }
                            Button { settle(job, as: .billedElsewhere) } label: { Label("Billed elsewhere", systemImage: "checkmark.circle") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Bill or settle \(job.title)")
                    }
                    .font(.subheadline)
                }
            }
            .sheet(item: $billing) { BillJobSheet(project: $0) }
        }
    }

    private func detail(_ job: UnbilledJob) -> String {
        switch job.reason {
        case .unbilledTime: return "\(job.clientName) · \(String(format: "%.1f", job.hours)) unbilled hours"
        case .noInvoice:    return "\(job.clientName) · nothing invoiced"
        }
    }

    private func project(_ job: UnbilledJob) -> Project? { projects.first { $0.id == job.id } }

    private func settle(_ job: UnbilledJob, as state: BillingState) {
        guard let project = project(job) else { return }
        BillingService.markSettled(project, as: state)
        try? context.save()
    }
}

/// Reports card: what each client really pays per hour.
struct ProfitabilityCard: View {
    @Query(sort: \Client.name) private var clients: [Client]
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultRate = 150.0
    @State private var period: Period = .last12

    enum Period: String, CaseIterable, Identifiable {
        case last12 = "12 months"
        case ytd = "This year"
        case all = "All time"
        var id: String { rawValue }
    }

    private var start: Date? {
        let cal = Calendar.current
        switch period {
        case .last12: return cal.date(byAdding: .month, value: -12, to: .now)
        case .ytd:    return cal.date(from: DateComponents(year: cal.component(.year, from: .now), month: 1, day: 1))
        case .all:    return nil
        }
    }

    var body: some View {
        let rows = Profitability.rows(BillingService.profitInputs(clients: clients, defaultRate: defaultRate, since: start))
        SectionCard(title: "Effective hourly rate", systemImage: "dollarsign.gauge.chart.leftthird.topthird.rightthird", state: .info) {
            Picker("Period", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if rows.isEmpty {
                Text("Nothing invoiced or logged in this period.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                if let overall = Profitability.overallRate(rows) {
                    Text("Overall: \(Format.currency(overall)) per hour (invoiced ÷ hours logged).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(rows.prefix(12)) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.clientName).lineLimit(1)
                            Text("\(Format.currency(row.revenue)) · \(String(format: "%.1f", row.hours)) hrs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let rate = row.effectiveRate {
                            Text("\(Format.currency(rate))/hr").font(.subheadline.monospacedDigit())
                                .foregroundStyle(row.isBelowStandard ? Theme.color(.caution) : Color.primary)
                        } else {
                            Text("no time").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(row.isBelowStandard ? "below your standard rate" : "")
                }
                Text("Amber = below the rate you'd normally bill this client. Lowest first.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
