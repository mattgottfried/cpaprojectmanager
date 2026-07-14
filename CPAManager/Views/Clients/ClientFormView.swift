import SwiftUI
import SwiftData

/// Add or edit a client. Pass an existing `client` to edit; omit it to create.
struct ClientFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var client: Client?

    @State private var name = ""
    @State private var company = ""
    @State private var entityType: EntityType = .individual1040
    @State private var status: ClientStatus = .active
    @State private var email = ""
    @State private var phone = ""
    @State private var notes = ""

    private var isEditing: Bool { client != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty || !company.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Company (optional)", text: $company)
                }
                Section {
                    Picker("Entity type", selection: $entityType) {
                        ForEach(EntityType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ClientStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Contact") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Client" : "New Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfEditing)
        }
    }

    private func loadIfEditing() {
        guard let client else { return }
        name = client.name
        company = client.company
        entityType = client.entityType
        status = client.status
        email = client.email
        phone = client.phone
        notes = client.notes
    }

    private func save() {
        if let client {
            client.name = name
            client.company = company
            client.entityType = entityType
            client.status = status
            client.email = email
            client.phone = phone
            client.notes = notes
        } else {
            let newClient = Client(
                name: name,
                company: company,
                entityType: entityType,
                status: status,
                email: email,
                phone: phone,
                notes: notes
            )
            context.insert(newClient)
        }
        try? context.save()
        dismiss()
    }
}
