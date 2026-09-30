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
    @State private var showingDriveBrowser = false
    @State private var filingNotice: String?
    @State private var isFiling = false
    @Environment(GoogleAuthService.self) private var google
    @Environment(\.openURL) private var openURL

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
            if isFiling {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Filing in Google Drive…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(documents) { document in
                Button {
                    if document.isDriveLink, let url = URL(string: document.driveURL) {
                        openURL(url)
                    } else {
                        previewDocument = document
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: document))
                            .foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(document.isDriveLink ? "Google Drive · \(Format.mediumDate.string(from: document.createdAt))"
                                                      : Format.mediumDate.string(from: document.createdAt))
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
                    if DriveFilingPlan.canMove(hasData: !document.data.isEmpty, isDriveLink: document.isDriveLink) {
                        Button { moveToDrive([document]) } label: { Label("Move to Google Drive", systemImage: "externaldrive.badge.plus") }
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
                Button { showingDriveBrowser = true } label: {
                    Label("Link from Google Drive…", systemImage: "externaldrive.badge.plus")
                }
                if !localDocuments.isEmpty {
                    Button { moveToDrive(localDocuments) } label: {
                        Label("Move \(localDocuments.count) in-app file\(localDocuments.count == 1 ? "" : "s") to Drive", systemImage: "arrow.up.doc")
                    }
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
        .alert(filingNotice ?? "", isPresented: Binding(get: { filingNotice != nil }, set: { if !$0 { filingNotice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .sheet(item: $previewDocument) { document in
            DocumentPreviewView(document: document)
        }
        .sheet(isPresented: $showingDriveBrowser) {
            DriveBrowserView(mode: .files, startFolder: startFolder, onPickFiles: { picked in
                DriveLinker.link(picked, client: client, project: project, context: context)
            })
        }
    }

    /// Opens the browser inside the job's or client's chosen Drive folder, if there is one.
    private var startFolder: DrivePath.Crumb? {
        if let project, !project.driveFolderID.isEmpty { return DrivePath.Crumb(id: project.driveFolderID, name: project.driveFolderName) }
        if let client, !client.driveFolderID.isEmpty { return DrivePath.Crumb(id: client.driveFolderID, name: client.driveFolderName) }
        return nil
    }

    private func icon(for document: Document) -> String {
        if document.isDriveLink { return "externaldrive.fill" }
        switch document.fileExtension.lowercased() {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        default: return "doc.fill"
        }
    }

    /// The client this section belongs to, for wording notices.
    private var ownerName: String { client?.displayName ?? project?.client?.displayName ?? "" }

    /// Adds the file and, when Drive can take it, files it there and keeps only the link.
    private func save(data: Data, filename: String, ext: String) {
        Task {
            isFiling = true
            let result = await DriveFiling.add(
                data: data, title: filename, fileExtension: ext, kind: .upload,
                client: client, project: project, auth: google, context: context
            )
            isFiling = false
            if let reason = result.outcome.reason {
                filingNotice = DriveFilingPlan.notice(for: reason, clientName: ownerName)
            }
        }
    }

    private var localDocuments: [Document] {
        documents.filter { DriveFilingPlan.canMove(hasData: !$0.data.isEmpty, isDriveLink: $0.isDriveLink) }
    }

    private func moveToDrive(_ items: [Document]) {
        Task {
            isFiling = true
            let result = await DriveFiling.moveAll(items, auth: google, context: context)
            isFiling = false
            if let reason = result.reason {
                filingNotice = DriveFilingPlan.notice(for: reason, clientName: ownerName)
            } else if result.moved > 0 {
                filingNotice = result.moved == 1 ? "Moved 1 document to Google Drive." : "Moved \(result.moved) documents to Google Drive."
            }
        }
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
