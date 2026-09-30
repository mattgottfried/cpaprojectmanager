import SwiftUI
import SwiftData

/// Record a full or partial payment against an invoice.
struct RecordPaymentSheet: View {
    let invoice: Invoice
    /// Reports the recorded payment so the presenter can offer undo.
    var onRecorded: ((Payment) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double = 0
    @State private var date = Date.now
    @State private var method: PaymentMethod = .check
    @State private var note = ""

    private var isValid: Bool { InvoiceMath.cents(amount) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Balance due", value: Format.currency(invoice.balance))
                    LabeledContent("Amount received") {
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                    }
                    Button("Full balance") { amount = invoice.balance }
                        .font(.caption)
                }
                Section {
                    DatePicker("Received", selection: $date, in: ...Date.now, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(PaymentMethod.allCases.filter { $0 != .quickbooks }) { m in
                            Label(m.label, systemImage: m.systemImage).tag(m)
                        }
                    }
                    TextField("Note (check #, reference)", text: $note)
                }
            }
            .navigationTitle("Record Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
            .onAppear { amount = invoice.balance }
        }
        .macSheetFrame()
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let payment = invoice.recordPayment(amount, on: date, method: method, note: note)
        try? context.save()
        onRecorded?(payment)
        dismiss()
    }
}
