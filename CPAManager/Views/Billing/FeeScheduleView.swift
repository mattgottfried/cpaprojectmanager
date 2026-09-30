import SwiftUI
import SwiftData

/// Your standard prices, reused when building quotes.
struct FeeScheduleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FeeItem.sortIndex) private var items: [FeeItem]
    @State private var editing: FeeItem?
    @State private var showingNew = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No fees yet", systemImage: "tag")
                } description: {
                    Text("Add your standard prices — a 1040, monthly bookkeeping, an hourly rate — and pick from them when you write a quote.")
                } actions: {
                    Button("Add a fee") { showingNew = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(items) { item in
                Button { editing = item } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).foregroundStyle(.primary)
                            if !item.detail.isEmpty {
                                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(item.isHourly ? "\(Format.currency(item.unitPrice))/hr" : Format.currency(item.unitPrice))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(items[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Fee Schedule")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add fee")
            }
        }
        .sheet(isPresented: $showingNew) { FeeItemEditor(item: nil, nextSortIndex: (items.map(\.sortIndex).max() ?? -1) + 1) }
        .sheet(item: $editing) { FeeItemEditor(item: $0, nextSortIndex: $0.sortIndex) }
    }
}

struct FeeItemEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var item: FeeItem?
    var nextSortIndex: Int

    @State private var name = ""
    @State private var detail = ""
    @State private var price = 0.0
    @State private var isHourly = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. 1040 individual return)", text: $name)
                    TextField("Description (optional)", text: $detail)
                }
                Section {
                    LabeledContent(isHourly ? "Rate per hour" : "Price") {
                        TextField("Amount", value: $price, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                    }
                    Toggle("Billed hourly", isOn: $isHourly)
                } footer: {
                    Text("Hourly fees ask for hours when you add them to a quote; flat fees are added once.")
                }
            }
            .navigationTitle(item == nil ? "New Fee" : "Edit Fee")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                guard let item else { return }
                name = item.name; detail = item.detail; price = item.unitPrice; isHourly = item.isHourly
            }
        }
    }

    private func save() {
        if let item {
            item.name = name; item.detail = detail; item.unitPrice = max(0, price); item.isHourly = isHourly
        } else {
            context.insert(FeeItem(name: name, detail: detail, unitPrice: max(0, price), isHourly: isHourly, sortIndex: nextSortIndex))
        }
        try? context.save()
        dismiss()
    }
}
