import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringEngagement.name) private var engagements: [RecurringEngagement]
    @State private var editing: RecurringEngagement?
    @State private var showingNew = false
    @State private var showingBulk = false

    var body: some View {
        List {
            if engagements.isEmpty {
                ContentUnavailableView {
                    Label("No recurring work yet", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Add monthly bookkeeping, quarterly estimates, and more — they generate projects automatically.")
                } actions: {
                    Button("Add recurring work") { showingNew = true }.buttonStyle(.borderedProminent)
                }
                .cardListRow()
            }
            ForEach(engagements) { engagement in
                Button {
                    editing = engagement
                } label: {
                    row(engagement)
                }
                .buttonStyle(.plain)
                .cardListRow()
                .deleteMenu(of: engagement, in: engagements, title: "Delete", perform: delete)
                .swipeActions(edge: .leading) {
                    Button { skipNext(engagement) } label: { Label("Skip next", systemImage: "forward.end.fill") }
                        .tint(.orange)
                    Button { engagement.isActive.toggle(); try? context.save() } label: {
                        Label(engagement.isActive ? "Pause" : "Resume", systemImage: engagement.isActive ? "pause.fill" : "play.fill")
                    }
                    .tint(Theme.brand)
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingNew = true } label: { Label("New Recurring Work", systemImage: "plus") }
                    Button { showingBulk = true } label: { Label("Set Up for Several Clients", systemImage: "person.3.fill") }
                } label: { Image(systemName: "plus").accessibilityLabel("Add recurring work") }
            }
        }
        .sheet(isPresented: $showingNew) { RecurringFormView() }
        .sheet(isPresented: $showingBulk) { RecurringBulkSetupView() }
        .sheet(item: $editing) { RecurringFormView(engagement: $0) }
    }

    private func row(_ engagement: RecurringEngagement) -> some View {
        HStack(spacing: 12) {
            ServiceTypeIcon(serviceType: engagement.serviceType, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(engagement.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(engagement.frequency.label) · Next due \(Format.shortDate.string(from: engagement.nextDueDate))\(engagement.endDate.map { " · ends \(Format.shortDate.string(from: $0))" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let client = engagement.client {
                    Text(client.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !engagement.isActive {
                CapsuleBadge(text: "Paused", systemImage: "pause.fill", state: .neutral)
            }
        }
        .rowCard(dimmed: !engagement.isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engagement.name)
        .accessibilityValue("\(engagement.frequency.label), next due \(Format.shortDate.string(from: engagement.nextDueDate))\(engagement.isActive ? "" : ", paused")")
        .accessibilityHint("Opens the recurring work")
    }

    /// Moves the schedule past the next occurrence without creating work for it.
    private func skipNext(_ engagement: RecurringEngagement) {
        var next = engagement.frequency.nextDate(after: engagement.nextDueDate)
        if engagement.adjustForWeekends { next = DateMath.skippingWeekend(next, calendar: .current) }
        engagement.nextDueDate = next
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(engagements[index]) }
        try? context.save()
    }
}
