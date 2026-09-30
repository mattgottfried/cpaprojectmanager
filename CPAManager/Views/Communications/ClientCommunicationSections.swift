import SwiftUI
import SwiftData

/// "Letters & email" section on the client screen.
struct ClientCommunicationSection: View {
    let client: Client
    @State private var showingLetter = false
    @State private var showingEmail = false

    var body: some View {
        Section("Letters & email") {
            Button { showingLetter = true } label: {
                Label("Draft letter or proposal…", systemImage: "doc.richtext")
            }
            Button { showingEmail = true } label: {
                Label("Email from template…", systemImage: "envelope.badge")
            }
        }
        .sheet(isPresented: $showingLetter) { ClientLetterSheet(client: client) }
        .sheet(isPresented: $showingEmail) { ClientEmailSheet(client: client) }
    }
}

/// Pick a letter template, fill in the client, edit the text, save as a PDF on the client.
struct ClientLetterSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LetterTemplate.name) private var templates: [LetterTemplate]
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.firmContact) private var firmContact = ""
    @AppStorage(SettingsKeys.uploadPageURL) private var uploadPageURL = ""

    let client: Client

    @State private var selectedID: UUID?
    @State private var fee = ""
    @State private var service = ""
    @State private var text = ""
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var savedNotice = false
    @State private var trackSignature = true

    private var selected: LetterTemplate? { templates.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            Form {
                if templates.isEmpty {
                    Section {
                        Text("No letter templates yet. Add some in More → Letters & Emails.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Template", selection: templateBinding) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                        }
                        TextField("Fee (e.g. $450)", text: feeBinding)
                        TextField("Service (e.g. monthly bookkeeping)", text: serviceBinding)
                        if selected?.kind.hasSignatureBlock == true {
                            Toggle("Track it as sent for signature", isOn: $trackSignature)
                        }
                    }
                    if selected != nil {
                        Section {
                            TextEditor(text: $text).frame(minHeight: 320)
                        } header: {
                            Text("Letter (edit freely)")
                        } footer: {
                            let unknown = MergeFields.unknownTokens(in: text, known: Set(MergeFields.tokens.map(\.token)))
                            if !unknown.isEmpty {
                                Text("Unfilled fields: \(unknown.map { "{\($0)}" }.joined(separator: " "))")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Draft Letter")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save PDF", action: savePDF).disabled(selected == nil || text.isEmpty)
                }
            }
            .alert("Saved to \(client.displayName)'s documents", isPresented: $savedNotice) {
                Button("Share…") { showingShare = true }
                Button("Done") { dismiss() }
            }
            .sheet(isPresented: $showingShare, onDismiss: { dismiss() }) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
        }
        .macSheetFrame()
    }

    // Changing template / fee / service re-merges from the template (edits so far are replaced).
    private var templateBinding: Binding<UUID?> {
        Binding(get: { selectedID }, set: { selectedID = $0; remerge() })
    }
    private var feeBinding: Binding<String> {
        Binding(get: { fee }, set: { fee = $0; remerge() })
    }
    private var serviceBinding: Binding<String> {
        Binding(get: { service }, set: { service = $0; remerge() })
    }

    private func remerge() {
        guard let selected else { text = ""; return }
        text = MergeFields.render(selected.body, values: MergeFields.values(
            clientName: client.displayName, company: client.company, email: client.email,
            firmName: firmName, fee: fee, service: service, uploadLink: UploadLink.normalized(uploadPageURL)
        ))
    }

    private func savePDF() {
        guard let selected else { return }
        let data = LetterPDF.data(
            body: text,
            firmName: firmName,
            firmContact: firmContact,
            signatureBlock: selected.kind.hasSignatureBlock,
            clientName: client.displayName
        )
        guard !data.isEmpty else { return }
        let stamp = Format.shortDate.string(from: .now).replacingOccurrences(of: "/", with: "-")
        let filename = "\(selected.name) - \(client.displayName) \(stamp)"
        let document = Document(filename: filename, fileExtension: "pdf", data: data, client: client)
        if trackSignature && selected.kind.hasSignatureBlock {
            document.signatureStatus = .sent
            document.signatureSentAt = .now
        }
        context.insert(document)
        try? context.save()

        let safe = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        if (try? data.write(to: url)) != nil { shareURL = url }
        savedNotice = true
    }
}

/// Pick an email template, preview the merged message, open it in the mail app, log it.
struct ClientEmailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query(sort: \EmailTemplate.name) private var templates: [EmailTemplate]
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.uploadPageURL) private var uploadPageURL = ""

    let client: Client

    @State private var selectedID: UUID?
    @State private var subject = ""
    @State private var text = ""

    private var canSend: Bool { MailtoBuilder.url(to: client.email, subject: subject, body: text) != nil }

    var body: some View {
        NavigationStack {
            Form {
                if templates.isEmpty {
                    Section {
                        Text("No email templates yet. Add some in More → Letters & Emails.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Template", selection: templateBinding) {
                            Text("Choose…").tag(UUID?.none)
                            ForEach(templates) { Text($0.name).tag(Optional($0.id)) }
                        }
                        LabeledContent("To", value: client.email.isEmpty ? "No email on file" : client.email)
                    }
                    if selectedID != nil {
                        Section("Subject") { TextField("Subject", text: $subject) }
                        Section("Message") { TextEditor(text: $text).frame(minHeight: 200) }
                    }
                }
            }
            .navigationTitle("Email Client")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open in Mail", action: send).disabled(!canSend)
                }
            }
        }
        .macSheetFrame()
    }

    private var templateBinding: Binding<UUID?> {
        Binding(get: { selectedID }, set: { id in
            selectedID = id
            guard let template = templates.first(where: { $0.id == id }) else { subject = ""; text = ""; return }
            let values = MergeFields.values(
                clientName: client.displayName, company: client.company, email: client.email, firmName: firmName,
                uploadLink: UploadLink.normalized(uploadPageURL)
            )
            subject = MergeFields.render(template.subject, values: values)
            text = MergeFields.render(template.body, values: values)
        })
    }

    private func send() {
        guard let url = MailtoBuilder.url(to: client.email, subject: subject, body: text) else { return }
        openURL(url)
        // Log it so the client's history (and "last contacted") stays current.
        context.insert(Interaction(kind: .email, summary: "Emailed: \(subject)", client: client))
        if ClientActivity.shouldClearFollowUp(client.followUpDate) { client.followUpDate = nil }
        try? context.save()
        dismiss()
    }
}
