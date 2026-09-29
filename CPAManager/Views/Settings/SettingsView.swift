import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncStatus.self) private var syncStatus
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.firmTagline) private var firmTagline = ""
    @AppStorage(SettingsKeys.firmContact) private var firmContact = ""
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage(SettingsKeys.quietThresholdDays) private var quietDays = 14
    @AppStorage(SettingsKeys.focusEnabled) private var focusEnabled = false
    @AppStorage(SettingsKeys.focusStartHour) private var focusStart = 18
    @AppStorage(SettingsKeys.focusEndHour) private var focusEnd = 22
    @AppStorage(SettingsKeys.focusWeekends) private var focusWeekends = true

    @State private var showingRestoreConfirm = false
    @State private var restoreMessage: String?
    @State private var showingRemindersImport = false

    /// Changes whenever any side-business-hours setting does, so reminders re-time.
    private var focusSignature: String {
        "\(focusEnabled)-\(focusStart)-\(focusEnd)-\(focusWeekends)"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                TextField("Firm name", text: $firmName)
                TextField("Tagline (e.g. \"Certified Public Accountants  •  Ocoee, FL\")", text: $firmTagline)
                TextField("Contact (e.g. \"you@example.com  •  555-555-0100\")", text: $firmContact)
            } header: {
                Text("Firm")
            } footer: {
                Text("Shown on printed routing sheets and invoices.")
            }

            Section("Billing") {
                LabeledContent("Default hourly rate") {
                    TextField("Rate", value: $defaultHourlyRate, format: .currency(code: "USD"))
                        .multilineTextAlignment(.trailing)
                        .decimalKeyboard()
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
                Stepper("Nudge after \(quietDays) days", value: $quietDays, in: 3...90)
            } header: {
                Text("Client Check-Ins")
            } footer: {
                Text("Active clients with open work show as \"Gone quiet\" on Today when you haven't logged contact in this long — unless you've set a follow-up reminder for later.")
            }

            Section {
                Toggle("Only nudge me during my side-business hours", isOn: $focusEnabled)
                if focusEnabled {
                    Picker("Starts", selection: $focusStart) {
                        ForEach(0..<24, id: \.self) { Text(FocusHours.hourLabel($0)).tag($0) }
                    }
                    Picker("Ends", selection: $focusEnd) {
                        ForEach(0..<24, id: \.self) { Text(FocusHours.hourLabel($0)).tag($0) }
                    }
                    Toggle("Weekends all day", isOn: $focusWeekends)
                }
            } header: {
                Text("Side-Business Hours")
            } footer: {
                Text("Due-date reminders move to when your window opens on weekdays (and to the reminder time above on weekends, if \"Weekends all day\" is on). Today also tells you when it's off hours.")
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
                    GoogleSettingsView()
                } label: {
                    Label("Google (Gmail & Calendar)", systemImage: "g.circle.fill")
                }
                NavigationLink {
                    QBOSettingsView()
                } label: {
                    Label("QuickBooks Online", systemImage: "building.columns.fill")
                }
            } header: {
                Text("Integrations")
            } footer: {
                Text("Google brings starred emails into your Inbox and puts your schedule and due dates on Today and your calendar. QuickBooks pushes invoices and pulls payments.")
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
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Button {
                            Clipboard.string = error
                        } label: {
                            Label("Copy error", systemImage: "doc.on.doc")
                        }
                        .font(.caption)
                    }
                }
                LabeledContent("iCloud account", value: syncStatus.accountStatusDescription)
                LabeledContent("Settings sync", value: SettingsSync.isAvailable ? "On" : "Sign into iCloud")
                    .font(.caption)
                LabeledContent("Container", value: SyncStatus.containerIdentifier)
                    .font(.caption)

                if syncStatus.isCloudKitActive {
                    Button {
                        syncStatus.syncNow(context: context)
                    } label: {
                        if syncStatus.isSyncing {
                            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(syncStatus.isSyncing)

                    LabeledContent("Last sent to iCloud") {
                        syncEventValue(date: syncStatus.lastExportDate, error: syncStatus.lastExportError)
                    }
                    LabeledContent("Last received from iCloud") {
                        syncEventValue(date: syncStatus.lastImportDate, error: syncStatus.lastImportError)
                    }
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Sign into the same iCloud account on each device to sync. If this shows \"Local Only\" on any device, that device's data stays on-device until it's resolved — see the README's sync troubleshooting section. Your settings sync through iCloud too, and Google / QuickBooks connections sync through iCloud Keychain (System Settings → Apple ID → iCloud → Passwords & Keychain) — connect once and the other devices pick it up. iOS syncs with iCloud automatically in the background; \"Sync Now\" just saves any pending changes and checks your account status right away rather than waiting.")
            }

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .inlineNavigationTitle()
        .onChange(of: focusSignature) { _, _ in
            NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        }
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

    @ViewBuilder
    private func syncEventValue(date: Date?, error: String?) -> some View {
        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let date {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        } else {
            Text("Not yet")
                .foregroundStyle(.secondary)
        }
    }
}
