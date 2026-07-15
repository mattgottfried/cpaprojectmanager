import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncStatus.self) private var syncStatus
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @State private var showingRestoreConfirm = false
    @State private var restoreMessage: String?
    @State private var showingRemindersImport = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Firm") {
                TextField("Firm name", text: $firmName)
            }

            Section("Billing") {
                LabeledContent("Default hourly rate") {
                    TextField("Rate", value: $defaultHourlyRate, format: .currency(code: "USD"))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
            }

            Section {
                Stepper("Remind at \(reminderHour):00", value: $reminderHour, in: 0...23)
                Button("Reschedule reminders now") {
                    NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("Local notifications fire on the morning a project or task is due.")
            }

            Section {
                Button {
                    showingRemindersImport = true
                } label: {
                    Label("Import from Apple Reminders", systemImage: "list.bullet.clipboard")
                }
            } header: {
                Text("Data Import")
            } footer: {
                Text("One-time migration of your existing Reminders-based workflow. Shows a preview before creating anything; Reminders itself is never changed.")
            }

            Section {
                NavigationLink {
                    QBOSettingsView()
                } label: {
                    Label("QuickBooks Online", systemImage: "building.columns.fill")
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Connect to push invoices directly into QuickBooks Online.")
            }

            Section {
                Button {
                    showingRestoreConfirm = true
                } label: {
                    Label("Restore default templates", systemImage: "arrow.counterclockwise")
                }
                if let restoreMessage {
                    Text(restoreMessage).font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Adds the built-in engagement templates back. Your existing templates are kept.")
            }

            Section {
                if syncStatus.isCloudKitActive {
                    Label("Active — syncing via iCloud", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Local Only — not syncing", systemImage: "exclamationmark.icloud.fill")
                        .foregroundStyle(.red)
                    if let error = syncStatus.containerError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("iCloud account", value: syncStatus.accountStatusDescription)
                LabeledContent("Container", value: SyncStatus.containerIdentifier)
                    .font(.caption)
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Sign into the same iCloud account on each device to sync. If this shows \"Local Only\" on any device, that device's data stays on-device until it's resolved — see the README's sync troubleshooting section.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Restore the built-in templates?",
            isPresented: $showingRestoreConfirm,
            titleVisibility: .visible
        ) {
            Button("Restore templates") {
                SeedData.restoreDefaultTemplates(context: context)
                restoreMessage = "Default templates restored."
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingRemindersImport) { RemindersImportView() }
    }
}
