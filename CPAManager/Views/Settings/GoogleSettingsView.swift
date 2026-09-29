import SwiftUI
import SwiftData

/// Connects Google Workspace: starred emails → Inbox, today's schedule on Today, and
/// due dates pushed to a calendar. The user supplies their own OAuth client ID
/// (README has the Google Cloud walkthrough); tokens live only in the Keychain.
struct GoogleSettingsView: View {
    @Environment(GoogleAuthService.self) private var auth
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKeys.googleGmailEnabled) private var gmailEnabled = false
    @AppStorage(SettingsKeys.googleGmailQuery) private var gmailQuery = ""
    @AppStorage(SettingsKeys.googleScheduleEnabled) private var scheduleEnabled = false
    @AppStorage(SettingsKeys.googlePushEnabled) private var pushEnabled = false
    @AppStorage(SettingsKeys.googleCalendarID) private var calendarID = "primary"
    @AppStorage(SettingsKeys.googleLastGmailSync) private var lastGmailSync: Double = 0

    @State private var clientIDText = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var calendars: [GoogleCalendarListResponse.Entry] = []
    @State private var busy = false

    var body: some View {
        Form {
            connectionSection

            if auth.isConnected {
                gmailSection
                scheduleSection
                pushSection
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
            }
            if let statusMessage {
                Section { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Google")
        .onAppear { clientIDText = auth.clientID }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section {
            if auth.isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                Button("Disconnect", role: .destructive) {
                    Task {
                        if pushEnabled { await GoogleSync.removeAllPushedEvents(auth: auth) }
                        auth.disconnect()
                        gmailEnabled = false; scheduleEnabled = false; pushEnabled = false
                    }
                }
            } else {
                Label("Not connected", systemImage: "xmark.circle").foregroundStyle(.secondary)
            }

            TextField("OAuth client ID", text: $clientIDText)
                .emailFieldTraits()
                .onChange(of: clientIDText) { _, value in auth.clientID = value }

            Button {
                Task { await connect() }
            } label: {
                if isConnecting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(auth.isConnected ? "Reconnect to Google" : "Connect to Google")
                }
            }
            .disabled(isConnecting || clientIDText.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("Account")
        } footer: {
            Text("Create an iOS-type OAuth client in your own Google Cloud project (bundle ID com.gottfriedcpa.ProjectManager), enable the Gmail and Calendar APIs, and paste its client ID here. On Google Workspace, set the consent screen to Internal — no review needed. See the README for the step-by-step.")
        }
    }

    private var gmailSection: some View {
        Section {
            Toggle("Send emails to my Inbox", isOn: $gmailEnabled)
            if gmailEnabled {
                TextField("Gmail search", text: $gmailQuery, prompt: Text(GmailParsing.defaultQuery))
                    .emailFieldTraits()
                Button {
                    Task { await syncGmail() }
                } label: {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
                if lastGmailSync > 0 {
                    LabeledContent("Last sync", value: Date(timeIntervalSince1970: lastGmailSync).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
            }
        } header: {
            Text("Gmail")
        } footer: {
            Text("Star an email in Gmail and it lands in your Inbox here (read-only — the app never changes your mail). Use any Gmail search, e.g. \"label:cpa-todo\" or \"is:starred newer_than:14d\".")
        }
    }

    private var scheduleSection: some View {
        Section {
            Toggle("Show today's events on Today", isOn: $scheduleEnabled)
        } header: {
            Text("Schedule")
        } footer: {
            Text("Read-only view of today's events from your primary calendar.")
        }
    }

    private var pushSection: some View {
        Section {
            Toggle("Put due dates on my calendar", isOn: $pushEnabled)
                .onChange(of: pushEnabled) { _, on in
                    Task {
                        if on { await pushNow() } else { await GoogleSync.removeAllPushedEvents(auth: auth) }
                    }
                }
            if pushEnabled {
                Picker("Calendar", selection: $calendarID) {
                    Text("Primary").tag("primary")
                    ForEach(calendars.filter { $0.primary != true }, id: \.id) { entry in
                        Text(entry.summary ?? entry.id).tag(entry.id)
                    }
                }
                .task { await loadCalendars() }
                Button {
                    Task { await pushNow(force: true) }
                } label: {
                    Label("Sync due dates now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(busy)
            }
        } header: {
            Text("Due dates")
        } footer: {
            Text("Adds open tasks, project deadlines, unpaid invoices, and follow-ups from the next 90 days as all-day events that don't block your time. Only events this app created are ever changed or removed. Switching calendars applies to future syncs.")
        }
    }

    // MARK: Actions

    private func connect() async {
        errorMessage = nil
        statusMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            auth.clientID = clientIDText
            try await auth.connect()
        } catch GoogleError.cancelled {
            // User closed the sheet — not an error worth showing.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncGmail() async {
        busy = true
        defer { busy = false }
        let result = await GoogleSync.syncGmail(auth: auth, context: context, force: true)
        errorMessage = result.error
        statusMessage = result.error == nil
            ? (result.added == 0 ? "Nothing new in Gmail." : "Added \(result.added) email\(result.added == 1 ? "" : "s") to your Inbox.")
            : nil
    }

    private func pushNow(force: Bool = false) async {
        busy = true
        defer { busy = false }
        let result = await GoogleSync.pushDueDates(auth: auth, context: context, force: true)
        errorMessage = result.error
        if result.error == nil {
            statusMessage = "Calendar synced — \(result.created) added, \(result.updated) updated, \(result.deleted) removed."
        }
    }

    private func loadCalendars() async {
        calendars = (try? await GoogleAPI(auth: auth).calendarList()) ?? []
    }
}
