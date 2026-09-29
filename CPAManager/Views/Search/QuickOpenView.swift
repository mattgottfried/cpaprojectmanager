import SwiftUI
import SwiftData

/// ⌘K: one box to jump to a client, project, task, invoice, or inbox item — or run a
/// command ("Go to Inbox", "New task"). Arrow keys move, Return opens.
struct QuickOpenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @Query private var clients: [Client]
    @Query private var projects: [Project]
    @Query private var tasks: [TaskItem]
    @Query private var invoices: [Invoice]
    @Query private var expenses: [Expense]
    @Query private var interactions: [Interaction]
    @Query(filter: #Predicate<InboxItem> { $0.isProcessed == false }) private var inbox: [InboxItem]

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private struct Command: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let run: (AppRouter) -> Void
    }

    private enum Row: Identifiable {
        case hit(SearchHit)
        case command(Command)

        var id: String {
            switch self {
            case .hit(let hit):      return "hit-" + hit.id
            case .command(let cmd):  return "cmd-" + cmd.id
            }
        }
    }

    // MARK: Data

    private var docs: [SearchDoc] {
        SearchIndexBuilder.docs(
            clients: clients, projects: projects, tasks: tasks, invoices: invoices,
            inbox: inbox, expenses: expenses, interactions: interactions
        )
    }

    private var commands: [Command] {
        var list: [Command] = [
            Command(id: "new-task", title: "New task", systemImage: "plus.circle") { $0.go(to: .today, focus: .newTask) },
            Command(id: "capture", title: "Capture to Inbox", systemImage: "tray.and.arrow.down") { $0.go(to: .inbox, focus: .inboxCapture) },
        ]
        for section in AppSection.allCases {
            list.append(Command(id: "go-\(section.rawValue)", title: "Go to \(section.title)", systemImage: section.systemImage) { $0.go(to: section) })
        }
        return list
    }

    private var rows: [Row] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return commands.prefix(8).map { Row.command($0) } }
        let hits = GlobalSearch.search(docs, query: trimmed, limit: 25).map { Row.hit($0) }
        let normalized = GlobalSearch.normalize(trimmed)
        let matchingCommands = commands
            .filter { GlobalSearch.normalize($0.title).contains(normalized) }
            .prefix(4)
            .map { Row.command($0) }
        return hits + matchingCommands
    }

    // MARK: View

    var body: some View {
        let current = rows
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clients, work, tasks, invoices… or type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { open(at: selection, in: current) }
                    .onChange(of: query) { _, _ in selection = 0 }
                    .accessibilityLabel("Search")
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .font(.caption)
            }
            .padding(14)

            Divider()

            if current.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollViewReader { proxy in
                    List(Array(current.enumerated()), id: \.element.id) { index, row in
                        rowView(row, selected: index == selection)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { open(at: index, in: current) }
                            .listRowBackground(index == selection ? Theme.brand.opacity(0.12) : Color.clear)
                    }
                    .listStyle(.plain)
                    .onChange(of: selection) { _, new in
                        if current.indices.contains(new) { proxy.scrollTo(current[new].id) }
                    }
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 560, minHeight: 360)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(0, current.count - 1))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func rowView(_ row: Row, selected: Bool) -> some View {
        switch row {
        case .hit(let hit):
            HStack(spacing: 12) {
                StatusTile(systemImage: hit.doc.kind.systemImage, state: .info, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.doc.title).lineLimit(1)
                    if !hit.doc.subtitle.isEmpty {
                        Text(hit.doc.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text(hit.doc.kind.label).font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        case .command(let command):
            HStack(spacing: 12) {
                StatusTile(systemImage: command.systemImage, state: .neutral, size: 34)
                Text(command.title)
                Spacer(minLength: 0)
                Text("Command").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private func open(at index: Int, in rows: [Row]) {
        guard rows.indices.contains(index) else { return }
        switch rows[index] {
        case .command(let command):
            dismiss()
            command.run(router)
        case .hit(let hit):
            dismiss()
            let doc = hit.doc
            if let link = DeepLink(identifier: doc.target ?? doc.id) {
                router.open(link)
            } else if doc.kind == .inbox {
                router.go(to: .inbox)
            } else if doc.kind == .expense {
                router.go(to: .expenses)
            }
        }
    }
}
