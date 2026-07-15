import SwiftUI
import SwiftData
import Charts

/// Practice-at-a-glance reports: billable hours & amounts by client for a
/// selected period, unbilled work in progress, open work by pipeline stage,
/// and what's overdue. Pure computation over existing SwiftData fetches.
struct ReportsView: View {
    @Query private var timeEntries: [TimeEntry]
    @Query private var projects: [Project]

    @State private var period: Period = .month

    enum Period: String, CaseIterable, Identifiable {
        case month = "Month"
        case quarter = "Quarter"
        case ytd = "YTD"
        var id: String { rawValue }
    }

    private struct ClientAmount: Identifiable {
        let id = UUID()
        let name: String
        let hours: Double
        let amount: Double
    }

    private var periodStart: Date {
        let calendar = Calendar.current
        let now = Date.now
        switch period {
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .quarter:
            let month = calendar.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var components = calendar.dateComponents([.year], from: now)
            components.month = quarterStartMonth
            components.day = 1
            return calendar.date(from: components) ?? now
        case .ytd:
            var components = calendar.dateComponents([.year], from: now)
            components.month = 1
            components.day = 1
            return calendar.date(from: components) ?? now
        }
    }

    private var periodEntries: [TimeEntry] {
        timeEntries.filter { !$0.isRunning && $0.startedAt >= periodStart }
    }

    private func grouped(_ entries: [TimeEntry]) -> [ClientAmount] {
        let byClient = Dictionary(grouping: entries) { $0.clientName.isEmpty ? "No client" : $0.clientName }
        return byClient.map { name, entries in
            ClientAmount(
                name: name,
                hours: entries.reduce(0) { $0 + $1.durationSeconds } / 3600.0,
                amount: entries.reduce(0) { $0 + $1.billableAmount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var byClient: [ClientAmount] { grouped(periodEntries) }
    private var totalHoursSeconds: Double { periodEntries.reduce(0) { $0 + $1.durationSeconds } }
    private var totalBillable: Double { periodEntries.reduce(0) { $0 + $1.billableAmount } }

    private var unbilledByClient: [ClientAmount] { grouped(timeEntries.filter(\.isUnbilled)) }

    private var statusCounts: [(status: ProjectStatus, count: Int)] {
        ProjectStatus.allCases.compactMap { status in
            let count = projects.filter { $0.status == status }.count
            return count > 0 ? (status, count) : nil
        }
    }

    private var overdueProjects: [Project] {
        projects.filter(\.isOverdue).sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Billable Hours by Client") {
                LabeledContent("Total", value: "\(Format.hoursMinutes(totalHoursSeconds)) · \(Format.currency(totalBillable))")
                if byClient.isEmpty {
                    Text("No time logged this period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(byClient) { item in
                        BarMark(x: .value("Hours", item.hours), y: .value("Client", item.name))
                            .foregroundStyle(Theme.brand)
                    }
                    .frame(height: CGFloat(byClient.count) * 28 + 20)

                    ForEach(byClient) { item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1fh", item.hours))
                                .foregroundStyle(.secondary)
                            Text(Format.currency(item.amount))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            if !unbilledByClient.isEmpty {
                Section("Unbilled Work in Progress") {
                    ForEach(unbilledByClient) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(Format.currency(item.amount)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !statusCounts.isEmpty {
                Section("Open Work by Stage") {
                    ForEach(statusCounts, id: \.status) { entry in
                        HStack {
                            StatusBadge(status: entry.status)
                            Spacer()
                            Text("\(entry.count)")
                        }
                    }
                }
            }

            if !overdueProjects.isEmpty {
                Section("Overdue") {
                    ForEach(overdueProjects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            HStack {
                                Text(project.title).lineLimit(1)
                                Spacer()
                                if let due = project.dueDate {
                                    Text(Format.relativeDay(due))
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reports")
    }
}
