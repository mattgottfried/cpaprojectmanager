import SwiftUI
import SwiftData

/// Filing deadlines for one client, computed from their entity type and whether an
/// extension was filed for the year.
struct TaxDeadlinesSection: View {
    @Bindable var client: Client

    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @State private var taxYear = Calendar.current.component(.year, from: .now) - 1
    @State private var message: String?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var deadlines: [TaxCalendar.Deadline] {
        TaxCalendar.deadlines(for: client.entityType, taxYear: taxYear, extended: client.extensionYears.contains(taxYear))
    }

    var body: some View {
        if TaxCalendar.form(for: client.entityType) != nil {
            Section {
                Picker("Tax year", selection: $taxYear) {
                    ForEach((currentYear - 3)...currentYear, id: \.self) { Text(String($0)).tag($0) }
                }
                Toggle("Extension filed for \(String(taxYear))", isOn: extensionBinding)

                ForEach(deadlines) { deadline in
                    HStack(spacing: 10) {
                        Image(systemName: icon(deadline.kind))
                            .foregroundStyle(Theme.color(deadline.kind == .extended ? .caution : .info))
                            .accessibilityHidden(true)
                        Text(deadline.title).font(.subheadline)
                        Spacer(minLength: 6)
                        Text(deadline.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(deadline.date < .now ? Color.secondary : Color.primary)
                    }
                    .accessibilityElement(children: .combine)
                }

                Button {
                    let count = TaxDeadlineService.createTasks(for: [client], taxYear: taxYear, includeEstimates: true, context: context)
                    NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
                    message = count == 0 ? "Already on your task list." : "Added \(count) task\(count == 1 ? "" : "s") to Today."
                } label: {
                    Label("Add deadlines to my tasks", systemImage: "calendar.badge.plus")
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Tax deadlines")
            } footer: {
                Text("Calendar-year federal dates, moved to the next business day when they fall on a weekend or holiday. Confirm against the IRS calendar, especially for fiscal-year clients or disaster-relief postponements.")
            }
        }
    }

    private var extensionBinding: Binding<Bool> {
        Binding(
            get: { client.extensionYears.contains(taxYear) },
            set: { on in
                var years = client.extensionYears
                if on { years.insert(taxYear) } else { years.remove(taxYear) }
                client.extensionYears = years
                try? context.save()
                message = nil
            }
        )
    }

    private func icon(_ kind: TaxCalendar.Kind) -> String {
        switch kind {
        case .filing:           return "doc.text"
        case .extended:         return "calendar.badge.clock"
        case .estimatedPayment: return "banknote"
        }
    }
}
