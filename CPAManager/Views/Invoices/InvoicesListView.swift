import SwiftUI
import SwiftData

struct InvoicesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Invoice.number, order: .reverse) private var invoices: [Invoice]
    @State private var showingBuilder = false

    private var outstandingTotal: Double {
        invoices.filter { $0.status != .paid }.reduce(0) { $0 + $1.total }
    }

    var body: some View {
        List {
            if !invoices.isEmpty {
                Section {
                    LabeledContent("Outstanding", value: Format.currency(outstandingTotal))
                }
            }

            if invoices.isEmpty {
                Text("No invoices yet. Create one from unbilled time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invoices) { invoice in
                    NavigationLink {
                        InvoiceDetailView(invoice: invoice)
                    } label: {
                        row(invoice)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Invoices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingBuilder = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingBuilder) { InvoiceBuilderView() }
    }

    private func row(_ invoice: Invoice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.displayNumber).font(.subheadline.weight(.medium))
                Text(invoice.client?.displayName ?? "No client")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.currency(invoice.total)).font(.subheadline.monospacedDigit())
                InvoiceStatusBadge(status: invoice.status)
            }
        }
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
