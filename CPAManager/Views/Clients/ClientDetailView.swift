import SwiftUI
import SwiftData

struct ClientDetailView: View {
    @Bindable var client: Client
    @Environment(\.modelContext) private var context
    @Environment(GoogleAuthService.self) private var google
    @State private var showingEdit = false
    @State private var showingAddProject = false
    @State private var logKind: InteractionKind?
    @State private var showingFollowUpPicker = false
    @AppStorage(SettingsKeys.reminderHour) private var reminderHour = 8
    @State private var toast: UndoToastState?
    @AppStorage(SettingsKeys.quietThresholdDays) private var quietDays = 14

    private var sortedProjects: [Project] {
        client.projectList.sorted {
            if $0.status.order != $1.status.order { return $0.status.order < $1.status.order }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    /// One glance at where this client stands: contact, open work, money, next deadline.
    @ViewBuilder
    private var healthSection: some View {
        let result = ClientHealthService.assess(client, quietDays: quietDays)
        let health = result.health
        let input = result.input
        Section {
            HStack {
                CapsuleBadge(text: health.headline, systemImage: healthIcon(health.level), state: healthState(health.level))
                Spacer()
            }
            if !health.reasons.isEmpty {
                Text(health.reasons.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Last contact", value: ClientActivity.lastContactLabel(input.lastContactedAt))
            LabeledContent("Open work", value: "\(input.openJobCount) job\(input.openJobCount == 1 ? "" : "s") · \(input.openTaskCount) task\(input.openTaskCount == 1 ? "" : "s")")
            if input.balanceOwedCents > 0 {
                LabeledContent("Owes", value: Format.currency(Double(input.balanceOwedCents) / 100)
                    + (input.overdueBalanceCents > 0 ? " (\(Format.currency(Double(input.overdueBalanceCents) / 100)) overdue)" : ""))
            }
            if let title = input.nextDeadlineTitle, let date = input.nextDeadlineDate {
                LabeledContent("Next deadline", value: "\(title) · \(Format.relativeDay(date))")
            }
        } header: {
            Text("Health")
        }
    }

    private func healthState(_ level: ClientHealth.Level) -> SemanticState {
        switch level {
        case .good:   return .good
        case .watch:  return .caution
        case .atRisk: return .bad
        }
    }

    private func healthIcon(_ level: ClientHealth.Level) -> String {
        switch level {
        case .good:   return "checkmark.circle.fill"
        case .watch:  return "eye.fill"
        case .atRisk: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        GroupedList {
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

            healthSection

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

            occasionsSection

            if !client.notes.isEmpty {
                Section {
                    MarkdownNotesView(text: $client.notes)
                } header: {
                    let progress = MarkdownBlocks.checkboxProgress(client.notes)
                    HStack {
                        Text("Notes")
                        if progress.total > 0 {
                            Spacer()
                            Text("\(progress.done)/\(progress.total) done")
                        }
                    }
                }
            }

            ClientCommunicationSection(client: client)

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

            DriveFolderSection(
                folderID: $client.driveFolderID, folderName: $client.driveFolderName, subject: "client",
                createFolder: { await DriveFolders.ensureClientFolder(client, auth: google, context: context) }
            )
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
    /// Upcoming birthday / anniversary for this client (Today shows the day-of nudge).
    @ViewBuilder
    var occasionsSection: some View {
        let sources = [OccasionSource(
            clientID: client.id, clientName: client.displayName,
            birthday: client.birthday, anniversary: client.anniversary,
            birthdayAckYear: client.birthdayAckYear, anniversaryAckYear: client.anniversaryAckYear,
            isActive: true
        )]
        let upcoming = Occasions.upcoming(sources, withinDays: 366)
        if !upcoming.isEmpty {
            Section("Dates to remember") {
                ForEach(upcoming) { occasion in
                    HStack {
                        Label(occasion.kind.label, systemImage: occasion.kind.systemImage)
                        Spacer()
                        Text(occasion.daysAway == 0 ? "Today" : Format.shortDate.string(from: occasion.date))
                            .foregroundStyle(occasion.daysAway <= 7 ? Theme.brand : .secondary)
                    }
                }
            }
        }
    }

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
        .macSheetFrame()
        .presentationDetents([.medium, .large])
    }
}
