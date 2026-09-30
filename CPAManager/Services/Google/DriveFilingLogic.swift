import Foundation

// Pure logic for filing documents into Google Drive: where a file goes, what it's called, its
// type, the multipart upload body, and the notice shown when a file stays in the app. No
// networking, no SwiftData. Unit-tested. The app only ever *creates* files in Drive — it never
// overwrites, renames, moves or deletes anything there.

enum DriveUpload {
    static func contentType(boundary: String) -> String { "multipart/related; boundary=\(boundary)" }

    /// Drive's multipart upload: a JSON part naming the file (and its folder), then the bytes.
    static func multipartBody(name: String, mimeType: String, parentID: String?, data: Data, boundary: String) -> Data {
        var metadata: [String: Any] = ["name": name, "mimeType": mimeType]
        if let parentID, DriveQuery.isSafeID(parentID) { metadata["parents"] = [parentID] }
        let json = (try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])) ?? Data("{}".utf8)

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(json)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

/// Why a document stayed in the app instead of going to Drive.
enum DriveFilingReason: Equatable {
    case turnedOff
    case notConnected
    case noFolder
    case needsReconnect
    case failed
}

enum DriveFilingPlan {
    /// Where a file goes: the job's Drive folder, else the client's, else nowhere.
    static func destinationFolder(projectFolder: String, clientFolder: String) -> String? {
        for id in [projectFolder, clientFolder] where id != "root" && DriveQuery.isSafeID(id) { return id }
        return nil
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "tif", "tiff": return "image/tiff"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default: return "application/octet-stream"
        }
    }

    /// The name the file gets in Drive: no slashes, and the extension exactly once.
    static func driveName(filename: String, fileExtension: String) -> String {
        var base = filename.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        if base.isEmpty { base = "Document" }
        guard !ext.isEmpty else { return base }
        return base.lowercased().hasSuffix("." + ext) ? base : "\(base).\(ext)"
    }

    /// Whether a document can be moved into Drive: it has bytes here and isn't already a link.
    static func canMove(hasData: Bool, isDriveLink: Bool) -> Bool { hasData && !isDriveLink }

    /// The sentence shown when a file was kept in the app.
    static func notice(for reason: DriveFilingReason, clientName: String) -> String {
        switch reason {
        case .turnedOff:
            return "Saved in the app (saving to Drive is turned off in Settings ▸ Google)."
        case .notConnected:
            return "Saved in the app. Connect Google in Settings ▸ Google to keep files in Drive."
        case .noFolder:
            let who = clientName.trimmingCharacters(in: .whitespaces)
            return "Saved in the app. Choose a Drive folder for \(who.isEmpty ? "this client" : who) and use Move to Google Drive."
        case .needsReconnect:
            return "Saved in the app. Tap Reconnect to Google in Settings ▸ Google so Google can allow saving to Drive."
        case .failed:
            return "Saved in the app. Drive couldn't take the file just now — try Move to Google Drive again later."
        }
    }

    /// Maps a Drive HTTP status to a reason.
    static func reason(forHTTPStatus status: Int) -> DriveFilingReason {
        (status == 401 || status == 403) ? .needsReconnect : .failed
    }
}
