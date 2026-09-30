import SwiftUI
import SwiftData

/// Finds and fixes the messes that syncing between devices can leave behind.
struct DataHealthView: View {
    @Environment(\.modelContext) private var context
    @State private var report = DataHealthReport()
    @State private var scanned = false
    @State private var confirmTimers = false

    var body: some View {
        Form {
            if scanned && report.isHealthy {
                Section { Label("Everything looks consistent.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.color(.good)) }
            }

            if !report.duplicateInvoiceNumbers.isEmpty {
                Section {
                    Text("Invoice numbers used more than once: " + report.duplicateInvoiceNumbers.map { "#\($0)" }.joined(separator: ", "))
                    if !report.renumbers.isEmpty {
                        Button("Renumber \(report.renumbers.count) duplicate\(report.renumbers.count == 1 ? "" : "s")") {
                            DataHealthService.renumberInvoices(report, context: context)
                            scan()
                        }
                    }
                    if !report.unfixableInvoiceIDs.isEmpty {
                        Text("\(report.unfixableInvoiceIDs.count) duplicate\(report.unfixableInvoiceIDs.count == 1 ? " is" : "s are") already in QuickBooks; fix those there or by hand.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Duplicate invoice numbers") } footer: {
                    Text("Happens when two devices create an invoice before syncing. The earliest keeps its number; later ones get new numbers.")
                }
            }

            if !report.duplicateTemplateIDs.isEmpty {
                Section {
                    Button("Remove \(report.duplicateTemplateIDs.count) duplicate template\(report.duplicateTemplateIDs.count == 1 ? "" : "s")") {
                        DataHealthService.removeDuplicateTemplates(report, context: context)
                        scan()
                    }
                } header: { Text("Duplicate templates") } footer: {
                    Text("Identical copies (same name and steps) that nothing uses — usually the default templates seeded on two devices.")
                }
            }

            if !report.duplicateClientIDs.isEmpty {
                Section {
                    Text("\(report.duplicateClientIDs.count) clients share an email address with another client. Review them in Clients and delete or merge by hand.")
                        .font(.footnote)
                } header: { Text("Possible duplicate clients") }
            }

            if !report.staleTimerIDs.isEmpty {
                Section {
                    Button("End \(report.staleTimerIDs.count) forgotten timer\(report.staleTimerIDs.count == 1 ? "" : "s")…") { confirmTimers = true }
                } header: { Text("Timers running a very long time") } footer: {
                    Text("Ends them one hour after they started so they don't bill days of time. Edit the entry afterwards if that's wrong.")
                }
            }

            Section {
                Button("Scan again", action: scan)
            }
        }
        .navigationTitle("Data Health")
        .onAppear(perform: scan)
        .confirmationDialog("End forgotten timers?", isPresented: $confirmTimers, titleVisibility: .visible) {
            Button("End timers") {
                DataHealthService.stopStaleTimers(report, context: context)
                scan()
            }
        }
    }

    private func scan() {
        report = DataHealthService.scan(context: context)
        scanned = true
    }
}
