import SwiftUI
import SwiftData

/// First-run walkthrough: what the app does, your firm details, reminders, sample data.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Replays from Help: shows the pages but doesn't touch your data or settings again.
    var replay = false

    @AppStorage(SettingsKeys.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.defaultHourlyRate) private var hourlyRate = 150.0
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @State private var page = 0
    @State private var keepSamples = true
    @State private var notificationsAsked = false

    private let lastPage = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                firmPage.tag(1)
                capturePage.tag(2)
                remindersPage.tag(3)
                startPage.tag(4)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            HStack {
                if page > 0 {
                    Button("Back") { withAnimation { page -= 1 } }
                }
                Spacer()
                if page < lastPage {
                    Button("Skip") { finish() }.foregroundStyle(.secondary)
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get started") { finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 380, minHeight: 520)
        .interactiveDismissDisabled(!replay)
    }

    // MARK: Pages

    private func pageContent(_ image: String, _ title: String, _ message: String) -> some View {
        pageContent(image, title, message) { EmptyView() }
    }

    private func pageContent<Extra: View>(_ image: String, _ title: String, _ message: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Image(systemName: image)
                .font(.system(size: 56))
                .foregroundStyle(Theme.brand)
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            extra()
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var welcomePage: some View {
        pageContent(
            "checkmark.circle.fill",
            "Never lose track of what you owe",
            "One place for clients, jobs and the daily to-do list for your practice. Today shows what matters; the Inbox catches everything else."
        )
    }

    private var firmPage: some View {
        pageContent("building.2.fill", "Your practice", "Used on invoices, letters and routing sheets. You can change these any time in Settings.") {
            VStack(spacing: 12) {
                TextField("Firm name", text: $firmName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Hourly rate")
                    Spacer()
                    TextField("Rate", value: $hourlyRate, format: .currency(code: "USD"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                        .decimalKeyboard()
                }
            }
        }
    }

    private var capturePage: some View {
        pageContent(
            "tray.and.arrow.down.fill",
            "Capture without thinking",
            "Texts, emails and stray thoughts land in the Inbox. Use Siri or the Action button, the Share Sheet, or paste from a note — then decide later. Find the setup steps under Today ▸ Capture options."
        )
    }

    private var remindersPage: some View {
        pageContent("bell.badge.fill", "Reminders", "Due dates and follow-ups can notify you each morning.") {
            VStack(spacing: 12) {
                Stepper("Remind at \(reminderHour):00", value: $reminderHour, in: 0...23)
                Button {
                    notificationsAsked = true
                    Task { _ = await NotificationScheduler.requestAuthorization() }
                } label: {
                    Label(notificationsAsked ? "Requested" : "Allow notifications", systemImage: "bell")
                }
                .buttonStyle(.bordered)
                .disabled(notificationsAsked)
            }
        }
    }

    private var startPage: some View {
        pageContent("sparkles", "You're set", "Sample clients are included so you can explore. Help & Tips (More tab) explains every feature.") {
            if !replay {
                Toggle("Keep the sample clients", isOn: $keepSamples)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Finish

    private func finish() {
        if !replay {
            hasOnboarded = true
            if !keepSamples { SeedData.removeSampleClients(context: context) }
            NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        }
        dismiss()
    }
}
