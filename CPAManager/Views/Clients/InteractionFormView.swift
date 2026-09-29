import SwiftUI
import SwiftData

/// Log (or edit) a call, email, text, meeting, or note on a client.
struct InteractionFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let client: Client
    var interaction: Interaction?
    var initialKind: InteractionKind = .call

    @State private var kind: InteractionKind = .call
    @State private var summary = ""
    @State private var occurredAt = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(InteractionKind.allCases) { k in
                            Label(k.label, systemImage: k.systemImage).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                    DatePicker("When", selection: $occurredAt, in: ...Date.now)
                }
                Section("What was said or decided") {
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(interaction == nil ? "Log \(kind.label)" : "Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let interaction {
                    kind = interaction.kind
                    summary = interaction.summary
                    occurredAt = interaction.occurredAt
                } else {
                    kind = initialKind
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let interaction {
            interaction.kind = kind
            interaction.summary = text
            interaction.occurredAt = occurredAt
        } else {
            context.insert(Interaction(kind: kind, summary: text, occurredAt: occurredAt, client: client))
        }
        try? context.save()
        dismiss()
    }
}

/// A single timeline row.
struct InteractionRow: View {
    let interaction: Interaction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusTile(systemImage: interaction.kind.systemImage, state: .info, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(interaction.summary)
                    .font(.subheadline)
                    .lineLimit(4)
                Text("\(interaction.kind.label) • \(interaction.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(interaction.summary)
        .accessibilityValue("\(interaction.kind.label), \(interaction.occurredAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

/// Full history for one client.
struct InteractionHistoryView: View {
    let client: Client
    @Environment(\.modelContext) private var context

    private var entries: [Interaction] {
        client.interactionList.sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        List {
            ForEach(entries) { entry in
                InteractionRow(interaction: entry)
            }
            .onDelete { offsets in
                let list = entries
                for index in offsets { context.delete(list[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Activity")
        .overlay {
            if entries.isEmpty {
                EmptyStateView(title: "No activity", message: "Log calls, emails, texts and meetings to see them here.", systemImage: "clock")
            }
        }
    }
}
