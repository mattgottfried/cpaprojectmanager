import SwiftUI
import SwiftData

/// How sync is doing, what's on this device, and a tool to merge look-alike clients.
struct SyncHealthView: View {
    @Environment(CloudSync.self) private var cloud
    @Environment(\.modelContext) private var context
    @Query private var clients: [Client]

    private struct CountRow: Identifiable {
        let label: String
        let count: Int
        var id: String { label }
    }

    @State private var counts: [CountRow] = []
    @State private var toast: UndoToastState?

    private var report: SyncHealthReport {
        let engine = cloud.engine
        return SyncHealth.assess(SyncHealthInput(
            isSignedIn: cloud.availability == .signedIn,
            phase: engine?.phase ?? .stopped,
            pendingUploads: engine?.pendingUploads ?? 0,
            deferredCount: engine?.deferredCount ?? 0,
            blockedDeletions: engine?.blockedDeletionCount ?? 0,
            oversizedFiles: engine?.oversizedFileCount ?? 0,
            lastPush: engine?.lastPushDate,
            lastPull: engine?.lastPullDate
        ))
    }

    private var duplicateGroups: [DupGroup] {
        DuplicateClients.groups(clients.map {
            DupClientInput(
                id: $0.id, name: $0.name, company: $0.company, email: $0.email, createdAt: $0.createdAt,
                recordCount: $0.projectList.count + $0.invoiceList.count + $0.interactionList.count + ($0.documents ?? []).count
            )
        })
    }

    var body: some View {
        let report = report
        Form {
            Section {
                HStack {
                    CapsuleBadge(text: report.headline, systemImage: icon(report.level), state: state(report.level))
                    Spacer()
                }
                ForEach(report.issues, id: \.self) { issue in
                    Text(issue).font(.footnote).foregroundStyle(.secondary)
                }
                if let engine = cloud.engine {
                    LabeledContent("Last sent") { date(engine.lastPushDate) }
                    LabeledContent("Last received") { date(engine.lastPullDate) }
                    if engine.pendingUploads > 0 { LabeledContent("Waiting to upload", value: "\(engine.pendingUploads)") }
                }
                Button { cloud.syncNow() } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(cloud.availability != .signedIn)
            } header: {
                Text("Status")
            }

            duplicatesSection

            Section {
                ForEach(counts) { row in
                    LabeledContent(row.label, value: "\(row.count)")
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("Compare these counts between your devices; they should match once sync is up to date.")
            }
        }
        .macReadableWidth(760)
        .navigationTitle("Sync Health")
        .undoToast($toast)
        .onAppear(perform: loadCounts)
    }

    @ViewBuilder
    private var duplicatesSection: some View {
        let groups = duplicateGroups
        Section {
            if groups.isEmpty {
                Label("No duplicate clients found", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.color(.good))
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(name(of: group.keeper)).font(.body.weight(.medium))
                    Text("\(group.others.count) look-alike\(group.others.count == 1 ? "" : "s") · \(group.reason)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Merge into \(name(of: group.keeper))") { merge(group) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Duplicate clients")
        } footer: {
            Text("Merging moves everything (jobs, invoices, documents, notes, contact log) onto the client with the most records and removes the extra. You can undo right after.")
        }
    }

    private func name(of id: UUID) -> String {
        clients.first { $0.id == id }?.displayName ?? "Client"
    }

    private func merge(_ group: DupGroup) {
        guard let keeper = clients.first(where: { $0.id == group.keeper }) else { return }
        let others = clients.filter { group.others.contains($0.id) }
        toast = context.performUndoable("Merged \(others.count + 1) clients", systemImage: "arrow.triangle.merge", overwrite: true) {
            ClientMergeService.merge(others, into: keeper, context: context)
        }
    }

    private func loadCounts() {
        counts = BackupService.export(context: context, includeFiles: false).summary.map { CountRow(label: $0.label, count: $0.count) }
    }

    @ViewBuilder
    private func date(_ value: Date?) -> some View {
        if let value {
            Text(value.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
        } else {
            Text("Not yet").foregroundStyle(.secondary)
        }
    }

    private func state(_ level: SyncHealthReport.Level) -> SemanticState {
        switch level {
        case .good:    return .good
        case .watch:   return .caution
        case .problem: return .bad
        }
    }

    private func icon(_ level: SyncHealthReport.Level) -> String {
        switch level {
        case .good:    return "checkmark.icloud.fill"
        case .watch:   return "exclamationmark.icloud.fill"
        case .problem: return "xmark.icloud.fill"
        }
    }
}
