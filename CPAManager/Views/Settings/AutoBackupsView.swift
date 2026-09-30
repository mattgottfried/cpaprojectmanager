import SwiftUI
import SwiftData

/// Automatic daily backups kept on this device, with restore and share.
struct AutoBackupsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.autoBackupEnabled) private var enabled = true

    @State private var backups: [AutoBackupInfo] = []
    @State private var message: String?
    @State private var pendingRestore: AutoBackupInfo?

    var body: some View {
        Form {
            Section {
                Toggle("Back up automatically", isOn: $enabled)
                Button { backUpNow() } label: { Label("Back up now", systemImage: "externaldrive.badge.plus") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text("A full backup is saved on this device about once a day (the last \(AutoBackupLogic.keep) are kept). They're the safety net if a sync ever goes wrong. Restoring adds back anything missing and never deletes or overwrites.")
            }

            Section("Saved backups") {
                if backups.isEmpty {
                    Text("None yet.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(backups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.date.formatted(date: .complete, time: .omitted))
                            Text(ByteCountFormatter.string(fromByteCount: Int64(backup.bytes), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: backup.url) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Share backup")
                        Button("Restore") { pendingRestore = backup }
                            .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            AutoBackupService.delete(backup.url)
                            reload()
                        } label: { Label("Delete Backup", systemImage: "trash") }
                    }
                }
            }
        }
        .macReadableWidth(760)
        .navigationTitle("Automatic Backups")
        .onAppear(perform: reload)
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { backup in
            Button("Add back what's missing") { restore(backup) }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("From \(backup.date.formatted(date: .long, time: .omitted)). Existing records aren't changed or deleted.")
        }
    }

    private func reload() { backups = AutoBackupService.list() }

    private func backUpNow() {
        do {
            try AutoBackupService.backupNow(context: context)
            message = "Backup saved."
        } catch {
            message = "Couldn't save the backup: \(error.localizedDescription)"
        }
        reload()
    }

    private func restore(_ backup: AutoBackupInfo) {
        do {
            let result = try AutoBackupService.restore(backup.url, into: context)
            try? context.save()
            message = result.inserted == 0 ? "Nothing was missing." : "Added back \(result.inserted) record\(result.inserted == 1 ? "" : "s")."
        } catch {
            message = "Couldn't read that backup: \(error.localizedDescription)"
        }
    }
}
