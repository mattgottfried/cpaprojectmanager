import SwiftUI
import SwiftData
import Charts

/// Business expenses with receipts, totalled by category for the year.
struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var showingNew = false
    @State private var editing: Expense?
    @State private var toast: UndoToastState?

    private var yearExpenses: [Expense] {
        guard let range = ExpenseMath.yearRange(year) else { return [] }
        return expenses.filter { range.contains($0.date) }
    }

    private var totals: [ExpenseMath.CategoryTotal] {
        ExpenseMath.totalsByCategory(expenses.map {
            ExpenseMath.Row(category: $0.category, date: $0.date, amount: $0.amount, deductiblePercent: $0.deductiblePercent)
        }, in: ExpenseMath.yearRange(year))
    }

    private var yearTotal: Double { totals.reduce(0) { $0 + $1.total } }
    private var yearDeductible: Double { totals.reduce(0) { $0 + $1.deductible } }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        let seen = Set(expenses.map { Calendar.current.component(.year, from: $0.date) })
        return Array(seen.union([current])).sorted(by: >)
    }

    var body: some View {
        List {
            Picker("Year", selection: $year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .cardListRow()

            if !yearExpenses.isEmpty {
                summaryCard.cardListRow()
            }

            if yearExpenses.isEmpty {
                ContentUnavailableView {
                    Label("No expenses for \(String(year))", systemImage: "creditcard")
                } description: {
                    Text("Log software, travel, fees and more — attach a receipt photo so it's there at tax time.")
                } actions: {
                    Button("Add an expense") { showingNew = true }.buttonStyle(.borderedProminent)
                }
                .cardListRow()
            }

            ForEach(yearExpenses) { expense in
                Button { editing = expense } label: { row(expense) }
                    .buttonStyle(.plain)
                    .cardListRow()
                    .swipeActions {
                        Button(role: .destructive) { delete(expense) } label: { Label("Delete", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground)
        .macReadableWidth()
        .navigationTitle("Expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add expense")
            }
        }
        .sheet(isPresented: $showingNew) { ExpenseFormView() }
        .sheet(item: $editing) { ExpenseFormView(expense: $0) }
        .undoToast($toast)
    }

    private var summaryCard: some View {
        SectionCard(title: "\(String(year)) by category", systemImage: "chart.bar.fill", state: .info) {
            HStack(spacing: 10) {
                StatChip(value: Format.currency(yearTotal), label: "Spent", state: .caution)
                StatChip(value: Format.currency(yearDeductible), label: "Deductible", state: .good)
            }
            Chart(totals.prefix(6)) { item in
                BarMark(x: .value("Amount", item.total), y: .value("Category", item.category.label))
                    .foregroundStyle(Theme.brand)
            }
            .frame(height: CGFloat(min(6, totals.count)) * 30 + 20)
            .accessibilityLabel("Bar chart of expenses by category")
            ForEach(totals) { item in
                HStack {
                    Label(item.category.label, systemImage: item.category.systemImage).font(.caption)
                    Spacer()
                    Text(Format.currency(item.total)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func row(_ expense: Expense) -> some View {
        HStack(spacing: 12) {
            StatusTile(systemImage: expense.category.systemImage, state: .caution, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(expense.vendor.isEmpty ? expense.category.label : expense.vendor)
                    .font(.body.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(expense.date.formatted(date: .abbreviated, time: .omitted))
                    if !expense.vendor.isEmpty { Text("· \(expense.category.label)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if expense.hasReceipt { Label("Receipt", systemImage: "paperclip").font(.caption2).foregroundStyle(.secondary) }
                    if expense.deductiblePercent < 100 { CapsuleBadge(text: "\(expense.deductiblePercent)% deductible", state: .neutral) }
                    if let client = expense.client { Label(client.displayName, systemImage: "person.fill").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            Text(Format.currency(expense.amount)).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .rowCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(expense.vendor.isEmpty ? expense.category.label : expense.vendor)
        .accessibilityValue("\(Format.currency(expense.amount)), \(expense.category.label), \(expense.date.formatted(date: .abbreviated, time: .omitted))\(expense.hasReceipt ? ", has receipt" : "")")
        .accessibilityHint("Opens the expense")
    }

    private func delete(_ expense: Expense) {
        // Keep a copy of every field (receipt included) so Undo restores it exactly.
        let copy = Expense(amount: expense.amount, date: expense.date, category: expense.category, vendor: expense.vendor, note: expense.note, client: expense.client)
        copy.deductiblePercent = expense.deductiblePercent
        copy.receiptData = expense.receiptData
        copy.receiptExtension = expense.receiptExtension
        context.delete(expense)
        try? context.save()
        toast = UndoToastState(message: "Deleted expense", systemImage: "trash") {
            context.insert(copy)
            try? context.save()
        }
    }
}
