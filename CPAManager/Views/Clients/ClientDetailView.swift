import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Bindable var client: Client
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var showingAddProject = false
    @State private var logKind: InteractionKind?
    @State private var showingFollowUpPicker = false
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @State private var toast: UndoToastState?

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

            followUpSection

            if client.leadStage != nil {
                leadSection
            }

            TaxDeadlinesSection(client: client)

            if !client.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(client.tags, id: \.self) { tag in
                                CapsuleBadge(text: "#\(tag)", systemImage: "tag.fill", state: .info)
                            }
                        }
                    }
                }
            }

            if !client.notes.isEmpty {
                Section("Notes") { Text(client.notes) }
            }

            activitySection

            Section("Projects") {
                if sortedProjects.isEmpty {
                    Text("No projects yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedProjects) { project in
                        NavigationLink {
                            ProjectDetailView(project: project)
                        } label: {
                            ProjectRow(project: project, showClient: false, card: false)
                        }
                    }
                }
                Button {
                    showingAddProject = true
                } label: {
                    Label("New project", systemImage: "plus")
                }
            }

            DocumentRequestsSection(client: client)

            DocumentsSectionView(client: client)
        }
        .navigationTitle(client.displayName)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEdit = true }
            }
        }
        .undoToast($toast)
        .sheet(isPresented: $showingFollowUpPicker) {
            FollowUpDateSheet(initial: client.followUpDate) { date in setFollowUp(date) }
        }
        .sheet(item: $logKind) { kind in InteractionFormView(client: client, initialKind: kind) }
        .sheet(isPresented: $showingEdit) { ClientFormView(client: client) }
        .sheet(isPresented: $showingAddProject) { ProjectFormView(defaultClient: client) }
    }
}

extension ClientDetailView {
    @ViewBuilder
    var followUpSection: some View {
        Section {
            HStack {
                Label(
                    client.followUpDate.map { "Follow up \(Format.relativeDay($0).lowercased())" } ?? "No follow-up set",
                    systemImage: client.followUpDate == nil ? "bell.slash" : "bell.fill"
                )
                .foregroundStyle(client.followUpDate == nil ? AnyShapeStyle(HierarchicalShapeStyle.secondary) : AnyShapeStyle(Theme.brand))
                Spacer()
                Menu {
                    ForEach(FollowUpPreset.allCases) { preset in
                        Button { setFollowUp(preset.date()) } label: { Label(preset.label, systemImage: "calendar") }
                    }
                    Button { showingFollowUpPicker = true } label: { Label("Choose a date…", systemImage: "calendar.badge.plus") }
                    if client.followUpDate != nil {
                        Button(role: .destructive) { setFollowUp(nil) } label: { Label("Clear", systemImage: "xmark") }
                    }
                } label: {
                    Text(client.followUpDate == nil ? "Set" : "Change")
                        .font(.subheadline.weight(.semibold))
                }
            }
        } header: {
            Text("Follow-up")
        } footer: {
            Text("Shows on Today from that day. Logging a call, email, text or meeting clears it.")
        }
    }

    @ViewBuilder
    var leadSection: some View {
        Section("Lead") {
            Picker("Stage", selection: leadStageBinding) {
                ForEach(LeadStage.allCases) { stage in
                    Label(stage.label, systemImage: stage.systemImage).tag(stage)
                }
            }
            LabeledContent("Est. annual fees") {
                TextField("Amount", value: leadValueBinding, format: .currency(code: "USD"))
                    .multilineTextAlignment(.trailing)
                    .decimalKeyboard()
            }
            if client.leadStage?.isOpen == true {
                Button {
                    client.leadStage = .won
                    try? context.save()
                } label: {
                    Label("Won — make an active client", systemImage: "checkmark.seal.fill")
                }
            }
        }
    }

    private var leadStageBinding: Binding<LeadStage> {
        Binding(
            get: { client.leadStage ?? .new },
            set: { client.leadStage = $0; try? context.save() }
        )
    }

    private var leadValueBinding: Binding<Double> {
        Binding(get: { client.leadValue }, set: { client.leadValue = $0; try? context.save() })
    }

    func setFollowUp(_ date: Date?) {
        client.followUpDate = date.map { Calendar.current.startOfDay(for: $0) }
        try? context.save()
        NotificationScheduler.rescheduleAll(context: context, morningHour: reminderHour)
        SnapshotBuilder.rebuild(context: context)
    }

    private var recentActivity: [Interaction] {
        Array(client.interactionList.sorted { $0.occurredAt > $1.occurredAt }.prefix(5))
    }

    @ViewBuilder
    var activitySection: some View {
        Section {
            LabeledContent("Last contact", value: ClientActivity.lastContactLabel(client.lastContactedAt))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InteractionKind.allCases) { kind in
                        Button { logKind = kind } label: {
                            Label("Log \(kind.label.lowercased())", systemImage: kind.systemImage)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Theme.brand.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brand)
                    }
                }
            }

            ForEach(recentActivity) { entry in
                InteractionRow(interaction: entry)
                    .swipeActions {
                        Button(role: .destructive) { remove(entry) } label: { Label("Delete", systemImage: "trash") }
                    }
            }

            if client.interactionList.count > recentActivity.count {
                NavigationLink {
                    InteractionHistoryView(client: client)
                } label: {
                    Label("All activity (\(client.interactionList.count))", systemImage: "clock.arrow.circlepath")
                }
            }
        } header: {
            Text("Activity")
        }
    }

    private func remove(_ entry: Interaction) {
        let kind = entry.kind, summary = entry.summary, when = entry.occurredAt
        context.delete(entry)
        try? context.save()
        toast = UndoToastState(message: "Deleted \(kind.label.lowercased())", systemImage: "trash") {
            context.insert(Interaction(kind: kind, summary: summary, occurredAt: when, client: client))
            try? context.save()
        }
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

/// Pick an exact follow-up date.
struct FollowUpDateSheet: View {
    var initial: Date?
    var onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Follow up on", selection: $date, in: Date.now..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
            }
            .navigationTitle("Follow-up date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { onPick(date); dismiss() }
                }
            }
            .onAppear { if let initial, initial > .now { date = initial } }
        }
        .presentationDetents([.medium, .large])
    }
}
