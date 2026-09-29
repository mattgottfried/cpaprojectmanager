import SwiftUI
import SwiftData

struct DeadlinesView: View {
    @Query private var projects: [Project]
    @Query private var tasks: [TaskItem]
    @State private var showingTaxDates = false
    @State private var showingGenerator = false
    @State private var calendarRequest: CalendarEventRequest?
    /// True when pushed from another stack (e.g. More) so it doesn't nest a second
    /// NavigationStack.
    var embedded = false

    private var grouped: [(bucket: String, items: [AgendaItem])] {
        let items = Agenda.items(projects: projects, tasks: tasks)
        let byBucket = Dictionary(grouping: items) { Agenda.bucket(for: $0.dueDate) }
        return Agenda.bucketOrder.compactMap { key in
            guard let arr = byBucket[key], !arr.isEmpty else { return nil }
            return (key, arr)
        }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            List {
                if grouped.isEmpty {
                    Section {
                        Text("Nothing due right now.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(grouped, id: \.bucket) { group in
                        Section(header: bucketHeader(group.bucket, count: group.items.count)) {
                            ForEach(group.items) { item in
                                deadlineRow(item)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingTaxDates = true
                    } label: {
                        Label("Standard tax deadlines", systemImage: "calendar.badge.exclamationmark")
                    }
                    Button {
                        showingGenerator = true
                    } label: {
                        Label("Add filing deadlines for my clients…", systemImage: "wand.and.stars")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.appGroupedBackground)
            .navigationTitle("Deadlines")
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $showingTaxDates) { TaxDatesView() }
            .sheet(isPresented: $showingGenerator) { TaxDeadlineGeneratorView() }
            .sheet(item: $calendarRequest) { CalendarEventView(request: $0) }
        }
    }

    private func bucketHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .foregroundStyle(title == "Overdue" ? Theme.bad : Color.secondary)
    }

    @ViewBuilder
    private func deadlineRow(_ item: AgendaItem) -> some View {
        let bucket = Agenda.bucket(for: item.dueDate)
        let state: SemanticState = bucket == "Overdue" ? .bad : (bucket == "Today" ? .alert : .neutral)
        let content = HStack(spacing: 12) {
            StatusTile(
                systemImage: item.id == item.project?.id ? "folder.fill" : "checkmark.circle",
                state: state, size: 40
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            DueDatePill(date: item.dueDate, isComplete: item.isComplete)
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue("\(bucket), \(Format.relativeDay(item.dueDate)), \(item.subtitle)")

        Group {
            if let project = item.project {
                NavigationLink(value: project) { content }
            } else {
                content
            }
        }
        .cardListRow()
        .contextMenu {
            Button {
                calendarRequest = CalendarEventRequest(title: item.title, date: item.dueDate, notes: item.subtitle)
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }
        }
    }
}

/// A static, evergreen reference of common US filing deadlines.
struct TaxDatesView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Deadline: Identifiable {
        let id = UUID()
        let date: String
        let description: String
    }

    private let deadlines: [Deadline] = [
        .init(date: "Jan 15", description: "Q4 estimated tax payment (prior year)"),
        .init(date: "Jan 31", description: "W-2s & 1099-NEC to recipients and IRS/SSA"),
        .init(date: "Mar 15", description: "S-Corp (1120-S) & Partnership (1065) returns"),
        .init(date: "Apr 15", description: "Individual (1040), C-Corp (1120), Q1 estimates, IRA contributions"),
        .init(date: "Jun 15", description: "Q2 estimated tax payment"),
        .init(date: "Sep 15", description: "Q3 estimates; extended S-Corp & Partnership returns"),
        .init(date: "Oct 15", description: "Extended individual (1040) returns"),
        .init(date: "Dec 15", description: "Extended C-Corp (1120) returns"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(deadlines) { deadline in
                        HStack(alignment: .top, spacing: 12) {
                            Text(deadline.date)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.brand)
                                .frame(width: 64, alignment: .leading)
                            Text(deadline.description)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Dates shift to the next business day when they fall on a weekend or holiday. Always confirm against current IRS guidance.")
                }
            }
            .navigationTitle("Tax Deadlines")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
