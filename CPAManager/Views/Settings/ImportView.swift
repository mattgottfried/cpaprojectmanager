import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import clients, time or your fee schedule from a CSV (a spreadsheet, or a QuickBooks customer list export).
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.defaultHourlyRate) private var defaultHourlyRate = 150.0

    enum Kind: String, CaseIterable, Identifiable {
        case clients = "Clients", time = "Time entries", fees = "Fee schedule"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .clients
    @State private var showingImporter = false
    @State private var fileName = ""
    @State private var rows: [[String]] = []
    @State private var message: String?
    @State private var done: String?

    private var clientPlan: ClientImportPlan {
        let keys = ImportService.existingKeys(context: context)
        return ClientImport.plan(rows: rows, existingEmails: keys.emails, existingNames: keys.names)
    }
    private var timePlan: TimeImportPlan { TimeImport.plan(rows: rows) }
    private var feePlan: FeeImportPlan { FeeImport.plan(rows: rows, existingNames: ImportService.existingFeeNames(context: context)) }

    var body: some View {
        Form {
            Section {
                Picker("Import", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, _ in done = nil }
                Button { showingImporter = true } label: { Label("Choose a CSV file…", systemImage: "doc.badge.plus") }
                if !fileName.isEmpty { LabeledContent("File", value: fileName) }
            } footer: {
                switch kind {
                case .clients:
                    Text("Columns are matched by name: Name (or Customer), Company, Email, Phone, Entity type, Tags, Notes. A QuickBooks customer list exported to CSV works. Clients whose email or name already exist are skipped.")
                case .time:
                    Text("Columns: Date, Hours, and optionally Client, Project, Rate, Notes, Billable. Hours can be 1.5, 1:30 or 1h 30m.")
                case .fees:
                    Text("Columns: Name and Price, and optionally Description and Hourly (yes/no; a price like \"$300/hr\" also counts as hourly). Items whose name is already in your fee schedule are skipped. Imported items show up in More ▸ Fee Schedule and in quotes and invoices.")
                }
            }

            if let message {
                Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.color(.caution)) }
            }

            if !rows.isEmpty { preview }

            if let done {
                Section { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.color(.good)) }
            }
        }
        .navigationTitle("Import")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            load(result)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if kind == .clients {
            let plan = clientPlan
            if let missing = plan.missingRequiredColumn {
                Section { Text("Couldn't find \(missing).").foregroundStyle(.secondary) }
            } else {
                Section("Ready to import") {
                    LabeledContent("New clients", value: "\(plan.records.count)")
                    LabeledContent("Skipped", value: "\(plan.skipped.count)")
                    ForEach(Array(plan.records.prefix(5).enumerated()), id: \.offset) { _, record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.name)
                            Text([record.email, record.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    skippedList(plan.skipped)
                    Button("Import \(plan.records.count) client\(plan.records.count == 1 ? "" : "s")") {
                        let n = ImportService.importClients(plan, context: context)
                        done = "Imported \(n) client\(n == 1 ? "" : "s")."
                        rows = []; fileName = ""
                    }
                    .disabled(plan.records.isEmpty)
                }
            }
        } else if kind == .fees {
            let plan = feePlan
            if let missing = plan.missingRequiredColumn {
                Section { Text("Couldn't find \(missing).").foregroundStyle(.secondary) }
            } else {
                Section("Ready to import") {
                    LabeledContent("New fee items", value: "\(plan.records.count)")
                    LabeledContent("Skipped", value: "\(plan.skipped.count)")
                    ForEach(Array(plan.records.prefix(8).enumerated()), id: \.offset) { _, record in
                        HStack {
                            Text(record.name).lineLimit(1)
                            Spacer()
                            Text(record.isHourly ? "\(Format.currency(record.unitPrice))/hr" : Format.currency(record.unitPrice))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if plan.records.count > 8 {
                        Text("…and \(plan.records.count - 8) more").font(.caption).foregroundStyle(.secondary)
                    }
                    skippedList(plan.skipped)
                    Button("Import \(plan.records.count) fee item\(plan.records.count == 1 ? "" : "s")") {
                        let n = ImportService.importFees(plan, context: context)
                        done = "Imported \(n) fee item\(n == 1 ? "" : "s"). Find them in More ▸ Fee Schedule."
                        rows = []; fileName = ""
                    }
                    .disabled(plan.records.isEmpty)
                }
            }
        } else {
            let plan = timePlan
            if let missing = plan.missingRequiredColumn {
                Section { Text("Couldn't find \(missing).").foregroundStyle(.secondary) }
            } else {
                Section("Ready to import") {
                    LabeledContent("Entries", value: "\(plan.records.count)")
                    LabeledContent("Total hours", value: String(format: "%.2f", plan.records.reduce(0) { $0 + $1.hours }))
                    LabeledContent("Skipped", value: "\(plan.skipped.count)")
                    skippedList(plan.skipped)
                    Button("Import \(plan.records.count) entr\(plan.records.count == 1 ? "y" : "ies")") {
                        let r = ImportService.importTime(plan, defaultRate: defaultHourlyRate, context: context)
                        done = "Imported \(r.imported) entries." + (r.unmatchedClients > 0 ? " \(r.unmatchedClients) had a client name that didn't match anyone." : "")
                        rows = []; fileName = ""
                    }
                    .disabled(plan.records.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func skippedList(_ skipped: [ImportSkip]) -> some View {
        if !skipped.isEmpty {
            DisclosureGroup("Why rows were skipped") {
                ForEach(Array(skipped.prefix(20).enumerated()), id: \.offset) { _, skip in
                    Text("Row \(skip.row): \(skip.reason)").font(.caption).foregroundStyle(.secondary)
                }
                if skipped.count > 20 { Text("…and \(skipped.count - 20) more").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func load(_ result: Result<[URL], Error>) {
        message = nil; done = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { message = "Couldn't read that file."; return }
        // Excel on Windows often saves CSVs as Windows-1252, not UTF-8.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            message = "That file isn't plain text."
            return
        }
        rows = CSVParser.parse(text)
        fileName = url.lastPathComponent
        if rows.isEmpty { message = "The file is empty." }
    }
}
