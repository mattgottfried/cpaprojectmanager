import Foundation
import SwiftData

/// Store-facing: builds and walks the client folder structure in Drive. Folders are found by
/// name (or by their leading number) before anything is created, so running it twice, or on a
/// second device, never makes duplicates. It only ever creates folders.
@MainActor
enum DriveFolders {
    nonisolated static var template: DriveFolderTemplate {
        DriveFolderTemplate.decode(UserDefaults.standard.string(forKey: SettingsKeys.driveFolderTemplate) ?? "")
    }
    nonisolated static var rootID: String { UserDefaults.standard.string(forKey: SettingsKeys.driveClientsRootID) ?? "" }
    nonisolated static var autoCreate: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.driveAutoCreateFolders) }

    /// The folder called `name` inside `parentID`, created if it isn't there.
    static func ensureChild(named name: String, in parentID: String, api: GoogleAPI) async throws -> String {
        guard let query = DriveQuery.children(of: parentID) else { throw GoogleError.decoding }
        let page = try await api.driveFiles(query: DriveQuery.foldersOnly(query), pageSize: 200)
        if let existing = FolderMatch.match(name: name, in: page.files ?? []) { return existing.id }
        return try await api.driveCreateFolder(name: name, parentID: parentID).id
    }

    /// Walks (creating as needed) `components` below `parentID`; returns the last folder's id.
    static func ensurePath(_ components: [String], below parentID: String, api: GoogleAPI) async throws -> String {
        var current = parentID
        for name in components { current = try await ensureChild(named: name, in: current, api: api) }
        return current
    }

    enum CreateResult: Equatable {
        case created(String)
        case alreadyHasFolder
        case noRoot
        case notConnected
        case failed(String)
    }

    /// Gives a client a Drive folder (named after them, under the chosen root) with the template's
    /// numbered subfolders, and links it on the client. Adopts a folder of the same name if one exists.
    @discardableResult
    static func ensureClientFolder(_ client: Client, auth: GoogleAuthService, context: ModelContext) async -> CreateResult {
        guard client.driveFolderID.isEmpty else { return .alreadyHasFolder }
        guard auth.isConnected else { return .notConnected }
        let root = rootID
        guard DriveQuery.isSafeID(root) else { return .noRoot }
        let api = GoogleAPI(auth: auth)
        let name = ClientFolderName.name(for: client.displayName)
        do {
            let folderID = try await ensureChild(named: name, in: root, api: api)
            for slot in template.slots {
                _ = try await ensureChild(named: slot.name, in: folderID, api: api)
            }
            client.driveFolderID = folderID
            client.driveFolderName = name
            try? context.save()
            return .created(folderID)
        } catch let GoogleError.http(status, body) {
            return .failed(DriveErrors.message(status: status, body: body))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The automatic path: a new client or tax return creates the folder when that's switched on.
    static func autoCreateIfNeeded(_ client: Client, auth: GoogleAuthService, context: ModelContext) async {
        guard autoCreate, client.driveFolderID.isEmpty else { return }
        _ = await ensureClientFolder(client, auth: auth, context: context)
    }

    /// Where a document goes: the job's own Drive folder if it has one, else the client's folder
    /// routed by document type (with a year subfolder where the template asks for one). If the
    /// subfolders can't be made, the client's folder itself is used.
    static func destination(
        for document: Document, kind: DocumentKind, auth: GoogleAuthService
    ) async -> String? {
        let owner = document.client ?? document.project?.client
        if let direct = DriveFilingPlan.destinationFolder(projectFolder: document.project?.driveFolderID ?? "", clientFolder: "") {
            return direct
        }
        guard let clientFolder = DriveFilingPlan.destinationFolder(projectFolder: "", clientFolder: owner?.driveFolderID ?? "") else { return nil }
        let year = DocumentNaming.year(taxYear: document.project?.taxYear, date: .now)
        let path = template.path(for: kind, year: year)
        guard !path.isEmpty else { return clientFolder }
        do {
            return try await ensurePath(path, below: clientFolder, api: GoogleAPI(auth: auth))
        } catch {
            return clientFolder
        }
    }

    /// Files in a client's upload areas, for matching against what they owe you.
    static func uploadedFiles(for client: Client, auth: GoogleAuthService) async -> [DriveFile] {
        guard auth.isConnected, DriveQuery.isSafeID(client.driveFolderID) else { return [] }
        let api = GoogleAPI(auth: auth)
        var files: [DriveFile] = []
        var folders = [client.driveFolderID]
        if let uploads = template.slot(for: .upload), let query = DriveQuery.children(of: client.driveFolderID),
           let page = try? await api.driveFiles(query: DriveQuery.foldersOnly(query), pageSize: 200),
           let match = FolderMatch.match(name: uploads.name, in: page.files ?? []) {
            folders = [match.id]
        }
        for folder in folders {
            guard let query = DriveQuery.children(of: folder),
                  let page = try? await api.driveFiles(query: query, pageSize: 100, orderBy: "modifiedTime desc") else { continue }
            files.append(contentsOf: page.files ?? [])
        }
        return files
    }
}
