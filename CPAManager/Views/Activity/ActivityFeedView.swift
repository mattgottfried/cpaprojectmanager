import SwiftUI
import SwiftData

/// A timeline of what happened — tasks finished, emails logged, payments received,
/// clients added — built from the timestamps already on your records.
struct ActivityFeedView: View {
    /// True when pushed from another stack so it doesn't nest a second NavigationStack.
    var embedded = false

    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]
    @Query private var interactions: [Interaction]
    @Query private var payments: [Payment]
    @Query private var invoices: [Invoice]
    @Query private var projects: [Project]
    @Query private var clients: [Client]
    @Query private var documents: [Document]
    @Query private var expenses: [Expense]
    @Query private var timeEntries: [TimeEntry]
    @Query private var requests: [DocumentRequest]
    @Query private var inbox: [InboxItem]

    @AppStorage("activityDays") private var days = 7

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var events: [ActivityEvent] {
        var result: [ActivityEvent] = []
        func clientLink(_ c: Client?) -> String? { c.map { DeepLink.client($0.id).identifier } }

        for t in tasks {
            if let done = t.completedAt, t.isDone {
                result.append(ActivityEvent(id: "done-\(t.id)", date: done, kind: .taskDone, title: "Completed: \(t.title)",
                                            detail: t.project?.title ?? t.client?.displayName ?? "",
                                            link: t.project.map { DeepLink.project($0.id).identifier } ?? clientLink(t.client)))
            } else if t.project == nil {
                result.append(ActivityEvent(id: "task-\(t.id)", date: t.createdAt, kind: .taskAdded, title: "Added: \(t.title)",
                                            detail: t.client?.displayName ?? "", link: clientLink(t.client)))
            }
        }
        for i in interactions {
            result.append(ActivityEvent(id: "int-\(i.id)", date: i.occurredAt, kind: .contact,
                                        title: "\(i.kind.label): \(i.client?.displayName ?? "Client")",
                                        detail: i.summary, link: clientLink(i.client)))
        }
        for p in payments {
            result.append(ActivityEvent(id: "pay-\(p.id)", date: p.date, kind: .payment,
                                        title: "Payment received: \(Format.currency(p.amount))",
                                        detail: [p.invoice?.displayNumber, p.invoice?.client?.displayName].compactMap { $0 }.joined(separator: " · "),
                                        link: p.invoice.map { DeepLink.invoice($0.id).identifier }))
        }
        for i in invoices {
            result.append(ActivityEvent(id: "inv-\(i.id)", date: i.createdAt, kind: .invoice,
                                        title: "\(i.status == .draft ? "Draft invoice" : "Invoice") \(i.displayNumber)",
                                        detail: "\(i.client?.displayName ?? "") · \(Format.currency(i.total))",
                                        link: DeepLink.invoice(i.id).identifier))
        }
        for p in projects {
            if let done = p.completedAt {
                result.append(ActivityEvent(id: "pdone-\(p.id)", date: done, kind: .project, title: "Completed: \(p.title)",
                                            detail: p.clientName, link: DeepLink.project(p.id).identifier))
            }
            result.append(ActivityEvent(id: "pnew-\(p.id)", date: p.createdAt, kind: .project, title: "New work: \(p.title)",
                                        detail: p.clientName, link: DeepLink.project(p.id).identifier))
        }
        for c in clients {
            result.append(ActivityEvent(id: "cnew-\(c.id)", date: c.createdAt, kind: .client, title: "New \(c.status == .prospect ? "lead" : "client"): \(c.displayName)",
                                        link: DeepLink.client(c.id).identifier))
        }
        for d in documents {
            result.append(ActivityEvent(id: "doc-\(d.id)", date: d.createdAt, kind: .document, title: "Filed: \(d.displayName)",
                                        detail: d.project?.title ?? d.client?.displayName ?? "",
                                        link: d.project.map { DeepLink.project($0.id).identifier } ?? clientLink(d.client)))
        }
        for e in expenses {
            result.append(ActivityEvent(id: "exp-\(e.id)", date: e.date, kind: .expense,
                                        title: "Expense: \(e.vendor.isEmpty ? e.category.label : e.vendor)",
                                        detail: Format.currency(e.amount)))
        }
        for t in timeEntries where !t.isRunning {
            if let end = t.endedAt {
                result.append(ActivityEvent(id: "time-\(t.id)", date: end, kind: .time,
                                            title: "Logged \(Format.hoursMinutes(t.durationSeconds))",
                                            detail: [t.projectTitle, t.clientName].filter { !$0.isEmpty }.joined(separator: " · ")))
            }
        }
        for r in requests {
            if let received = r.receivedAt {
                result.append(ActivityEvent(id: "req-\(r.id)", date: received, kind: .document, title: "Received: \(r.title)",
                                            detail: r.client?.displayName ?? "", link: clientLink(r.client)))
            }
        }
        for i in inbox {
            result.append(ActivityEvent(id: "in-\(i.id)", date: i.createdAt, kind: .inbox, title: "Captured (\(i.source.label)): \(String(i.text.prefix(80)))"))
        }
        return result
    }

    private var content: some View {
        let sections = ActivityFeed.sections(events, days: days)
        return List {
            Picker("Range", selection: $days) {
                Text("Today").tag(1)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            .cardListRow()

            if sections.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("As you work, a timeline of what you did shows up here."))
                    .cardListRow()
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.events) { event in
                        eventRow(event)
                            .cardListRow()
                    }
                } header: {
                    HStack {
                        Text(section.label).font(.headline)
                        Spacer()
                        Text("\(section.events.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .navigationTitle("Activity")
    }

    @ViewBuilder
    private func eventRow(_ event: ActivityEvent) -> some View {
        let card = HStack(alignment: .top, spacing: 12) {
            StatusTile(systemImage: event.kind.systemImage, state: event.kind.state, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !event.detail.isEmpty {
                    Text(event.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.title)
        .accessibilityValue("\(event.detail.isEmpty ? "" : event.detail + ", ")\(event.date.formatted(date: .omitted, time: .shortened))")

        if let identifier = event.link, let link = DeepLink(identifier: identifier) {
            Button { router.open(link) } label: { card }
                .buttonStyle(.plain)
                .accessibilityHint("Opens it")
        } else {
            card
        }
    }
}
