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
    @State private var showingPayment = false
    @State private var toast: UndoToastState?
    @Environment(\.openURL) private var openURL

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

            paymentsSection

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
        .inlineNavigationTitle()
        .undoToast($toast)
        .sheet(isPresented: $showingPayment) {
            RecordPaymentSheet(invoice: invoice) { payment in
                toast = UndoToastState(message: "Recorded \(Format.currency(payment.amount))", systemImage: "banknote") {
                    invoice.payments?.removeAll { $0.id == payment.id }
                    context.delete(payment)
                    invoice.refreshPaidStatus()
                    persist()
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            if let pdfURL {
                ShareSheet(items: [pdfURL])
            }
        }
    }

    @ViewBuilder
    private var paymentsSection: some View {
        Section {
            LabeledContent("Paid so far", value: Format.currency(invoice.amountPaid))
            LabeledContent("Balance due") {
                Text(Format.currency(invoice.balance))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(invoice.isOverdue ? Theme.bad : Color.primary)
            }
            ForEach(invoice.paymentList) { payment in
                HStack {
                    Label(payment.method.label, systemImage: payment.method.systemImage)
                        .font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.currency(payment.amount)).font(.subheadline.monospacedDigit())
                        Text(payment.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                let list = invoice.paymentList
                for index in offsets {
                    invoice.payments?.removeAll { $0.id == list[index].id }
                    context.delete(list[index])
                }
                invoice.refreshPaidStatus()
                persist()
            }
            if invoice.balance > 0 {
                Button { showingPayment = true } label: {
                    Label("Record payment", systemImage: "banknote")
                }
                if let email = invoice.client?.email, !email.isEmpty, invoice.status == .sent {
                    Button { sendReminder(to: email) } label: {
                        Label("Email a reminder", systemImage: "envelope.badge")
                    }
                }
            }
            if qboAuth.isConnected, !invoice.qboId.isEmpty, invoice.status != .paid {
                Button {
                    Task {
                        let changed = await QBOSyncService.refreshPaidStatus(invoice: invoice, auth: qboAuth, context: context)
                        toast = UndoToastState(
                            message: changed ? "Updated from QuickBooks" : "No new payments in QuickBooks",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                } label: {
                    Label("Check QuickBooks for payments", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } header: {
            Text("Payments")
        }
    }

    private func sendReminder(to email: String) {
        let firm = firmName.isEmpty ? "" : firmName
        let body = InvoiceMath.reminderBody(
            clientName: invoice.client?.displayName ?? "there",
            number: invoice.displayNumber,
            balance: invoice.balance,
            dueDate: invoice.dueDate,
            firm: firm
        )
        if let url = InvoiceMath.reminderURL(to: email, subject: "Reminder: invoice \(invoice.displayNumber)", body: body) {
            openURL(url)
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
