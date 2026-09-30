import SwiftUI
import SwiftData

struct TimeLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @Query(sort: \TimeEntry.startedAt, order: .reverse) private var entries: [TimeEntry]
    @State private var toast: UndoToastState?

    private var completed: [TimeEntry] { entries.filter { !$0.isRunning } }

    private var monthEntries: [TimeEntry] {
        let cal = Calendar.current
        return completed.filter {
            cal.isDate($0.startedAt, equalTo: .now, toGranularity: .month)
        }
    }
    private var monthSeconds: Double { monthEntries.reduce(0) { $0 + $1.durationSeconds } }
    private var monthBillable: Double { monthEntries.reduce(0) { $0 + $1.billableAmount } }
    private var unbilledTotal: Double {
        completed.filter(\.isUnbilled).reduce(0) { $0 + $1.billableAmount }
    }

    var body: some View {
        List {
            timerCard
                .cardListRow()

            HStack(spacing: 10) {
                StatChip(value: Format.hoursMinutes(monthSeconds), label: "Tracked this month", state: .info)
                StatChip(value: Format.currency(monthBillable), label: "Billable", state: .good)
                StatChip(value: Format.currency(unbilledTotal), label: "Unbilled", state: unbilledTotal > 0 ? .caution : .neutral)
            }
            .cardListRow()

            if unbilledTotal > 0 {
                Label("Create an invoice from Invoices to bill this time.", systemImage: "doc.text.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .cardListRow()
            }

            Section {
                if completed.isEmpty {
                    ContentUnavailableView("No time logged yet", systemImage: "clock",
                                           description: Text("Start a timer on a project, or a general timer above."))
                        .cardListRow()
                }
                ForEach(completed) { entry in
                    entryRow(entry)
                        .cardListRow()
                        .deleteMenu(of: entry, in: completed, title: "Delete Entry", perform: delete)
                }
                .onDelete(perform: delete)
            } header: {
                Text("Entries").font(.headline).textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .undoToast($toast)
        .navigationTitle("Time")
    }

    private var timerCard: some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: timer.isRunning ? "timer" : "play.fill", state: timer.isRunning ? .alert : .neutral)
            if timer.isRunning {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.label).font(.body.weight(.semibold)).lineLimit(2)
                    if let start = timer.startedAt {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    timer.stop(context: context)
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.bad)
            } else {
                Text("No timer running").font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    timer.start(project: nil, hourlyRate: defaultHourlyRate, isBillable: true, context: context)
                } label: {
                    Label("Start", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
            }
        }
        .rowCard(outline: timer.isRunning ? Theme.alert : nil)
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack(spacing: 12) {
            StatusTile(
                systemImage: entry.isBilled ? "checkmark.circle.fill" : "clock.fill",
                state: entry.isBilled ? .good : (entry.isUnbilled ? .caution : .neutral),
                size: 40
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.projectTitle.isEmpty ? "General time" : entry.projectTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text("\(Format.shortDate.string(from: entry.startedAt))\(entry.clientName.isEmpty ? "" : " · \(entry.clientName)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.hoursMinutes(entry.durationSeconds))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if entry.isBillable && entry.billableAmount > 0 {
                    Text(Format.currency(entry.billableAmount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if entry.isBilled {
                    CapsuleBadge(text: "Billed", systemImage: "checkmark", state: .good)
                } else if entry.isUnbilled {
                    CapsuleBadge(text: "Unbilled", systemImage: "hourglass", state: .caution)
                }
            }
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.projectTitle.isEmpty ? "General time" : entry.projectTitle)
        .accessibilityValue("\(Format.hoursMinutes(entry.durationSeconds)), \(entry.isBilled ? "billed" : (entry.isUnbilled ? "unbilled" : "not billable")), \(Format.shortDate.string(from: entry.startedAt))")
    }

    private func delete(_ offsets: IndexSet) {
        let list = completed
        let doomed = offsets.map { list[$0] }
        toast = context.deleteWithUndo(doomed.count == 1 ? "Deleted time entry" : "Deleted \(doomed.count) entries") {
            for entry in doomed { context.delete(entry) }
        }
    }
}
