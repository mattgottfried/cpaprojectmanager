import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Bindable var client: Client
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var showingAddProject = false

    private var sortedProjects: [Project] {
        client.projectList.sorted {
            if $0.status.order != $1.status.order { return $0.status.order < $1.status.order }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Avatar(initials: client.initials, size: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(client.displayName).font(.title3.bold())
                        HStack(spacing: 6) {
                            EntityBadge(entityType: client.entityType)
                            ClientStatusBadge(status: client.status)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                ContactButtons(client: client)
            }

            if !client.email.isEmpty || !client.phone.isEmpty {
                Section("Contact") {
                    if !client.email.isEmpty {
                        LabeledContent("Email", value: client.email)
                    }
                    if !client.phone.isEmpty {
                        LabeledContent("Phone", value: client.phone)
                    }
                }
            }

            if !client.notes.isEmpty {
                Section("Notes") { Text(client.notes) }
            }

            Section("Projects") {
                if sortedProjects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedProjects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            ProjectRow(project: project, showClient: false)
                        }
                    }
                }
                Button {
                    showingAddProject = true
                } label: {
                    Label("New project", systemImage: "plus")
                }
            }

            DocumentsSectionView(client: client)
        }
        .navigationTitle(client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) { ClientFormView(client: client) }
        .sheet(isPresented: $showingAddProject) { ProjectFormView(defaultClient: client) }
    }
}

/// Tap-to-call / text / email buttons.
struct ContactButtons: View {
    let client: Client
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            if !client.phone.isEmpty {
                actionButton("Call", "phone.fill", url: URL(string: "tel:\(digits(client.phone))"))
                actionButton("Text", "message.fill", url: URL(string: "sms:\(digits(client.phone))"))
            }
            if !client.email.isEmpty {
                actionButton("Email", "envelope.fill", url: URL(string: "mailto:\(client.email)"))
            }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.brand)
        .disabled(url == nil)
    }

    private func digits(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }
}
