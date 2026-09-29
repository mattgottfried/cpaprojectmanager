import SwiftUI
import SwiftData

struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringEngagement.name) private var engagements: [RecurringEngagement]
    @State private var editing: RecurringEngagement?
    @State private var showingNew = false

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
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) { RecurringFormView() }
        .sheet(item: $editing) { RecurringFormView(engagement: $0) }
    }

    private func row(_ engagement: RecurringEngagement) -> some View {
        HStack(spacing: 12) {
            ServiceTypeIcon(serviceType: engagement.serviceType, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(engagement.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(engagement.frequency.label) · Next due \(Format.shortDate.string(from: engagement.nextDueDate))")
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

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(engagements[index]) }
        try? context.save()
    }
}
