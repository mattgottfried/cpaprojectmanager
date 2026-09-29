import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct ExpenseFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Client.name) private var clients: [Client]

    var expense: Expense?

    @State private var amount: Double = 0
    @State private var date = Date.now
    @State private var category: ExpenseCategory = .software
    @State private var vendor = ""
    @State private var note = ""
    @State private var deductiblePercent = 100
    @State private var client: Client?
    @State private var receiptData = Data()
    @State private var receiptExtension = ""
    @State private var photo: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var showingPreview = false

    private var canSave: Bool { InvoiceMath.cents(amount) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("Amount", value: $amount, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    TextField("Vendor", text: $vendor)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { c in Label(c.label, systemImage: c.systemImage).tag(c) }
                    }
                    .onChange(of: category) { _, new in
                        if expense == nil { deductiblePercent = new.defaultDeductiblePercent }
                    }
                }

                Section {
                    Stepper("Deductible: \(deductiblePercent)%", value: $deductiblePercent, in: 0...100, step: 5)
                    LabeledContent("Deductible amount", value: Format.currency(ExpenseMath.deductible(amount: amount, percent: deductiblePercent)))
                        .font(.caption)
                } footer: {
                    Text("Meals start at 50% — adjust for your situation and current rules.")
                }

                Section("Reimbursable by a client?") {
                    Picker("Client", selection: $client) {
                        Text("No").tag(Client?.none)
                        ForEach(clients) { c in Text(c.displayName).tag(Client?.some(c)) }
                    }
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                }

                Section("Receipt") {
                    if receiptData.isEmpty {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Choose a photo", systemImage: "photo")
                        }
                        Button { showingFileImporter = true } label: { Label("Choose a file (PDF or image)", systemImage: "folder") }
                    } else {
                        Button { showingPreview = true } label: { Label("View receipt", systemImage: "doc.text.magnifyingglass") }
                        Button(role: .destructive) { receiptData = Data(); receiptExtension = "" } label: {
                            Label("Remove receipt", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        receiptData = data
                        receiptExtension = "jpg"
                    }
                    photo = nil
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    receiptData = data
                    receiptExtension = url.pathExtension.isEmpty ? "pdf" : url.pathExtension.lowercased()
                }
            }
            .sheet(isPresented: $showingPreview) {
                // An unsaved Document is enough for the shared previewer.
                DocumentPreviewView(document: Document(
                    filename: vendor.isEmpty ? "Receipt" : "Receipt – \(vendor)",
                    fileExtension: receiptExtension.isEmpty ? "jpg" : receiptExtension,
                    data: receiptData
                ))
            }
        }
    }

    private func load() {
        guard let expense else { return }
        amount = expense.amount
        date = expense.date
        category = expense.category
        vendor = expense.vendor
        note = expense.note
        deductiblePercent = expense.deductiblePercent
        client = expense.client
        receiptData = expense.receiptData
        receiptExtension = expense.receiptExtension
    }

    private func save() {
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense()
            context.insert(target)
        }
        target.amount = Double(InvoiceMath.cents(amount)) / 100
        target.date = date
        target.category = category
        target.vendor = vendor.trimmingCharacters(in: .whitespaces)
        target.note = note
        target.deductiblePercent = deductiblePercent
        target.client = client
        target.receiptData = receiptData
        target.receiptExtension = receiptExtension
        try? context.save()
        dismiss()
    }
}
