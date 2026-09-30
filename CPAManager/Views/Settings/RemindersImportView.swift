import SwiftUI
import SwiftData

/// One-time migration screen: scans Apple Reminders for the firm's existing
/// workflow, shows a preview grouped by what will be created, and lets Matt
/// deselect anything before committing. Reminders are never modified.
struct RemindersImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case intro
        case denied
        case scanning
        case preview
        case importing
        case done(clients: Int, projects: Int, recurring: Int)
    }

    @State private var phase: Phase = .intro
    @State private var preview = ImportPreview(newClientNames: [], projects: [], recurring: [], entityHints: [:])

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import from Reminders")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
        }
        .macSheetFrame()
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .intro:
            introView
        case .denied:
            EmptyStateView(
                title: "Reminders Access Needed",
                message: "Allow full access to Reminders in Settings > Privacy & Security > Reminders > CPA Manager, then try again.",
                systemImage: "list.bullet.clipboard"
            )
        case .scanning:
            ProgressView("Scanning Reminders…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .preview:
            previewList
        case .importing:
            ProgressView("Importing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let clients, let projects, let recurring):
            doneView(clients: clients, projects: projects, recurring: recurring)
        }
    }

    private var introView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Theme.brand)
            Text("Import Your Reminders Workflow")
                .font(.title3.bold())
            Text("Scans your Apple Reminders lists — client work, bookkeeping, payroll, and sales tax — and shows you a preview before creating anything. Nothing in Reminders is changed or deleted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Scan Reminders") { Task { await scan() } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneView(clients: Int, projects: Int, recurring: Int) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Import Complete")
                .font(.title3.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("\(clients) new client\(clients == 1 ? "" : "s")")
                Text("\(projects) project\(projects == 1 ? "" : "s")")
                Text("\(recurring) recurring engagement\(recurring == 1 ? "" : "s")")
            }
            .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preview list

    private var includedProjectCount: Int { preview.projects.filter(\.isIncluded).count }
    private var includedRecurringCount: Int { preview.recurring.filter(\.isIncluded).count }

    private var previewList: some View {
        GroupedList {
            Section {
                Text("\(includedProjectCount) project\(includedProjectCount == 1 ? "" : "s") and \(includedRecurringCount) recurring item\(includedRecurringCount == 1 ? "" : "s") selected, across \(preview.newClientNames.count) new client\(preview.newClientNames.count == 1 ? "" : "s"). Likely duplicates are pre-unchecked — review before importing.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !preview.projects.isEmpty {
                Section("Projects") {
                    ForEach($preview.projects) { $item in
                        projectRow($item)
                    }
                }
            }

            if !preview.recurring.isEmpty {
                Section("Recurring Work") {
                    ForEach($preview.recurring) { $item in
                        recurringRow($item)
                    }
                }
            }

            if preview.isEmpty {
                Section {
                    Text("No open items found in Reminders.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await commitImport() }
            } label: {
                Text("Import Selected")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .disabled(includedProjectCount == 0 && includedRecurringCount == 0)
            .padding()
            .background(.bar)
        }
    }

    private func projectRow(_ item: Binding<ProposedProject>) -> some View {
        Toggle(isOn: item.isIncluded) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.wrappedValue.title).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(StatusFlow.taxReturn.label(item.wrappedValue.status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.wrappedValue.isDuplicate {
                        Text("· already exists")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let client = item.wrappedValue.clientName, !client.isEmpty {
                    Text(client).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recurringRow(_ item: Binding<ProposedRecurring>) -> some View {
        Toggle(isOn: item.isIncluded) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.wrappedValue.name).font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(item.wrappedValue.frequency.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.wrappedValue.isDuplicate {
                        Text("· already exists")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func scan() async {
        phase = .scanning
        let granted = await RemindersImporter.requestAccess()
        guard granted else {
            phase = .denied
            return
        }

        let existingClients = Set((try? context.fetch(FetchDescriptor<Client>()))?.map { $0.displayName.lowercased() } ?? [])
        let existingProjects = Set((try? context.fetch(FetchDescriptor<Project>()))?.map { $0.title.lowercased() } ?? [])
        let existingRecurring = Set((try? context.fetch(FetchDescriptor<RecurringEngagement>()))?.map { $0.name.lowercased() } ?? [])

        preview = await RemindersImporter.buildPreview(
            existingClientNames: existingClients,
            existingProjectTitles: existingProjects,
            existingRecurringNames: existingRecurring
        )
        phase = .preview
    }

    private func commitImport() async {
        phase = .importing
        let result = RemindersImporter.commit(preview: preview, context: context)
        phase = .done(clients: result.clients, projects: result.projects, recurring: result.recurring)
    }
}
