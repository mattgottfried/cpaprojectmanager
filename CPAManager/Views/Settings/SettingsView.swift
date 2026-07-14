import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @State private var showingRestoreConfirm = false
    @State private var restoreMessage: String?

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
                Label("Syncs across your devices via iCloud", systemImage: "icloud.fill")
                    .foregroundStyle(Theme.brand)
                Text("Sign into the same iCloud account on each device. Your data is stored privately in your iCloud — no third-party server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Sync")
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
    }
}
