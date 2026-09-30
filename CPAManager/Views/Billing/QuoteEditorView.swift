import SwiftUI
import SwiftData

struct QuoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.firmName) private var firmName = ""
    @AppStorage(SettingsKeys.firmContact) private var firmContact = ""

    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \FeeItem.sortIndex) private var feeItems: [FeeItem]
    @Query private var allQuotes: [Quote]

    var quote: Quote?

    @State private var clientID: UUID?
    @State private var status: QuoteStatus = .draft
    @State private var hasValidUntil = true
    @State private var validUntil = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var lines: [QuoteLine] = []
    @State private var notes = ""
    @State private var loaded = false
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var message: String?
    @Environment(GoogleAuthService.self) private var google

    private var client: Client? { clientID.flatMap { id in clients.first { $0.id == id } } }
    private var cleanedLines: [QuoteLine] { QuoteMath.cleaned(lines) }
    private var canSave: Bool { client != nil && !cleanedLines.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Client", selection: $clientID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(clients) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(QuoteStatus.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Valid until", isOn: $hasValidUntil.animation())
                    if hasValidUntil {
                        DatePicker("Date", selection: $validUntil, displayedComponents: .date)
                    }
                }

                Section("Lines") {
                    ForEach($lines) { $line in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Description", text: $line.detail)
                            HStack {
                                TextField("Qty", value: $line.quantity, format: .number)
                                    .frame(maxWidth: 70)
                                    .decimalKeyboard()
                                Text("×").foregroundStyle(.secondary)
                                TextField("Rate", value: $line.rate, format: .currency(code: "USD"))
                                    .decimalKeyboard()
                                Spacer()
                                Text(Format.currency(line.amount)).foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }

                    Button { lines.append(QuoteLine(detail: "")) } label: { Label("Add line", systemImage: "plus") }
                    if !feeItems.isEmpty {
                        Menu {
                            ForEach(feeItems) { item in
                                Button("\(item.name) — \(Format.currency(item.unitPrice))\(item.isHourly ? "/hr" : "")") { add(item) }
                            }
                        } label: { Label("Add from fee schedule", systemImage: "tag") }
                    }
                    LabeledContent("Total") {
                        Text(Format.currency(QuoteMath.total(cleanedLines))).font(.headline)
                    }
                }

                Section("Notes") {
                    TextField("Terms, assumptions…", text: $notes, axis: .vertical).lineLimit(2...6)
                }

                if quote != nil {
                    Section {
                        Button { exportPDF() } label: { Label("Save PDF to client & share", systemImage: "square.and.arrow.up") }
                            .disabled(!canSave)
                        Button { createInvoice() } label: { Label("Create draft invoice", systemImage: "doc.badge.plus") }
                            .disabled(!canSave || quote?.invoiceID != nil)
                    } footer: {
                        if quote?.invoiceID != nil { Text("This quote has already been turned into an invoice.") }
                    }
                }
            }
            .navigationTitle(quote?.displayNumber ?? "New Quote")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { _ = save(); dismiss() }.disabled(!canSave) }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showingShare) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
            .onAppear(perform: loadOnce)
        }
        .macSheetFrame()
    }

    // MARK: Lines

    private func add(_ item: FeeItem) {
        let detail = item.detail.isEmpty ? item.name : "\(item.name) — \(item.detail)"
        // Hourly items start at 1 hour; edit the quantity to the estimate.
        lines.append(QuoteLine(detail: detail, quantity: 1, rate: item.unitPrice))
    }

    // MARK: Load / save

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        guard let quote else { return }
        clientID = quote.client?.id
        status = quote.status
        hasValidUntil = quote.validUntil != nil
        validUntil = quote.validUntil ?? validUntil
        lines = quote.lines
        notes = quote.notes
    }

    @discardableResult
    private func save() -> Quote? {
        guard let client else { return nil }
        let target: Quote
        if let quote {
            target = quote
        } else {
            target = Quote(number: QuoteMath.nextNumber(existing: allQuotes.map(\.number)))
            context.insert(target)
        }
        target.client = client
        target.status = status
        target.validUntil = hasValidUntil ? validUntil : nil
        target.lines = cleanedLines
        target.notes = notes
        try? context.save()
        return target
    }

    // MARK: Actions

    private func exportPDF() {
        guard let saved = save(), let client = saved.client else { return }
        let body = QuoteText.body(
            number: saved.number, clientName: client.displayName, firmName: firmName,
            date: saved.issueDate, validUntil: saved.validUntil, lines: saved.lines, notes: saved.notes,
            formatDate: { Format.mediumDate.string(from: $0) },
            formatMoney: { Format.currency($0) }
        )
        let data = LetterPDF.data(body: body, firmName: firmName, firmContact: firmContact, signatureBlock: true, clientName: client.displayName)
        guard !data.isEmpty else { message = "Couldn't create the PDF."; return }
        let filename = "Quote \(saved.displayNumber) - \(client.displayName)"
        let safe = filename.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        if (try? data.write(to: url)) != nil {
            shareURL = url
            showingShare = true
        }
        Task {
            let result = await DriveFiling.add(
                data: data, title: "Quote \(saved.displayNumber)", fileExtension: "pdf", kind: .quote, client: client, project: nil,
                auth: google, context: context
            )
            if let reason = result.outcome.reason {
                message = DriveFilingPlan.notice(for: reason, clientName: client.displayName)
            }
        }
    }

    private func createInvoice() {
        guard let saved = save() else { return }
        if let invoice = QuoteService.convertToInvoice(saved, context: context) {
            SnapshotBuilder.rebuild(context: context)
            status = .accepted
            message = "Created draft invoice \(invoice.displayNumber). Find it under Invoices."
        } else {
            message = "This quote needs a client and at least one line."
        }
    }
}
