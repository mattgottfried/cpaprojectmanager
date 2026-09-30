import SwiftUI
import SwiftData

struct ClientsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \SavedClientFilter.createdAt) private var savedFilters: [SavedClientFilter]

    @State private var search = ""
    @State private var filter = ClientFilter()
    @State private var showingAdd = false
    @State private var showingSave = false
    @State private var linkedClient: Client?
    @Environment(AppRouter.self) private var router
    @State private var newFilterName = ""
    @State private var selection = ListSelection<UUID>()
    @State private var toast: UndoToastState?
    @State private var showingBulkTag = false
    @State private var bulkTag = ""

    private var effectiveFilter: ClientFilter {
        var f = filter
        f.search = search
        return f
    }

    private var filtered: [Client] {
        let f = effectiveFilter
        return clients.filter { f.matches($0.summary) }
    }

    private var tagCounts: [TagSet.TagCount] {
        TagSet.counts(clients.map { $0.tags })
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
                    VStack(spacing: 0) {
                        chipRow
                        List {
                            ForEach(filtered) { client in
                                SelectableRow(
                                    isSelecting: selection.isSelecting,
                                    isSelected: selection.selected.contains(client.id),
                                    isCursor: selection.cursor == client.id,
                                    toggle: { selection.toggle(client.id) }
                                ) {
                                    ClientRow(client: client)
                                } link: {
                                    NavigationLink(value: client) {
                                        ClientRow(client: client)
                                    }
                                }
                                .cardListRow()
                                .deleteMenu("Delete Client") { deleteClients([client]) }
                            }
                            .onDelete(perform: delete)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .overlay {
                            if filtered.isEmpty {
                                ContentUnavailableView.search
                            }
                        }
                    }
                    .background(Color.appGroupedBackground)
                    .macReadableWidth()
                    .listKeyboard(
                        move: { selection.cursor = ListSelection.moved(from: selection.cursor, in: filtered.map(\.id), by: $0) },
                        open: { if let id = selection.cursor { linkedClient = filtered.first { $0.id == id } } },
                        toggle: { if let id = selection.cursor { selection.toggle(id) } },
                        delete: { deleteClients(keyboardTargets) }
                    )
                    .safeAreaInset(edge: .bottom) {
                        if selection.isSelecting { bulkBar }
                    }
                    .onChange(of: filtered.map(\.id)) { _, ids in selection.prune(to: ids) }
                }
            }
            .navigationTitle("Clients")
            .searchable(text: $search, prompt: "Search name, company, tag")
            .toolbar {
                ToolbarItem(placement: .leading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if selection.isSelecting { selection.finish() } else { selection.isSelecting = true }
                    } label: {
                        Image(systemName: selection.isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .accessibilityLabel(selection.isSelecting ? "Stop selecting" : "Select clients")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add client")
                }
            }
            .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
            .navigationDestination(item: $linkedClient) { ClientDetailView(client: $0) }
            .onAppear(perform: consumeLink)
            .onChange(of: router.pendingLink) { _, _ in consumeLink() }
            .sheet(isPresented: $showingAdd) { ClientFormView() }
            .alert("Save filter", isPresented: $showingSave) {
                TextField("Name", text: $newFilterName)
                Button("Save") { saveCurrentFilter() }
                Button("Cancel", role: .cancel) { newFilterName = "" }
            } message: {
                Text("Give this combination of filters a name to reuse it.")
            }
            .alert("Add tag", isPresented: $showingBulkTag) {
                TextField("Tag", text: $bulkTag)
                Button("Add") {
                    let tag = bulkTag
                    bulkTag = ""
                    toast = context.performUndoable("Tagged \(selectedClients.count) clients", overwrite: true) {
                        BulkActions.addTag(tag, to: selectedClients)
                    }
                }
                Button("Cancel", role: .cancel) { bulkTag = "" }
            } message: {
                Text("Adds this tag to every selected client.")
            }
            .undoToast($toast)
            .sensoryFeedback(.selection, trigger: filter)
        }
    }

    // MARK: Selecting several clients

    private var selectedClients: [Client] { clients.filter { selection.selected.contains($0.id) } }

    /// What the Delete key acts on: the ticked rows, else the row under the cursor.
    private var keyboardTargets: [Client] {
        if !selection.selected.isEmpty { return selectedClients }
        return clients.filter { $0.id == selection.cursor }
    }

    private var bulkBar: some View {
        BulkBar(count: selection.count, done: { selection.finish() }) {
            Menu {
                Button { showingBulkTag = true } label: { Label("Add tag…", systemImage: "tag") }
                Menu("Set status") {
                    ForEach(ClientStatus.allCases) { status in
                        Button(status.label) {
                            toast = context.performUndoable("Updated \(selectedClients.count) clients", overwrite: true) {
                                BulkActions.setStatus(status, for: selectedClients)
                            }
                        }
                    }
                }
            } label: { Label("Update", systemImage: "ellipsis.circle") }
            Button(role: .destructive) {
                deleteClients(selectedClients)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func deleteClients(_ doomed: [Client]) {
        guard !doomed.isEmpty else { return }
        let message = doomed.count == 1 ? "Deleted client" : "Deleted \(doomed.count) clients"
        toast = context.deleteWithUndo(message, includeFiles: true) {
            for client in doomed { context.delete(client) }
        }
        selection.finish()
    }

    // MARK: Filter UI

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $filter.status) {
                Text("Any status").tag(ClientStatus?.none)
                ForEach(ClientStatus.allCases) { s in
                    Label(s.label, systemImage: s.systemImage).tag(ClientStatus?.some(s))
                }
            }
            Picker("Entity", selection: $filter.entityType) {
                Text("Any entity").tag(EntityType?.none)
                ForEach(EntityType.allCases) { e in
                    Text(e.label).tag(EntityType?.some(e))
                }
            }
            if !tagCounts.isEmpty {
                Picker("Tag", selection: $filter.tag) {
                    Text("Any tag").tag(String?.none)
                    ForEach(tagCounts, id: \.tag) { t in
                        Text("#\(t.tag) (\(t.count))").tag(String?.some(t.tag))
                    }
                }
            }
            Toggle("Only with open work", isOn: $filter.onlyWithOpenWork)
            if !filter.isEmpty {
                Divider()
                Button { showingSave = true } label: {
                    Label("Save this filter…", systemImage: "bookmark")
                }
                Button(role: .destructive) { filter = ClientFilter() } label: {
                    Label("Clear filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: filter.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter clients")
        .accessibilityValue(filter.isEmpty ? "No filters" : "\(filter.activeCount) active")
    }

    /// Saved filters first, then the most-used tags as one-tap chips.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", systemImage: "person.2.fill", isSelected: filter.isEmpty) {
                    filter = ClientFilter()
                }
                ForEach(savedFilters) { saved in
                    FilterChip(title: saved.name, systemImage: "bookmark.fill", isSelected: filter == saved.filter) {
                        filter = saved.filter
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            context.delete(saved)
                            try? context.save()
                        } label: { Label("Delete saved filter", systemImage: "trash") }
                    }
                }
                ForEach(tagCounts.prefix(8), id: \.tag) { t in
                    FilterChip(title: "#\(t.tag)", systemImage: "tag.fill", isSelected: filter.tag == t.tag) {
                        filter.tag = (filter.tag == t.tag) ? nil : t.tag
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: Actions

    private func consumeLink() {
        guard case .client(let id)? = router.pendingLink,
              let client = clients.first(where: { $0.id == id }) else { return }
        router.pendingLink = nil
        linkedClient = client
    }

    private func saveCurrentFilter() {
        let name = newFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFilterName = ""
        guard !name.isEmpty, !filter.isEmpty else { return }
        context.insert(SavedClientFilter(name: name, filter: filter))
        try? context.save()
    }

    private func delete(_ offsets: IndexSet) {
        let list = filtered
        deleteClients(offsets.map { list[$0] })
    }
}

/// Capsule filter chip: tinted when selected, icon + word always.
struct FilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Theme.brand)
                .background(isSelected ? Theme.brand : Theme.brand.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ClientRow: View {
    let client: Client
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var lastContact: Date? { client.lastContactedAt }
    private var isQuiet: Bool {
        client.status == .active
            && !client.openProjects.isEmpty
            && (ClientActivity.daysSince(lastContact ?? client.createdAt) ?? 0) >= 14
    }
    private var contactText: String { ClientActivity.lastContactLabel(lastContact) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            Avatar(initials: client.initials)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    EntityBadge(entityType: client.entityType)
                    if let stage = client.leadStage, stage.isOpen {
                        CapsuleBadge(text: stage.label, systemImage: stage.systemImage, state: stage.state)
                    }
                    let open = client.openProjects.count
                    if open > 0 {
                        Text("\(open) open")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Label(contactText, systemImage: isQuiet ? "exclamationmark.bubble.fill" : "clock")
                    .font(.caption.weight(isQuiet ? .semibold : .regular))
                    .foregroundStyle(isQuiet ? AnyShapeStyle(Theme.caution) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .lineLimit(1)
                if let due = client.followUpDate {
                    Label("Follow up \(Format.relativeDay(due).lowercased())", systemImage: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !client.tags.isEmpty {
                    Text(client.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                ClientStatusBadge(status: client.status)
            }
        }
        .rowCard(dimmed: client.status == .inactive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(client.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the client")
    }

    private var accessibilityValue: String {
        var parts = [client.status.label, client.entityType.label]
        let open = client.openProjects.count
        if open > 0 { parts.append("\(open) open projects") }
        parts.append(isQuiet ? "Needs contact, last contact \(contactText)" : "Last contact \(contactText)")
        if !client.tags.isEmpty { parts.append("Tags: " + client.tags.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
