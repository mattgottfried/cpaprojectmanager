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
                Text("No recurring work yet. Add monthly bookkeeping, quarterly estimates, and more — they generate projects automatically.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(engagements) { engagement in
                Button {
                    editing = engagement
                } label: {
                    row(engagement)
                }
            }
            .onDelete(perform: delete)
        }
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
            ServiceTypeIcon(serviceType: engagement.serviceType, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(engagement.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text("\(engagement.frequency.label) · Next due \(Format.shortDate.string(from: engagement.nextDueDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let client = engagement.client {
                    Text(client.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !engagement.isActive {
                Image(systemName: "pause.circle.fill").foregroundStyle(.secondary)
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(engagements[index]) }
        try? context.save()
    }
}
