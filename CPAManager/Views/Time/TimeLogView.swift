import SwiftUI
import SwiftData

struct TimeLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(TimerController.self) private var timer
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @Query(sort: \TimeEntry.startedAt, order: .reverse) private var entries: [TimeEntry]

    private var completed: [TimeEntry] { entries.filter { !$0.isRunning } }

    private var monthEntries: [TimeEntry] {
        let cal = Calendar.current
        return completed.filter {
            cal.isDate($0.startedAt, equalTo: .now, toGranularity: .month)
        }
    }
    private var monthSeconds: Double { monthEntries.reduce(0) { $0 + $1.durationSeconds } }
    private var monthBillable: Double { monthEntries.reduce(0) { $0 + $1.billableAmount } }

    var body: some View {
        List {
            Section {
                if timer.isRunning {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timer.label).font(.body.weight(.medium))
                            if let start = timer.startedAt {
                                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            timer.stop(context: context)
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                        }
                    }
                } else {
                    Button {
                        timer.start(project: nil, hourlyRate: defaultHourlyRate, isBillable: true, context: context)
                    } label: {
                        Label("Start general timer", systemImage: "play.circle.fill")
                    }
                }
            }

            Section("This month") {
                LabeledContent("Tracked", value: Format.hoursMinutes(monthSeconds))
                LabeledContent("Billable", value: Format.currency(monthBillable))
            }

            Section("Entries") {
                if completed.isEmpty {
                    Text("No time logged yet.").foregroundStyle(.secondary)
                }
                ForEach(completed) { entry in
                    entryRow(entry)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Time")
    }

    private func entryRow(_ entry: TimeEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.projectTitle.isEmpty ? "General time" : entry.projectTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(Format.shortDate.string(from: entry.startedAt))\(entry.clientName.isEmpty ? "" : " · \(entry.clientName)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.hoursMinutes(entry.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                if entry.isBillable && entry.billableAmount > 0 {
                    Text(Format.currency(entry.billableAmount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(completed[index]) }
        try? context.save()
    }
}
