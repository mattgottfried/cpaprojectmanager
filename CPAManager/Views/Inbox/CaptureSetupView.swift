import SwiftUI

/// How to get texts and email into the inbox. Apps can't read Messages or Notes
/// directly on iOS/macOS, so capture flows through Shortcuts and the share sheet.
struct CaptureSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Apple doesn't let any app read your Messages, Notes, or Mail directly. Instead, a Shortcut hands the text to CPA Manager. You set it up once; after that it runs on its own.")
                        .font(.subheadline)
                }

                Section {
                    step(1, "Open the Shortcuts app → Automation → New Automation → Time of Day (e.g. 8:00 AM and 6:00 PM, Run Immediately).")
                    step(2, "Add the action Find Notes, filtered to the note your Siri-digested texts land in.")
                    step(3, "Add Get Text from Note (or Get Details of Notes → Body).")
                    step(4, "Add CPA Manager → Add to Inbox. Set Text to the note text and Source to Note.")
                } header: {
                    Label("Texts (from your Siri note)", systemImage: "message.fill")
                } footer: {
                    Text("Each line becomes an inbox item. Lines already captured are skipped, so it's safe to re-run on the same note.")
                }

                Section {
                    step(1, "In Shortcuts, create a new shortcut and turn on Show in Share Sheet (accept Text / Email).")
                    step(2, "Add CPA Manager → Add to Inbox with Text = Shortcut Input, Source = Email, and turn off One item per line.")
                    step(3, "In Mail or Outlook, open an email → Share → your shortcut.")
                } header: {
                    Label("Email", systemImage: "envelope.fill")
                } footer: {
                    Text("Works the same on Mac: Shortcuts appear in Mail's Share menu.")
                }

                Section {
                    Text("Say “Add a task in CPA Manager” and then dictate — dates like “tomorrow” or “Friday” are picked up automatically.")
                        .font(.subheadline)
                } header: {
                    Label("Siri", systemImage: "waveform")
                }

                Section {
                    Text("Hands-free capture from Outlook without a Shortcut would need a direct Microsoft account connection. That's possible as a later step.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Capture setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.brand, in: Circle())
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}
