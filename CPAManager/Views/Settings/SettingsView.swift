import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.firmTagline) private var firmTagline = ""
    @AppStorage(SettingsKeys.firmContact) private var firmContact = ""
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @AppStorage(SettingsKeys.taxSeasonMode) private var taxSeasonMode = TaxSeasonMode.auto.rawValue
    @AppStorage(SettingsKeys.uploadPageURL) private var uploadPageURL = ""
    @AppStorage(SettingsKeys.signatureChaseDays) private var signatureChaseDays = 3
    @AppStorage(SettingsKeys.timeRoundingMinutes) private var roundingMinutes = 0
    @AppStorage(SettingsKeys.timerReminderHours) private var timerReminderHours = 0
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
                SettingsField("Firm name", prompt: "Your firm", text: $firmName)
                SettingsField("Tagline", prompt: "Certified Public Accountants  •  Ocoee, FL", text: $firmTagline)
                SettingsField("Contact", prompt: "you@example.com  •  555-555-0100", text: $firmContact)
            } header: {
                Text("Firm")
            } footer: {
                Text("Shown on printed routing sheets and invoices.")
            }

            Section {
                Picker("Tax-season card on Today", selection: $taxSeasonMode) {
                    ForEach(TaxSeasonMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } footer: {
                Text("Shows days to the deadline, open returns by stage, and what's still outstanding.")
            }

            Section {
                SettingsField("Upload page", prompt: "https://www.encyro.com/yourfirm", text: $uploadPageURL)
                    .urlKeyboard()
                    .noAutocapitalization()
                if !uploadPageURL.isEmpty && UploadLink.normalized(uploadPageURL).isEmpty {
                    Label("That doesn't look like a web address.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.color(.caution))
                }
                Stepper("Nudge after \(signatureChaseDays) day\(signatureChaseDays == 1 ? "" : "s") unsigned", value: $signatureChaseDays, in: 1...30)
            } header: {
                Text("Client uploads & signatures")
            } footer: {
                Text("Your secure upload page is added to document-request emails and the {uploadlink} template field. Letters you send for signature show on Today if they stay unsigned.")
            }

            Section("Billing") {
                LabeledContent("Default hourly rate") {
                    TextField("Rate", value: $defaultHourlyRate, format: .currency(code: "USD"))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 160)
                        .decimalKeyboard()
                }
                Picker("Round billed time up to", selection: $roundingMinutes) {
                    ForEach(TimeRounding.options, id: \.self) { Text(TimeRounding.label($0)).tag($0) }
                }
                Picker("Warn if a timer runs longer than", selection: $timerReminderHours) {
                    ForEach(TimerReminderPlan.hourOptions, id: \.self) { Text($0 == 0 ? "Never" : "\($0) hr").tag($0) }
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
                    ExportBackupView()
                } label: {
                    Label("Export & Backup", systemImage: "square.and.arrow.up.on.square")
                }
                NavigationLink {
                    AutoBackupsView()
                } label: {
                    Label("Automatic Backups", systemImage: "externaldrive.fill.badge.timemachine")
                }
                NavigationLink {
                    SyncHealthView()
                } label: {
                    Label("Sync Health", systemImage: "arrow.triangle.2.circlepath.icloud")
                }
            } header: {
                Text("Your Data")
            } footer: {
                Text("CSV spreadsheets for your accountant or your own books, and a full backup you control.")
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

            CloudSyncSection()

            Section {
                LabeledContent("Version", value: appVersion)
            }
        }
        .macReadableWidth(760)
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

}

/// A labelled text field that reads the same in Mac's grouped form and on iPhone: the label
/// on the left, the value on the right, an example as the placeholder.
private struct SettingsField: View {
    let label: String
    let prompt: String
    @Binding var text: String

    init(_ label: String, prompt: String, text: Binding<String>) {
        self.label = label
        self.prompt = prompt
        _text = text
    }

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
    }
}
