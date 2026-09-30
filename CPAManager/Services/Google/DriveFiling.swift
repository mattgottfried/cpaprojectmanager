import Foundation
import SwiftData

/// Store-facing: Drive is where documents live, so new files are filed there and the app keeps
/// only a link. A document is always saved in the app first — if Drive can't take it (not
/// connected, no folder chosen, offline) it simply stays put and the caller shows the notice.
@MainActor
enum DriveFiling {
    struct Outcome: Equatable {
        /// nil = the file is in Drive.
        var reason: DriveFilingReason?
        var inDrive: Bool { reason == nil }
    }

    private static var inFlight = Set<UUID>()

    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: SettingsKeys.saveToDrive) as? Bool) ?? true
    }

    /// Adds a document to the client/job and files it in Drive when possible. The name comes from
    /// the naming pattern in Settings (year, client, title), and `kind` picks the Drive subfolder.
    @discardableResult
    static func add(
        data: Data, title: String, fileExtension: String, kind: DocumentKind,
        client: Client?, project: Project?,
        auth: GoogleAuthService, context: ModelContext,
        configure: ((Document) -> Void)? = nil
    ) async -> (document: Document, outcome: Outcome) {
        let owner = client ?? project?.client
        let filename = DocumentNaming.render(
            pattern: DriveFolders.template.namePattern, title: title, client: owner?.displayName ?? "",
            year: DocumentNaming.year(taxYear: project?.taxYear, date: .now), date: .now
        )
        let document = Document(filename: filename, fileExtension: fileExtension, data: data, client: client, project: project)
        configure?(document)
        context.insert(document)
        try? context.save()
        let outcome = await move(document, kind: kind, auth: auth, context: context)
        return (document, outcome)
    }

    /// Uploads a document's bytes to its job's (else its client's) Drive folder and turns it
    /// into a Drive link. The local bytes are dropped only after Drive confirms the file.
    @discardableResult
    static func move(_ document: Document, kind: DocumentKind? = nil, auth: GoogleAuthService, context: ModelContext) async -> Outcome {
        guard DriveFilingPlan.canMove(hasData: !document.data.isEmpty, isDriveLink: document.isDriveLink) else {
            return Outcome(reason: document.isDriveLink ? nil : .failed)
        }
        guard enabled else { return Outcome(reason: .turnedOff) }
        guard auth.isConnected else { return Outcome(reason: .notConnected) }
        guard inFlight.insert(document.id).inserted else { return Outcome(reason: .failed) }
        defer { inFlight.remove(document.id) }
        let resolvedKind = kind ?? DocumentKind.infer(filename: document.displayName, fileExtension: document.fileExtension)
        guard let folder = await DriveFolders.destination(for: document, kind: resolvedKind, auth: auth) else {
            return Outcome(reason: .noFolder)
        }

        do {
            let file = try await GoogleAPI(auth: auth).driveUpload(
                name: DriveFilingPlan.driveName(filename: document.displayName, fileExtension: document.fileExtension),
                mimeType: DriveFilingPlan.mimeType(forExtension: document.fileExtension),
                data: document.data, parentID: folder
            )
            document.driveFileID = file.id
            document.driveURL = DriveLinks.fileURL(file)?.absoluteString ?? ""
            document.driveMimeType = file.mimeType
            document.data = Data()
            try? context.save()
            return Outcome(reason: nil)
        } catch {
            if case GoogleError.http(let status, _) = error {
                return Outcome(reason: DriveFilingPlan.reason(forHTTPStatus: status))
            }
            return Outcome(reason: .failed)
        }
    }

    /// Moves every local document of a client or job. Returns (moved, stayed, first reason that kept one).
    static func moveAll(
        _ documents: [Document], auth: GoogleAuthService, context: ModelContext
    ) async -> (moved: Int, stayed: Int, reason: DriveFilingReason?) {
        var moved = 0, stayed = 0
        var reason: DriveFilingReason?
        for document in documents where DriveFilingPlan.canMove(hasData: !document.data.isEmpty, isDriveLink: document.isDriveLink) {
            let outcome = await move(document, auth: auth, context: context)
            if outcome.inDrive { moved += 1 } else {
                stayed += 1
                reason = reason ?? outcome.reason
                if outcome.reason == .needsReconnect || outcome.reason == .notConnected || outcome.reason == .noFolder { break }
            }
        }
        return (moved, stayed, reason)
    }
}
