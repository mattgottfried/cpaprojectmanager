import SwiftUI
import SwiftData

/// "Google Drive" section for a client or job: the folder where its documents live, its most
/// recently changed files, and shortcuts to open them. Read-only — nothing is uploaded.
struct DriveFolderSection: View {
    @Binding var folderID: String
    @Binding var folderName: String
    /// "client" / "job", for the wording.
    var subject = "client"
    /// When set, a folder can be created with the standard structure (clients only).
    var createFolder: (() async -> DriveFolders.CreateResult)? = nil

    @Environment(GoogleAuthService.self) private var auth
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var showingBrowser = false
    @State private var recent: [DriveFile] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var creating = false

    var body: some View {
        Section {
            if folderID.isEmpty {
                if let createFolder, auth.isConnected, !DriveFolders.rootID.isEmpty {
                    Button {
                        Task {
                            creating = true
                            let result = await createFolder()
                            creating = false
                            switch result {
                            case .failed(let message): errorText = message
                            default: errorText = nil
                            }
                        }
                    } label: {
                        Label(creating ? "Creating…" : "Create \(subject)'s folder in Drive", systemImage: "folder.badge.plus")
                    }
                    .disabled(creating)
                }
                Button { showingBrowser = true } label: {
                    Label("Choose \(subject)'s Drive folder…", systemImage: "externaldrive.badge.plus")
                }
            } else {
                Button { openURL(DriveLinks.folderURL(id: folderID)) } label: {
                    HStack {
                        Label(folderName.isEmpty ? "Drive folder" : folderName, systemImage: "folder.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    }
                }

                if !auth.isConnected {
                    Text("Connect Google in Settings ▸ Google to see the files in this folder.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if loading && recent.isEmpty {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                } else if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.color(.caution)).textSelection(.enabled)
                } else if recent.isEmpty {
                    Text("Nothing in this folder yet.").font(.footnote).foregroundStyle(.secondary)
                }

                ForEach(recent) { file in
                    Button {
                        if file.isFolder { openURL(DriveLinks.folderURL(id: file.id)) }
                        else if let url = DriveLinks.fileURL(file) { openURL(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: DriveFileKind.symbol(for: file))
                                .foregroundStyle(file.isFolder ? Theme.brand : Color.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).foregroundStyle(.primary).lineLimit(1)
                                if let modified = file.modifiedTime {
                                    Text("Changed \(modified.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Menu {
                    Button { showingBrowser = true } label: { Label("Change folder…", systemImage: "folder.badge.gearshape") }
                    Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    Button(role: .destructive) { clear() } label: { Label("Remove folder link", systemImage: "link.badge.plus") }
                } label: {
                    Label("Folder options", systemImage: "ellipsis.circle")
                }
            }
        } header: {
            Text("Google Drive")
        } footer: {
            Text("Documents live in Drive; the app links to them and files new ones here. Newest changes first.")
        }
        .sheet(isPresented: $showingBrowser) {
            DriveBrowserView(
                mode: .folder,
                startFolder: folderID.isEmpty ? nil : DrivePath.Crumb(id: folderID, name: folderName),
                onPickFolder: { crumb in
                    folderID = crumb.id
                    folderName = crumb.name
                    try? context.save()
                }
            )
        }
        .task(id: folderID) { await load() }
    }

    private func clear() {
        folderID = ""
        folderName = ""
        recent = []
        errorText = nil
        try? context.save()
    }

    private func load() async {
        guard auth.isConnected, !folderID.isEmpty, let query = DriveQuery.children(of: folderID) else {
            recent = []
            return
        }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let page = try await GoogleAPI(auth: auth).driveFiles(query: query, pageSize: 8, orderBy: "modifiedTime desc")
            recent = page.files ?? []
        } catch let GoogleError.http(status, body) {
            errorText = DriveErrors.message(status: status, body: body)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
