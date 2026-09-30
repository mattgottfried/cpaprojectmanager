import SwiftUI
import SwiftData

/// Who needs an extension, who has one, and who's done — for one tax year. Marking a client
/// extended moves their open return to the extended due date and logs it.
struct ExtensionTrackerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Pipeline.sortIndex) private var pipelines: [Pipeline]
    @State private var taxYear = Calendar.current.component(.year, from: .now) - 1
    @State private var toast: UndoToastState?

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    private var rows: [ExtensionRow] {
        ExtensionTracker.rows(ExtensionService.inputs(clients: clients, taxYear: taxYear, pipelines: pipelines), taxYear: taxYear)
    }

    var body: some View {
        let all = rows
        List {
            Section {
                Picker("Tax year", selection: $taxYear) {
                    ForEach((currentYear - 3)...currentYear, id: \.self) { Text(String($0)).tag($0) }
                }
            } footer: {
                Text("Calendar-year federal dates. An extension gives more time to file, not to pay — confirm any balance due was paid by the original date.")
            }
            .cardListRow()

            if all.isEmpty {
                ContentUnavailableView("No clients to track", systemImage: "calendar.badge.clock",
                                       description: Text("Active clients with a federal return type show up here."))
                    .cardListRow()
            }

            group("Needs a decision", state: .needsDecision, in: all)
            group("Extended", state: .extended, in: all)
            group("Return finished", state: .done, in: all)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .undoToast($toast)
        .navigationTitle("Extensions")
    }

    @ViewBuilder
    private func group(_ title: String, state: ExtensionState, in all: [ExtensionRow]) -> some View {
        let subset = all.filter { $0.state == state }
        if !subset.isEmpty {
            Section {
                ForEach(subset) { row in
                    rowView(row)
                        .cardListRow()
                }
            } header: {
                Text("\(title) (\(subset.count))").font(.headline).textCase(nil)
            }
        }
    }

    private func rowView(_ row: ExtensionRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.formLabel)
                    if let stage = row.returnStageLabel { Text("·"); Text(stage) }
                }
                .font(.caption).foregroundStyle(.secondary)
                dates(row)
            }
            Spacer(minLength: 8)
            switch row.state {
            case .needsDecision:
                Button("Mark extended") { markExtended(row) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            case .extended:
                CapsuleBadge(text: "Extended", systemImage: "calendar.badge.clock", state: .caution)
            case .done:
                CapsuleBadge(text: "Done", systemImage: "checkmark", state: .good)
            }
        }
        .rowCard(dimmed: row.state == .done)
        .contextMenu {
            if row.state == .extended {
                Button { clear(row) } label: { Label("Remove extension", systemImage: "arrow.uturn.backward") }
            } else if row.state == .needsDecision {
                Button { markExtended(row) } label: { Label("Mark extended", systemImage: "calendar.badge.clock") }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func dates(_ row: ExtensionRow) -> some View {
        switch row.state {
        case .extended:
            Label("Extended due \(row.extendedDue.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                .font(.caption).foregroundStyle(Theme.color(.caution))
        case .needsDecision:
            let urgency = ExtensionTracker.urgency(for: row)
            Label("Due \(row.originalDue.formatted(date: .abbreviated, time: .omitted))" + (urgency.map { " · \($0)" } ?? ""),
                  systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(row.daysToOriginal < 0 ? Theme.color(.bad) : Theme.color(.info))
        case .done:
            EmptyView()
        }
    }

    private func client(_ row: ExtensionRow) -> Client? { clients.first { $0.id == row.id } }

    private func markExtended(_ row: ExtensionRow) {
        guard let client = client(row) else { return }
        toast = context.performUndoable("Extended \(row.name)", systemImage: "calendar.badge.clock", overwrite: true) {
            ExtensionService.markExtended(client, taxYear: taxYear, context: context)
        }
    }

    private func clear(_ row: ExtensionRow) {
        guard let client = client(row) else { return }
        toast = context.performUndoable("Removed extension for \(row.name)", systemImage: "arrow.uturn.backward", overwrite: true) {
            ExtensionService.clearExtension(client, taxYear: taxYear, context: context)
        }
    }
}
