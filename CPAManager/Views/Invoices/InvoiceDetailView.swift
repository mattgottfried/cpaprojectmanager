import SwiftUI
import SwiftData

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(QBOAuthService.self) private var qboAuth
    @AppStorage(SettingsKeys.firmName) private var firmName = ""

    @State private var pdfURL: URL?
    @State private var showingShare = false
    @State private var isSyncing = false

    var body: some View {
        List {
            Section {
                LabeledContent("Invoice #", value: invoice.displayNumber)
                LabeledContent("Client", value: invoice.client?.displayName ?? "No client")
                DatePicker("Issued", selection: issueDateBinding, displayedComponents: .date)
                DatePicker("Due", selection: dueDateBinding, displayedComponents: .date)
                Picker("Status", selection: statusBinding) {
                    ForEach(InvoiceStatus.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Line Items") {
                if invoice.lineList.isEmpty {
                    Text("No line items.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(invoice.lineList) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.detail)
                            Text("\(String(format: "%.2f", line.quantity)) × \(Format.currency(line.rate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Format.currency(line.amount))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .onDelete(perform: deleteLine)

                HStack {
                    Text("Total").font(.headline)
                    Spacer()
                    Text(Format.currency(invoice.total)).font(.headline)
                }
            }

            Section("Notes") {
                TextField("Notes", text: notesBinding, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section {
                Button {
                    generateAndShare()
                } label: {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
            }

            Section {
                HStack {
                    Text("QuickBooks")
                    Spacer()
                    QBOSyncStateBadge(state: invoice.qboSyncState)
                }
                if invoice.qboSyncState == .failed, !invoice.qboSyncError.isEmpty {
                    Text(invoice.qboSyncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await sendToQuickBooks() }
                } label: {
                    if isSyncing {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(
                            invoice.qboSyncState == .synced ? "Sync Again" : "Send to QuickBooks",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .disabled(!qboAuth.isConnected || isSyncing)
                if !qboAuth.isConnected {
                    Text("Connect QuickBooks in Settings > QuickBooks Online first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(invoice.displayNumber)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShare) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
    }

    private var statusBinding: Binding<InvoiceStatus> {
        Binding(get: { invoice.status }, set: { invoice.status = $0; persist() })
    }
    private var issueDateBinding: Binding<Date> {
        Binding(get: { invoice.issueDate }, set: { invoice.issueDate = $0; persist() })
    }
    private var dueDateBinding: Binding<Date> {
        Binding(get: { invoice.dueDate }, set: { invoice.dueDate = $0; persist() })
    }
    private var notesBinding: Binding<String> {
        Binding(get: { invoice.notes }, set: { invoice.notes = $0; persist() })
    }

    private func deleteLine(_ offsets: IndexSet) {
        let list = invoice.lineList
        let entryIDs = Set(offsets.compactMap { list[$0].timeEntryID })
        if !entryIDs.isEmpty, let allEntries = try? context.fetch(FetchDescriptor<TimeEntry>()) {
            for entry in allEntries where entryIDs.contains(entry.id) {
                entry.invoiceID = nil
            }
        }
        for index in offsets { context.delete(list[index]) }
        persist()
    }

    private func persist() {
        try? context.save()
    }

    private func generateAndShare() {
        let url = InvoicePDF.generate(invoice: invoice, firmName: firmName.isEmpty ? "My Firm" : firmName)
        pdfURL = url
        showingShare = url != nil
    }

    private func sendToQuickBooks() async {
        isSyncing = true
        defer { isSyncing = false }
        await QBOSyncService.send(invoice: invoice, auth: qboAuth, context: context)
    }
}
