import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Spreadsheet exports (CSV) and a full JSON backup that doesn't depend on iCloud.
struct ExportBackupView: View {
    @Environment(\.modelContext) private var context

    @State private var includeFiles = true
    @State private var shareItems: [Any] = []
    @State private var showingShare = false
    @State private var showingImporter = false
    @State private var pendingBackup: BackupFile?
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach(ExportService.Dataset.allCases) { dataset in
                    Button { share(dataset) } label: {
                        Label(dataset.title, systemImage: dataset.systemImage)
                    }
                }
                Button { shareAll() } label: {
                    Label("Export everything (7 files)", systemImage: "square.and.arrow.up.on.square")
                }
            } header: {
                Text("Spreadsheets (CSV)")
            } footer: {
                Text("Opens in Excel, Numbers, or Google Sheets. Cells that start with = + - @ are escaped so a spreadsheet can't run them as formulas.")
            }

            Section {
                Toggle("Include documents and receipts", isOn: $includeFiles)
                Button { makeBackup() } label: {
                    Label("Create backup file", systemImage: "externaldrive.badge.plus")
                }
                Button { showingImporter = true } label: {
                    Label("Restore from a backup…", systemImage: "arrow.counterclockwise.circle")
                }
            } header: {
                Text("Backup & restore")
            } footer: {
                Text("A backup is one JSON file with all your clients, work, invoices, time and expenses. Restoring merges it in: anything already here is left untouched, and nothing is deleted.")
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad) }
            }
        }
        .navigationTitle("Export & Backup")
        .sheet(isPresented: $showingShare) { ShareSheet(items: shareItems) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { result in
            loadBackup(result)
        }
        .sheet(isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
            if let file = pendingBackup { restorePreview(file) }
        }
    }

    // MARK: Export

    private func share(_ dataset: ExportService.Dataset) {
        guard let url = ExportService.file(dataset, context: context) else {
            errorMessage = "Couldn't write the file."
            return
        }
        present([url])
    }

    private func shareAll() {
        let urls = ExportService.Dataset.allCases.compactMap { ExportService.file($0, context: context) }
        guard !urls.isEmpty else { errorMessage = "Couldn't write the files."; return }
        present(urls)
    }

    private func makeBackup() {
        guard let url = BackupService.exportFile(context: context, includeFiles: includeFiles) else {
            errorMessage = "Couldn't create the backup."
            return
        }
        present([url])
    }

    private func present(_ items: [Any]) {
        errorMessage = nil
        message = nil
        shareItems = items
        showingShare = true
    }

    // MARK: Restore

    private func loadBackup(_ result: Result<[URL], Error>) {
        errorMessage = nil
        message = nil
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingBackup = try BackupService.decode(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restorePreview(_ file: BackupFile) -> some View {
        NavigationStack {
            Form {
                Section("This backup contains") {
                    LabeledContent("Made", value: file.createdAt.formatted(date: .abbreviated, time: .shortened))
                    ForEach(file.summary, id: \.label) { line in
                        LabeledContent(line.label, value: "\(line.count)")
                    }
                }
                Section {
                    Text("Only records that aren't already on this device are added. Nothing here is changed or deleted.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Restore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pendingBackup = nil } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge in") {
                        let result = BackupService.restore(file, into: context)
                        pendingBackup = nil
                        message = "Restored \(result.inserted) new record\(result.inserted == 1 ? "" : "s"); \(result.skippedExisting) already here."
                    }
                }
            }
        }
        .macSheetFrame()
        .presentationDetents([.medium, .large])
    }
}
