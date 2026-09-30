import Foundation
import SwiftData

/// A file attached to a client or a project — a scanned document, PDF, or photo.
/// Stored as external storage so large scans don't bloat the primary SwiftData
/// store file (CloudKit syncs external-storage attachments as CKAssets).
@Model
final class Document {
    var id: UUID = UUID()
    var filename: String = ""
    var fileExtension: String = "pdf"
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date.now

    /// Raw `SignatureStatus`: empty = not tracked, "sent" = out for signature, "signed".
    var signatureStatusRaw: String = ""
    var signatureSentAt: Date? = nil
    var signedAt: Date? = nil

    /// A file that lives in Google Drive and is only linked here (`data` stays empty):
    /// its Drive id, the link that opens it, and its Drive type.
    var driveFileID: String = ""
    var driveURL: String = ""
    var driveMimeType: String = ""

    var client: Client? = nil
    var project: Project? = nil

    init(
        filename: String = "",
        fileExtension: String = "pdf",
        data: Data = Data(),
        client: Client? = nil,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.filename = filename
        self.fileExtension = fileExtension
        self.data = data
        self.client = client
        self.project = project
        self.createdAt = .now
    }

    var isDriveLink: Bool { !driveFileID.isEmpty }

    var signatureStatus: SignatureStatus {
        get { SignatureStatus(rawValue: signatureStatusRaw) ?? .none }
        set { signatureStatusRaw = newValue.rawValue }
    }

    var displayName: String {
        filename.isEmpty ? "Document" : filename
    }
}
