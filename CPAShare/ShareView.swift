import SwiftUI

/// The compose sheet shown by the share extension: review the text, say where it came
/// from, and send it to the CPA Manager inbox.
struct ShareView: View {
    @State var text: String
    let link: String
    let attachmentNames: [String]
    let onSave: (_ text: String, _ sourceRaw: String) -> Void
    let onCancel: () -> Void

    @State private var sourceRaw = "email"

    private struct SourceOption: Identifiable {
        let raw: String
        let label: String
        var id: String { raw }
    }

    private let sources = [
        SourceOption(raw: "email", label: "Email"),
        SourceOption(raw: "note", label: "Note"),
        SourceOption(raw: "text", label: "Text message"),
    ]

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachmentNames.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Came from", selection: $sourceRaw) {
                        ForEach(sources) { Text($0.label).tag($0.raw) }
                    }
                }
                Section("What should you do about it?") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                }
                if !link.isEmpty {
                    Section("Link") {
                        Text(link).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                if !attachmentNames.isEmpty {
                    Section("Attachments") {
                        ForEach(attachmentNames, id: \.self) { name in
                            let parts = PendingCaptures.displayParts(name)
                            Label(parts.ext.isEmpty ? parts.base : "\(parts.base).\(parts.ext)", systemImage: "paperclip")
                        }
                    }
                }
            }
            .navigationTitle("Add to Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(text, sourceRaw) }.disabled(!canSave)
                }
            }
        }
    }
}
