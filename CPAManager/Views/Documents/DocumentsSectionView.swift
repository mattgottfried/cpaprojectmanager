import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Reusable "Documents" section embedded in client and project detail screens.
/// Pass exactly one of `client` or `project` — new documents attach to it.
struct DocumentsSectionView: View {
    var client: Client?
    var project: Project?

    @Environment(\.modelContext) private var context
    @Query private var allDocuments: [Document]

    @State private var showingScanner = false
    @State private var showingPhotosPicker = false
    @State private var showingFileImporter = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var previewDocument: Document?

    private var documents: [Document] {
        allDocuments
            .filter { document in
                if let project { return document.project?.id == project.id }
                if let client { return document.client?.id == client.id }
                return false
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func setSignature(_ document: Document, _ status: SignatureStatus) {
        document.signatureStatus = status
        switch status {
        case .none:   document.signatureSentAt = nil; document.signedAt = nil
        case .sent:   document.signatureSentAt = .now; document.signedAt = nil
        case .signed: document.signedAt = .now
        }
        try? context.save()
    }

    var body: some View {
        Section("Documents") {
            if documents.isEmpty {
                Text("No documents yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(documents) { document in
                Button {
                    previewDocument = document
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: document))
                            .foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(Format.mediumDate.string(from: document.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if document.signatureStatus != .none {
                                CapsuleBadge(
                                    text: document.signatureStatus.label,
                                    systemImage: document.signatureStatus == .signed ? "checkmark.seal.fill" : "signature",
                                    state: document.signatureStatus == .signed ? .good : .caution
                                )
                            }
                        }
                    }
                }
                .contextMenu {
                    if document.signatureStatus != .sent {
                        Button { setSignature(document, .sent) } label: { Label("Mark sent for signature", systemImage: "paperplane") }
                    }
                    if document.signatureStatus != .signed {
                        Button { setSignature(document, .signed) } label: { Label("Mark signed", systemImage: "checkmark.seal") }
                    }
                    if document.signatureStatus != .none {
                        Button { setSignature(document, .none) } label: { Label("Clear signature status", systemImage: "xmark.circle") }
                    }
                    Divider()
                    Button(role: .destructive) {
                        if let index = documents.firstIndex(where: { $0.id == document.id }) { delete(IndexSet(integer: index)) }
                    } label: { Label("Delete Document", systemImage: "trash") }
                }
            }
            .onDelete(perform: delete)

            Menu {
                #if os(iOS) && !targetEnvironment(macCatalyst)
                // VisionKit's document camera scanner has no Mac Catalyst equivalent.
                Button { showingScanner = true } label: {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
                #endif
                Button { showingPhotosPicker = true } label: {
                    Label("Choose Photo", systemImage: "photo")
                }
                Button { showingFileImporter = true } label: {
                    Label("Choose File", systemImage: "folder")
                }
            } label: {
                Label("Add Document", systemImage: "plus")
            }
        }
        #if os(iOS) && !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $showingScanner) {
            DocumentScannerView { pdfData in
                save(data: pdfData, filename: "Scan \(Format.shortDate.string(from: .now))", ext: "pdf")
            }
            .ignoresSafeArea()
        }
        #endif
        .photosPicker(isPresented: $showingPhotosPicker, selection: $selectedPhotos, maxSelectionCount: 1, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            guard let item = items.first else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    save(data: data, filename: "Photo \(Format.shortDate.string(from: .now))", ext: "jpg")
                }
                selectedPhotos = []
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $previewDocument) { document in
            DocumentPreviewView(document: document)
        }
    }

    private func icon(for document: Document) -> String {
        switch document.fileExtension.lowercased() {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        default: return "doc.fill"
        }
    }

    private func save(data: Data, filename: String, ext: String) {
        let document = Document(filename: filename, fileExtension: ext, data: data, client: client, project: project)
        context.insert(document)
        try? context.save()
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        save(data: data, filename: name, ext: ext)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(documents[index]) }
        try? context.save()
    }
}
