import Foundation
import SwiftData

/// Store-facing: turns picked Drive files into linked `Document` records. The file stays in
/// Drive; the record keeps its id and link (plus the signature tracking every document has).
enum DriveLinker {
    /// Links the files to the client or project. Folders and files already linked there are
    /// skipped. Returns how many were added.
    @discardableResult
    static func link(_ files: [DriveFile], client: Client?, project: Project?, context: ModelContext) -> Int {
        let documents = (try? context.fetch(FetchDescriptor<Document>())) ?? []
        let existing = Set(documents.filter { document in
            if let project { return document.project?.id == project.id }
            if let client { return document.client?.id == client.id }
            return false
        }.map(\.driveFileID).filter { !$0.isEmpty })

        let fresh = DriveLinkPlan.newFiles(files, alreadyLinked: existing)
        for file in fresh {
            let document = Document(
                filename: DriveFileKind.title(for: file),
                fileExtension: DriveFileKind.fileExtension(for: file),
                data: Data(), client: client, project: project
            )
            document.driveFileID = file.id
            document.driveURL = DriveLinks.fileURL(file)?.absoluteString ?? ""
            document.driveMimeType = file.mimeType
            context.insert(document)
        }
        try? context.save()
        return fresh.count
    }
}
