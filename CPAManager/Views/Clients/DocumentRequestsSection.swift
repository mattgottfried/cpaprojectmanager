import SwiftUI
import SwiftData

/// "Documents needed" on a client: what they owe you, ticked off as it arrives, with a
/// one-tap email that chases whatever is still missing.
struct DocumentRequestsSection: View {
    let client: Client

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @State private var newTitle = ""

    private var requests: [DocumentRequest] {
        client.documentRequestList.sorted {
            if $0.isReceived != $1.isReceived { return !$0.isReceived }
            return $0.requestedAt < $1.requestedAt
        }
    }

    private var outstanding: [DocumentRequest] { requests.filter { !$0.isReceived } }

    private var unusedSuggestions: [String] {
        let have = Set(requests.map { GlobalSearch.normalize($0.title) })
        return DocumentChecklist.suggestions(for: client.entityType).filter { !have.contains(GlobalSearch.normalize($0)) }
    }

    var body: some View {
        Section {
            if !requests.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: DocumentChecklist.progress(received: requests.count - outstanding.count, total: requests.count))
                        .tint(outstanding.isEmpty ? Theme.good : Theme.brand)
                    Text(outstanding.isEmpty ? "Everything received" : "\(requests.count - outstanding.count) of \(requests.count) received")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            ForEach(requests) { request in
                row(request)
            }

            HStack {
                TextField("Add a document you need", text: $newTitle)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.brand)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add document request")
            }

            if !unusedSuggestions.isEmpty {
                Menu {
                    ForEach(unusedSuggestions, id: \.self) { suggestion in
                        Button(suggestion) { insert(suggestion) }
                    }
                    if unusedSuggestions.count > 1 {
                        Divider()
                        Button("Add all \(unusedSuggestions.count)") { unusedSuggestions.forEach(insert) }
                    }
                } label: {
                    Label("Suggested for \(client.entityType.code == "—" ? "this client" : client.entityType.code)", systemImage: "list.bullet.clipboard")
                }
            }

            if !outstanding.isEmpty, !client.email.isEmpty {
                Button(action: emailClient) {
                    Label("Email about \(outstanding.count) missing item\(outstanding.count == 1 ? "" : "s")", systemImage: "envelope.badge")
                }
            }
        } header: {
            Text("Documents needed")
        } footer: {
            Text("Requests with a due date show on Today until they arrive.")
        }
    }

    private func row(_ request: DocumentRequest) -> some View {
        HStack(spacing: 12) {
            Button {
                toggle(request)
            } label: {
                Image(systemName: request.isReceived ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(request.isReceived ? Theme.good : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(request.isReceived ? "Received. Mark as still needed" : "Mark as received")

            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .strikethrough(request.isReceived)
                    .foregroundStyle(request.isReceived ? Color.secondary : Color.primary)
                if let received = request.receivedAt {
                    Text("Received \(received.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let due = request.dueDate {
                    DueDatePill(date: due)
                }
            }
            Spacer(minLength: 0)
        }
        .swipeActions {
            Button(role: .destructive) { delete(request) } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Menu {
                ForEach(FollowUpPreset.allCases) { preset in
                    Button(preset.label) { setDue(request, preset.date()) }
                }
                if request.dueDate != nil {
                    Button("Clear due date", role: .destructive) { setDue(request, nil) }
                }
            } label: { Label("Need it by…", systemImage: "calendar") }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        insert(title)
        newTitle = ""
    }

    private func insert(_ title: String) {
        context.insert(DocumentRequest(title: title, client: client))
        persist()
    }

    private func toggle(_ request: DocumentRequest) {
        request.isReceived ? request.markOutstanding() : request.markReceived()
        persist()
    }

    private func setDue(_ request: DocumentRequest, _ date: Date?) {
        request.dueDate = date
        persist()
    }

    private func delete(_ request: DocumentRequest) {
        context.delete(request)
        persist()
    }

    private func persist() {
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
    }

    private func emailClient() {
        let earliest = outstanding.compactMap(\.dueDate).min()
        let body = DocumentChecklist.requestEmailBody(
            clientName: client.displayName, items: outstanding.map(\.title), dueDate: earliest, firm: firmName
        )
        if let url = InvoiceMath.reminderURL(to: client.email, subject: "Documents I still need", body: body) {
            openURL(url)
            // Reaching out counts as contact.
            context.insert(Interaction(kind: .email, summary: "Requested \(outstanding.count) missing document\(outstanding.count == 1 ? "" : "s")", client: client))
            try? context.save()
        }
    }
}
