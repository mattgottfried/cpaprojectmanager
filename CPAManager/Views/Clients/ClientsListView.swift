import SwiftUI
import SwiftData

struct ClientsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @State private var search = ""
    @State private var showingAdd = false

    private var filtered: [Client] {
        guard !search.isEmpty else { return clients }
        return clients.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.email.localizedCaseInsensitiveContains(search)
                || $0.company.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if clients.isEmpty {
                    EmptyStateView(
                        title: "No Clients",
                        message: "Add your first client to start tracking their work.",
                        systemImage: "person.2"
                    )
                } else {
                    List {
                        ForEach(filtered) { client in
                            NavigationLink(value: client) {
                                ClientRow(client: client)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Clients")
            .searchable(text: $search, prompt: "Search clients")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
            .sheet(isPresented: $showingAdd) { ClientFormView() }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
        SnapshotBuilder.rebuild(context: context)
    }
}

struct ClientRow: View {
    let client: Client

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: client.initials)
            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    EntityBadge(entityType: client.entityType)
                    let open = client.openProjects.count
                    if open > 0 {
                        Text("\(open) open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            ClientStatusBadge(status: client.status)
        }
        .padding(.vertical, 4)
    }
}
