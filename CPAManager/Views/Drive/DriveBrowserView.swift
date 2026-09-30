import SwiftUI

/// Browses Google Drive (read-only) to pick a folder or link files. Files are never copied
/// or moved.
struct DriveBrowserView: View {
    enum Mode { case folder, files }

    let mode: Mode
    var startFolder: DrivePath.Crumb? = nil
    var onPickFolder: (DrivePath.Crumb) -> Void = { _ in }
    var onPickFiles: ([DriveFile]) -> Void = { _ in }

    @Environment(GoogleAuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var path = DrivePath()
    @State private var files: [DriveFile] = []
    @State private var nextPage: String?
    @State private var loading = false
    @State private var errorText: String?
    @State private var search = ""
    @State private var picked: [String: DriveFile] = [:]
    @State private var started = false

    private struct LoadKey: Equatable {
        var folder: String
        var query: String
    }

    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isConnected {
                    ContentUnavailableView(
                        "Google isn't connected",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("Connect Google in Settings ▸ Google, then come back.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle(mode == .folder ? "Choose Folder" : "Link Files")
            .inlineNavigationTitle()
            .searchable(text: $search, prompt: "Search Drive")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    switch mode {
                    case .folder:
                        Button("Use This Folder") {
                            onPickFolder(path.current)
                            dismiss()
                        }
                        .disabled(path.current.id == DrivePath.root.id)
                    case .files:
                        Button(picked.isEmpty ? "Link" : "Link \(picked.count)") {
                            onPickFiles(DriveFileKind.sorted(Array(picked.values)))
                            dismiss()
                        }
                        .disabled(picked.isEmpty)
                    }
                }
            }
            .onAppear {
                guard !started else { return }
                started = true
                path = DrivePath(startingIn: startFolder)
            }
            .task(id: LoadKey(folder: path.current.id, query: search)) {
                guard auth.isConnected else { return }
                if isSearching { try? await Task.sleep(nanoseconds: 350_000_000) }
                guard !Task.isCancelled else { return }
                await load(reset: true)
            }
        }
        .macSheetFrame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 640)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        List {
            if !isSearching {
                Section {
                    HStack(spacing: 8) {
                        if path.canGoUp {
                            Button { path.up() } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Up one folder")
                        }
                        Image(systemName: "folder.fill").foregroundStyle(Theme.brand)
                        Text(path.crumbs.map(\.name).joined(separator: " › "))
                            .font(.subheadline).lineLimit(1).truncationMode(.head)
                    }
                }
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(Theme.color(.bad)).textSelection(.enabled)
            }

            if loading && files.isEmpty {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            } else if files.isEmpty && errorText == nil {
                Text(isSearching ? "Nothing matches." : "This folder is empty.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            ForEach(files) { file in row(file) }

            if nextPage != nil {
                Button("Load more") { Task { await load(reset: false) } }
                    .disabled(loading)
            }
        }
    }

    @ViewBuilder
    private func row(_ file: DriveFile) -> some View {
        Button {
            tap(file)
        } label: {
            HStack(spacing: 10) {
                if mode == .files, !file.isFolder {
                    Image(systemName: picked[file.id] != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(picked[file.id] != nil ? Theme.brand : Color.secondary)
                }
                Image(systemName: DriveFileKind.symbol(for: file))
                    .foregroundStyle(file.isFolder ? Theme.brand : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).foregroundStyle(.primary).lineLimit(1)
                    if let modified = file.modifiedTime {
                        Text(modified.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if file.isFolder {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked[file.id] != nil ? .isSelected : [])
    }

    private func tap(_ file: DriveFile) {
        if file.isFolder {
            search = ""
            path.open(file)
        } else if mode == .files {
            if picked[file.id] != nil { picked[file.id] = nil } else { picked[file.id] = file }
        }
    }

    // MARK: Loading

    private func load(reset: Bool) async {
        let base: String?
        if isSearching {
            base = DriveQuery.search(search)
        } else {
            base = DriveQuery.children(of: path.current.id)
        }
        guard var query = base else { return }
        if mode == .folder { query = DriveQuery.foldersOnly(query) }

        loading = true
        errorText = nil
        if reset { files = []; nextPage = nil }
        defer { loading = false }
        do {
            let page = try await GoogleAPI(auth: auth).driveFiles(query: query, pageToken: reset ? nil : nextPage)
            guard !Task.isCancelled else { return }
            let received = page.files ?? []
            files = reset ? DriveFileKind.sorted(received) : DriveFileKind.sorted(files + received)
            nextPage = page.nextPageToken
        } catch let GoogleError.http(status, body) {
            errorText = DriveErrors.message(status: status, body: body)
        } catch {
            if !Task.isCancelled { errorText = error.localizedDescription }
        }
    }
}
