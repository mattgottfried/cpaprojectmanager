import SwiftUI
import SwiftData

/// Manage letter templates (engagement letters, proposals) and email templates.
struct TemplateLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LetterTemplate.name) private var letters: [LetterTemplate]
    @Query(sort: \EmailTemplate.name) private var emails: [EmailTemplate]

    @State private var editingLetter: LetterTemplate?
    @State private var editingEmail: EmailTemplate?
    @State private var newLetter = false
    @State private var newEmail = false

    var body: some View {
        GroupedList {
            Section {
                ForEach(letters) { letter in
                    Button { editingLetter = letter } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(letter.name).foregroundStyle(.primary)
                            Text(letter.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .deleteMenu { context.delete(letter); try? context.save() }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(letters[index]) }
                    try? context.save()
                }
                Button { newLetter = true } label: { Label("New letter template", systemImage: "plus") }
            } header: {
                Text("Letters & proposals")
            } footer: {
                Text("Fill in per client from the client screen and save as a PDF, with a signature block for engagement letters and proposals.")
            }

            Section {
                ForEach(emails) { email in
                    Button { editingEmail = email } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email.name).foregroundStyle(.primary)
                            Text(email.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .deleteMenu { context.delete(email); try? context.save() }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(emails[index]) }
                    try? context.save()
                }
                Button { newEmail = true } label: { Label("New email template", systemImage: "plus") }
            } header: {
                Text("Email templates")
            } footer: {
                Text("Opens in your mail app with the client's address filled in, and logs the email on the client.")
            }

            if letters.isEmpty && emails.isEmpty {
                Section {
                    Button(action: addStarters) {
                        Label("Add starter templates", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("An engagement letter, a proposal, and a few common emails to edit as you like.")
                }
            }

            Section("Merge fields") {
                ForEach(MergeFields.tokens, id: \.token) { item in
                    HStack {
                        Text("{\(item.token)}").font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Text(item.label).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Letters & Emails")
        .sheet(isPresented: $newLetter) { LetterTemplateEditor(template: nil) }
        .sheet(item: $editingLetter) { LetterTemplateEditor(template: $0) }
        .sheet(isPresented: $newEmail) { EmailTemplateEditor(template: nil) }
        .sheet(item: $editingEmail) { EmailTemplateEditor(template: $0) }
    }

    private func addStarters() {
        for starter in TemplateStarters.letters {
            context.insert(LetterTemplate(name: starter.name, kind: starter.kind, body: starter.body))
        }
        for starter in TemplateStarters.emails {
            context.insert(EmailTemplate(name: starter.name, subject: starter.subject, body: starter.body))
        }
        try? context.save()
    }
}

struct LetterTemplateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var template: LetterTemplate?
    @State private var name = ""
    @State private var kind: LetterKind = .engagement
    @State private var body_ = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(LetterKind.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    TextEditor(text: $body_)
                        .frame(minHeight: 260)
                        .font(.body)
                } header: {
                    HStack {
                        Text("Body")
                        Spacer()
                        MergeFieldMenu { body_ += "{\($0)}" }
                    }
                }
            }
            .navigationTitle(template == nil ? "New Letter" : "Edit Letter")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded, let template else { loaded = true; return }
                loaded = true
                name = template.name
                kind = template.kind
                body_ = template.body
            }
        }
        .macSheetFrame()
    }

    private func save() {
        if let template {
            template.name = name
            template.kind = kind
            template.body = body_
        } else {
            context.insert(LetterTemplate(name: name, kind: kind, body: body_))
        }
        try? context.save()
        dismiss()
    }
}

struct EmailTemplateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var template: EmailTemplate?
    @State private var name = ""
    @State private var subject = ""
    @State private var body_ = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                    TextField("Subject", text: $subject)
                }
                Section {
                    TextEditor(text: $body_).frame(minHeight: 200)
                } header: {
                    HStack {
                        Text("Body")
                        Spacer()
                        MergeFieldMenu { body_ += "{\($0)}" }
                    }
                }
            }
            .navigationTitle(template == nil ? "New Email" : "Edit Email")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded, let template else { loaded = true; return }
                loaded = true
                name = template.name
                subject = template.subject
                body_ = template.body
            }
        }
        .macSheetFrame()
    }

    private func save() {
        if let template {
            template.name = name
            template.subject = subject
            template.body = body_
        } else {
            context.insert(EmailTemplate(name: name, subject: subject, body: body_))
        }
        try? context.save()
        dismiss()
    }
}

/// "Insert field" menu for the template editors.
struct MergeFieldMenu: View {
    let insert: (String) -> Void
    var body: some View {
        Menu {
            ForEach(MergeFields.tokens, id: \.token) { item in
                Button(item.label) { insert(item.token) }
            }
        } label: {
            Label("Insert field", systemImage: "curlybraces")
                .font(.caption)
                .textCase(nil)
        }
    }
}
