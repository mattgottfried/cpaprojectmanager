import SwiftUI
import SwiftData

/// Paste a block of text (your Siri-digested texts note, an email body) and pick out
/// what's new. Uses the same parser and dedupe as the Shortcuts action.
struct PasteCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [InboxItem]

    @State private var text = ""
    @State private var source: InboxSource = .note

    private let sources: [InboxSource] = [.note, .text, .email]

    private var summary: (fresh: Int, duplicate: Int, checked: Int) {
        let known = Set(existing.map(\.dedupeKey))
        var fresh = 0, duplicate = 0, checked = 0
        for candidate in NoteDigestParser.candidates(from: text) {
            if candidate.isChecked { checked += 1 }
            else if known.contains(NoteDigestParser.dedupeKey(candidate.text)) { duplicate += 1 }
            else { fresh += 1 }
        }
        return (fresh, duplicate, checked)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Came from", selection: $source) {
                        ForEach(sources, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(s)
                        }
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                        .accessibilityLabel("Text to capture")
                    Button {
                        if let pasted = Clipboard.string { text = pasted }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                    }
                } footer: {
                    Text("Each line becomes one inbox item. Lines you've captured before are skipped, so it's safe to paste the whole note again.")
                }

                if !text.isEmpty {
                    let s = summary
                    Section("Preview") {
                        Label("\(s.fresh) new", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.good)
                        if s.duplicate > 0 {
                            Label("\(s.duplicate) already captured", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                        }
                        if s.checked > 0 {
                            Label("\(s.checked) checked off (skipped)", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Paste to Inbox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        InboxService.capture(text: text, source: source, context: context)
                        dismiss()
                    }
                    .disabled(summary.fresh == 0)
                }
            }
        }
        .macSheetFrame()
        .presentationDetents([.large])
    }
}
