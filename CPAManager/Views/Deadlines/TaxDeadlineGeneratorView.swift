import SwiftUI
import SwiftData

/// Creates filing-deadline tasks for every active client in one go.
struct TaxDeadlineGeneratorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @State private var taxYear = Calendar.current.component(.year, from: .now) - 1
    @State private var includeEstimates = true
    @State private var result: String?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var eligible: [Client] {
        clients.filter { $0.status != .inactive && TaxCalendar.form(for: $0.entityType) != nil }
    }

    private var previewCount: Int {
        eligible.reduce(0) {
            $0 + TaxCalendar.deadlines(for: $1.entityType, taxYear: taxYear, extended: $1.extensionYears.contains(taxYear), includeEstimates: includeEstimates).count
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tax year", selection: $taxYear) {
                        ForEach((currentYear - 3)...currentYear, id: \.self) { Text(String($0)).tag($0) }
                    }
                    Toggle("Include 1040 estimated payments", isOn: $includeEstimates)
                } footer: {
                    Text("Extended due dates are added for clients marked “extension filed” for that year.")
                }

                Section("Preview") {
                    LabeledContent("Active clients with an entity type", value: "\(eligible.count)")
                    LabeledContent("Deadlines to add", value: "\(previewCount)")
                    ForEach(eligible.prefix(8)) { client in
                        HStack {
                            Text(client.displayName).lineLimit(1)
                            Spacer()
                            EntityBadge(entityType: client.entityType)
                            if client.extensionYears.contains(taxYear) { CapsuleBadge(text: "Ext.", systemImage: "calendar.badge.clock", state: .caution) }
                        }
                        .font(.subheadline)
                    }
                    if eligible.count > 8 { Text("…and \(eligible.count - 8) more").font(.caption).foregroundStyle(.secondary) }
                }

                Section {
                    Button {
                        let count = TaxDeadlineService.createTasks(for: eligible, taxYear: taxYear, includeEstimates: includeEstimates, context: context)
                        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
                        result = count == 0 ? "Nothing new — those deadlines are already tasks." : "Added \(count) task\(count == 1 ? "" : "s")."
                    } label: {
                        Label("Add deadline tasks", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(eligible.isEmpty)
                    if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("Calendar-year federal dates, moved past weekends and holidays. Confirm against the IRS calendar for fiscal-year clients and disaster-relief postponements.")
                }
            }
            .navigationTitle("Tax Deadlines")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .macSheetFrame()
    }
}
