import SwiftUI
import SwiftData

struct InvoicesListView: View {
    @Environment(\.modelContext) private var context
    @Environment(QBOAuthService.self) private var qboAuth
    @Query(sort: \Invoice.number, order: .reverse) private var invoices: [Invoice]
    @State private var showingBuilder = false
    @State private var refreshing = false
    @State private var linkedInvoice: Invoice?
    @Environment(AppRouter.self) private var router

    private var sent: [Invoice] { invoices.filter { $0.status == .sent } }
    private var outstandingTotal: Double { sent.reduce(0) { $0 + $1.balance } }
    private var overdueTotal: Double { sent.filter(\.isOverdue).reduce(0) { $0 + $1.balance } }

    /// Overdue balances grouped by how late they are.
    private struct AgingEntry: Identifiable {
        let bucket: InvoiceMath.AgingBucket
        let total: Double
        var id: String { bucket.rawValue }
    }

    private var aging: [AgingEntry] {
        let overdue = sent.filter(\.isOverdue)
        var entries: [AgingEntry] = []
        for bucket in InvoiceMath.AgingBucket.allCases {
            let total = overdue
                .filter { InvoiceMath.agingBucket(dueDate: $0.dueDate) == bucket }
                .reduce(0) { $0 + $1.balance }
            if total > 0 { entries.append(AgingEntry(bucket: bucket, total: total)) }
        }
        return entries
    }

    var body: some View {
        List {
            if !invoices.isEmpty {
                summaryCard
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if invoices.isEmpty {
                ContentUnavailableView {
                    Label("No invoices yet", systemImage: "doc.text")
                } description: {
                    Text("Create one from unbilled time.")
                } actions: {
                    Button("New invoice") { showingBuilder = true }.buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(invoices) { invoice in
                    NavigationLink {
                        InvoiceDetailView(invoice: invoice)
                    } label: {
                        row(invoice)
                    }
                    .cardListRow()
                }
                .onDelete(perform: delete)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .navigationTitle("Invoices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingBuilder = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New invoice")
            }
            if qboAuth.isConnected {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        Task {
                            refreshing = true
                            await QBOSyncService.refreshOutstanding(auth: qboAuth, context: context, force: true)
                            refreshing = false
                        }
                    } label: {
                        Label("Check QuickBooks for payments", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(refreshing)
                }
            }
        }
        .sheet(isPresented: $showingBuilder) { InvoiceBuilderView() }
        .navigationDestination(item: $linkedInvoice) { InvoiceDetailView(invoice: $0) }
        .onAppear(perform: consumeLink)
        .onChange(of: router.pendingLink) { _, _ in consumeLink() }
    }

    private func consumeLink() {
        guard case .invoice(let id)? = router.pendingLink,
              let invoice = invoices.first(where: { $0.id == id }) else { return }
        router.pendingLink = nil
        linkedInvoice = invoice
    }

    private var summaryCard: some View {
        SectionCard(title: "Receivables", systemImage: "banknote.fill", state: overdueTotal > 0 ? .bad : .good) {
            HStack(spacing: 10) {
                StatChip(value: Format.currency(outstandingTotal), label: "Outstanding", state: .info)
                StatChip(value: Format.currency(overdueTotal), label: "Overdue", state: overdueTotal > 0 ? .bad : .neutral)
            }
            if !aging.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(aging) { entry in
                        HStack {
                            Text(entry.bucket.label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.currency(entry.total)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func row(_ invoice: Invoice) -> some View {
        let state: SemanticState = invoice.status == .paid ? .good : (invoice.isOverdue ? .bad : (invoice.status == .sent ? .info : .neutral))
        return HStack(spacing: 12) {
            StatusTile(systemImage: invoice.isOverdue ? "exclamationmark.triangle.fill" : "doc.text.fill", state: state, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(invoice.displayNumber).font(.body.weight(.semibold))
                Text(invoice.client?.displayName ?? "No client")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if invoice.status == .sent {
                    Label(
                        invoice.isOverdue ? "Overdue \(Format.relativeDay(invoice.dueDate))" : "Due \(Format.relativeDay(invoice.dueDate))",
                        systemImage: invoice.isOverdue ? "exclamationmark.triangle.fill" : "calendar"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(invoice.isOverdue ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.currency(invoice.status == .paid ? invoice.total : invoice.balance))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                InvoiceStatusBadge(status: invoice.status)
            }
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(invoice.displayNumber), \(invoice.client?.displayName ?? "no client")")
        .accessibilityValue("\(invoice.status.label), \(Format.currency(invoice.balance)) due\(invoice.isOverdue ? ", overdue" : "")")
        .accessibilityHint("Opens the invoice")
    }

    private func delete(_ offsets: IndexSet) {
        guard let allEntries = try? context.fetch(FetchDescriptor<TimeEntry>()) else {
            for index in offsets { context.delete(invoices[index]) }
            try? context.save()
            return
        }
        for index in offsets {
            let invoice = invoices[index]
            let entryIDs = Set(invoice.lineList.compactMap(\.timeEntryID))
            for entry in allEntries where entryIDs.contains(entry.id) {
                entry.invoiceID = nil
            }
            context.delete(invoice)
        }
        try? context.save()
    }
}
