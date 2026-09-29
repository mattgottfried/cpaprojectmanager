import SwiftUI
import SwiftData
import Charts

/// Practice-at-a-glance reports: billable hours & amounts by client for a
/// selected period, unbilled work in progress, open work by pipeline stage,
/// and what's overdue. Pure computation over existing SwiftData fetches.
struct ReportsView: View {
    @Query private var timeEntries: [TimeEntry]
    @Query private var projects: [Project]
    @Query private var invoices: [Invoice]

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

    private var sentInvoices: [Invoice] { invoices.filter { $0.status == .sent } }
    private var outstanding: Double { sentInvoices.reduce(0) { $0 + $1.balance } }
    private var overdueAmount: Double { sentInvoices.filter(\.isOverdue).reduce(0) { $0 + $1.balance } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    StatChip(value: Format.hoursMinutes(totalHoursSeconds), label: "Hours", state: .info)
                    StatChip(value: Format.currency(totalBillable), label: "Billable", state: .good)
                    StatChip(value: Format.currency(outstanding), label: "Outstanding", state: outstanding > 0 ? .caution : .neutral)
                    StatChip(value: Format.currency(overdueAmount), label: "Overdue", state: overdueAmount > 0 ? .bad : .neutral)
                }

                SectionCard(title: "Billable Hours by Client", systemImage: "clock.fill", state: .info) {
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
                        .accessibilityLabel("Bar chart of billable hours by client")

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
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !unbilledByClient.isEmpty {
                    SectionCard(title: "Unbilled Work in Progress", systemImage: "hourglass", state: .caution) {
                        ForEach(unbilledByClient) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(Format.currency(item.amount)).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !statusCounts.isEmpty {
                    SectionCard(title: "Open Work by Stage", systemImage: "checklist", state: .info) {
                        ForEach(statusCounts, id: \.status) { entry in
                            HStack {
                                StatusBadge(status: entry.status)
                                Spacer()
                                Text("\(entry.count)").font(.subheadline.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if !overdueProjects.isEmpty {
                    SectionCard(title: "Overdue", systemImage: "exclamationmark.triangle.fill", state: .bad) {
                        ForEach(overdueProjects) { project in
                            NavigationLink {
                                ProjectDetailView(project: project)
                            } label: {
                                HStack {
                                    Text(project.title).lineLimit(1)
                                    Spacer()
                                    if let due = project.dueDate {
                                        DueDatePill(date: due)
                                    }
                                }
                                .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Reports")
    }
}
