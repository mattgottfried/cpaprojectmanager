import SwiftUI
import SwiftData

struct QuotesListView: View {
    @Query(sort: \Quote.createdAt, order: .reverse) private var quotes: [Quote]
    @Environment(\.modelContext) private var context
    @State private var editing: Quote?
    @State private var showingNew = false

    var body: some View {
        List {
            if quotes.isEmpty {
                ContentUnavailableView {
                    Label("No quotes yet", systemImage: "doc.plaintext")
                } description: {
                    Text("Price a job before you start. Accepted quotes turn into a draft invoice in one tap.")
                } actions: {
                    Button("New quote") { showingNew = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(quotes) { quote in
                Button { editing = quote } label: { row(quote) }
                    .buttonStyle(.plain)
                    .cardListRow()
                    .deleteMenu("Delete Quote") { context.delete(quote); try? context.save() }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(quotes[index]) }
                try? context.save()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .navigationTitle("Quotes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New quote")
            }
        }
        .sheet(isPresented: $showingNew) { QuoteEditorView(quote: nil) }
        .sheet(item: $editing) { QuoteEditorView(quote: $0) }
    }

    private func row(_ quote: Quote) -> some View {
        let expired = QuoteMath.isExpired(validUntil: quote.validUntil, status: quote.status)
        return HStack(spacing: 12) {
            StatusTile(systemImage: "doc.plaintext", state: quote.status.state)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(quote.displayNumber) · \(quote.client?.displayName ?? "No client")")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(expired ? "Expired \(Format.shortDate.string(from: quote.validUntil ?? .now))" : "Issued \(Format.shortDate.string(from: quote.issueDate))")
                    .font(.caption)
                    .foregroundStyle(expired ? Theme.color(.caution) : .secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.currency(quote.total)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                CapsuleBadge(text: quote.status.label, systemImage: nil, state: quote.status.state)
            }
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quote.displayNumber) for \(quote.client?.displayName ?? "no client")")
        .accessibilityValue("\(quote.status.label), \(Format.currency(quote.total))")
    }
}
