import SwiftUI
import SwiftData

/// The sales pipeline: prospects grouped by stage, with one-swipe advance.
struct LeadsView: View {
    /// True when pushed from another stack so it doesn't nest a second NavigationStack.
    var embedded = false

    @Environment(\.modelContext) private var context
    @Query(sort: \Client.createdAt, order: .reverse) private var clients: [Client]

    @State private var showingNew = false
    @State private var toast: UndoToastState?
    @State private var logClient: Client?
    @State private var showClosed = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var leads: [Client] { clients.filter { $0.leadStage != nil } }

    private var summary: LeadPipeline.Summary {
        LeadPipeline.summarize(leads.compactMap(\.leadSummary))
    }

    private var staleIDs: Set<UUID> {
        Set(LeadPipeline.staleLeads(leads.compactMap(\.leadSummary)))
    }

    private func leads(in stage: LeadStage) -> [Client] {
        leads.filter { $0.leadStage == stage }
    }

    private var content: some View {
        List {
            if !leads.isEmpty {
                summaryCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(LeadStage.openStages) { stage in
                let group = leads(in: stage)
                if !group.isEmpty {
                    Section {
                        ForEach(group) { client in leadRow(client) }
                    } header: {
                        stageHeader(stage, count: group.count)
                    }
                }
            }

            let closed = leads(in: .won) + leads(in: .lost)
            if !closed.isEmpty {
                Section {
                    if showClosed {
                        ForEach(closed) { client in leadRow(client) }
                    }
                } header: {
                    Button {
                        withAnimation { showClosed.toggle() }
                    } label: {
                        HStack {
                            Label("Closed (\(closed.count))", systemImage: showClosed ? "chevron.down" : "chevron.right")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .overlay {
            if leads.isEmpty {
                ContentUnavailableView {
                    Label("No leads yet", systemImage: "funnel")
                } description: {
                    Text("Add a prospect and move them through New → Contacted → Proposal sent → Won.")
                } actions: {
                    Button("Add a lead") { showingNew = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Leads")
        .navigationDestination(for: Client.self) { ClientDetailView(client: $0) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add lead")
            }
        }
        .sheet(isPresented: $showingNew) { LeadFormView() }
        .sheet(item: $logClient) { client in InteractionFormView(client: client, initialKind: .call) }
        .undoToast($toast)
    }

    // MARK: Pieces

    private var summaryCard: some View {
        SectionCard(title: "Pipeline", systemImage: "funnel.fill", state: .info) {
            HStack(spacing: 10) {
                StatChip(value: "\(summary.openCount)", label: "Open leads", state: .info)
                StatChip(value: Format.currency(summary.openValue), label: "Est. value", state: .good)
                StatChip(
                    value: summary.winRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                    label: "Win rate",
                    state: .neutral
                )
            }
            if !staleIDs.isEmpty {
                Label("\(staleIDs.count) lead\(staleIDs.count == 1 ? "" : "s") untouched for a week", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.caution)
            }
        }
    }

    private func stageHeader(_ stage: LeadStage, count: Int) -> some View {
        HStack {
            Label(stage.label, systemImage: stage.systemImage)
                .font(.headline)
                .foregroundStyle(Theme.color(stage.state))
            Spacer()
            Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .textCase(nil)
    }

    private func leadRow(_ client: Client) -> some View {
        let stage = client.leadStage ?? .new
        let isStale = staleIDs.contains(client.id)
        return NavigationLink(value: client) {
            HStack(spacing: 12) {
                StatusTile(systemImage: stage.systemImage, state: stage.state)
                VStack(alignment: .leading, spacing: 4) {
                    Text(client.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if client.leadValue > 0 {
                            Text(Format.currency(client.leadValue))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.good)
                        }
                        Label(ClientActivity.lastContactLabel(client.lastContactedAt), systemImage: isStale ? "exclamationmark.bubble.fill" : "clock")
                            .font(.caption)
                            .foregroundStyle(isStale ? AnyShapeStyle(Theme.caution) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                            .lineLimit(1)
                    }
                    if let due = client.followUpDate {
                        Label("Follow up \(Format.relativeDay(due))", systemImage: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .rowCard(dimmed: stage == .lost)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(client.displayName)
            .accessibilityValue(accessibilityValue(client, stage: stage, isStale: isStale))
            .accessibilityHint("Opens the client. Swipe to advance or mark lost.")
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let next = LeadPipeline.advance(stage) {
                Button { move(client, to: next) } label: { Label(next.label, systemImage: next.systemImage) }
                    .tint(Theme.color(next.state))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if stage.isOpen {
                Button { move(client, to: .lost) } label: { Label("Lost", systemImage: "xmark.circle.fill") }
                    .tint(Theme.neutral)
            }
        }
        .contextMenu {
            Button { logClient = client } label: { Label("Log contact…", systemImage: "phone.fill") }
            Menu {
                ForEach(LeadStage.allCases) { target in
                    Button { move(client, to: target) } label: { Label(target.label, systemImage: target.systemImage) }
                }
            } label: { Label("Move to", systemImage: "arrow.right.circle") }
        }
    }

    private func accessibilityValue(_ client: Client, stage: LeadStage, isStale: Bool) -> String {
        var parts = [stage.label]
        if client.leadValue > 0 { parts.append("estimated \(Format.currency(client.leadValue))") }
        parts.append("last contact \(ClientActivity.lastContactLabel(client.lastContactedAt))")
        if isStale { parts.append("needs attention") }
        return parts.joined(separator: ", ")
    }

    // MARK: Actions

    private func move(_ client: Client, to stage: LeadStage) {
        let previousRaw = client.leadStageRaw
        let previousStatus = client.status
        client.leadStage = stage
        try? context.save()
        toast = UndoToastState(message: "\(client.displayName): \(stage.label)", systemImage: stage.systemImage) {
            client.leadStageRaw = previousRaw
            client.status = previousStatus
            try? context.save()
        }
    }
}

/// Add a prospect.
struct LeadFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8

    @State private var name = ""
    @State private var company = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var value: Double = 0
    @State private var notes = ""
    @State private var remind = true

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty || !company.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Company (optional)", text: $company)
                    TextField("Email", text: $email)
                        .emailFieldTraits()
                    TextField("Phone", text: $phone)
                        .phoneFieldTraits()
                }
                Section {
                    LabeledContent("Est. annual fees") {
                        TextField("Amount", value: $value, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                    }
                    TextField("How they found you, what they need…", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle("Remind me to follow up in 2 days", isOn: $remind)
                }
            }
            .navigationTitle("New Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
        .macSheetFrame()
    }

    private func save() {
        let client = Client(name: name, company: company, status: .prospect, email: email, phone: phone, notes: notes)
        client.leadStage = .new
        client.leadValue = value
        if remind {
            client.followUpDate = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: .now))
        }
        context.insert(client)
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        dismiss()
    }
}
