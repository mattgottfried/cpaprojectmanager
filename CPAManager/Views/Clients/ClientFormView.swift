import SwiftUI
import SwiftData
import Contacts

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
    @State private var tagsText = ""
    @State private var showingContactPicker = false
    @Query private var allClients: [Client]

    private var isEditing: Bool { client != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty || !company.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Company (optional)", text: $company)
                    #if os(iOS)
                    Button {
                        showingContactPicker = true
                    } label: {
                        Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                    #endif
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
                        .emailFieldTraits()
                    TextField("Phone", text: $phone)
                        .phoneFieldTraits()
                }
                Section {
                    TextField("Tags, separated by commas", text: $tagsText)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                    if !suggestedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    Button { addTag(tag) } label: {
                                        CapsuleBadge(text: "#\(tag)", systemImage: "plus", state: .info)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("e.g. referral, bookkeeping, side-hustle. Use tags to filter the client list.")
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(isEditing ? "Edit Client" : "New Client")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: loadIfEditing)
            #if os(iOS)
            .sheet(isPresented: $showingContactPicker) {
                ContactPickerView { contact in
                    if let contact { fill(from: contact) }
                    showingContactPicker = false
                }
                .ignoresSafeArea()
            }
            #endif
        }
    }

    #if os(iOS)
    private func fill(from contact: CNContact) {
        let fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !fullName.isEmpty { name = fullName }
        if !contact.organizationName.isEmpty { company = contact.organizationName }
        if let firstEmail = contact.emailAddresses.first { email = firstEmail.value as String }
        if let firstPhone = contact.phoneNumbers.first { phone = firstPhone.value.stringValue }
    }
    #endif

    /// Existing tags in use that this client doesn't have yet.
    private var suggestedTags: [String] {
        let current = Set(TagSet.parse(tagsText))
        return TagSet.counts(allClients.map { $0.tags }).map { $0.tag }.filter { !current.contains($0) }.prefix(8).map { $0 }
    }

    private func addTag(_ tag: String) {
        tagsText = TagSet.encode(TagSet.parse(tagsText) + [tag])
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
        tagsText = client.tagsRaw
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
            client.tagsRaw = TagSet.encode(TagSet.parse(tagsText))
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
            newClient.tagsRaw = TagSet.encode(TagSet.parse(tagsText))
            context.insert(newClient)
        }
        try? context.save()
        dismiss()
    }
}
