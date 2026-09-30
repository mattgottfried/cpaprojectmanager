import Foundation

// Pure logic for the Google Drive integration: response models, query building, links,
// error wording, folder navigation, and de-duplicated linking. No networking, no SwiftData.
// Unit-tested with canned API responses. The app only *reads* Drive (drive.readonly): files
// stay where they are and are linked, never copied or moved.

enum DriveMime {
    static let folder = "application/vnd.google-apps.folder"
    static let document = "application/vnd.google-apps.document"
    static let spreadsheet = "application/vnd.google-apps.spreadsheet"
    static let presentation = "application/vnd.google-apps.presentation"
}

struct DriveFile: Identifiable, Equatable, Decodable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let size: Int64?
    let webViewLink: String?

    var isFolder: Bool { mimeType == DriveMime.folder }

    init(id: String, name: String, mimeType: String, modifiedTime: Date? = nil, size: Int64? = nil, webViewLink: String? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.size = size
        self.webViewLink = webViewLink
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, mimeType, modifiedTime, size, webViewLink
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        modifiedTime = try c.decodeIfPresent(String.self, forKey: .modifiedTime).flatMap(DriveParsing.date)
        // Drive sends sizes as strings ("12345"); folders and Google Docs have none.
        size = try c.decodeIfPresent(String.self, forKey: .size).flatMap { Int64($0) }
        webViewLink = try c.decodeIfPresent(String.self, forKey: .webViewLink)
    }
}

struct DriveListResponse: Decodable {
    let nextPageToken: String?
    let files: [DriveFile]?
}

enum DriveParsing {
    /// RFC 3339 with or without fractional seconds ("2025-03-01T10:30:45.123Z").
    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func decode(_ data: Data) -> DriveListResponse? {
        try? JSONDecoder().decode(DriveListResponse.self, from: data)
    }

    static func decodeFile(_ data: Data) -> DriveFile? {
        try? JSONDecoder().decode(DriveFile.self, from: data)
    }
}

enum DriveQuery {
    /// What the app asks Drive to send back for each file.
    static let fields = "nextPageToken,files(id,name,mimeType,modifiedTime,size,webViewLink)"
    static let fileFields = "id,name,mimeType,modifiedTime,size,webViewLink"

    /// Backslashes and single quotes must be escaped inside a Drive query string.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }

    /// Ids are letters, digits, "-" and "_" (plus the alias "root"). Anything else is refused
    /// so a stored value can never change the meaning of a query.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
        }
    }

    /// Everything directly inside a folder (not trashed).
    static func children(of folderID: String) -> String? {
        guard isSafeID(folderID) else { return nil }
        return "'\(folderID)' in parents and trashed = false"
    }

    /// Narrows a query to folders only (the folder picker).
    static func foldersOnly(_ query: String) -> String {
        "\(query) and mimeType = '\(DriveMime.folder)'"
    }

    /// Files and folders whose name contains `text`; nil for blank input.
    static func search(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "name contains '\(escape(trimmed))' and trashed = false"
    }
}

enum DriveLinks {
    static let myDrive = URL(string: "https://drive.google.com/drive/my-drive")!

    static func folderURL(id: String) -> URL {
        guard id != "root", DriveQuery.isSafeID(id) else { return myDrive }
        return URL(string: "https://drive.google.com/drive/folders/\(id)") ?? myDrive
    }

    /// The link that opens a file: Drive's own `webViewLink`, else the generic viewer URL.
    static func fileURL(_ file: DriveFile) -> URL? {
        if let link = file.webViewLink, let url = URL(string: link), url.scheme == "https" { return url }
        guard DriveQuery.isSafeID(file.id) else { return nil }
        return URL(string: "https://drive.google.com/file/d/\(file.id)/view")
    }
}

enum DriveFileKind {
    static func symbol(for file: DriveFile) -> String {
        if file.isFolder { return "folder.fill" }
        switch file.mimeType {
        case "application/pdf":       return "doc.richtext.fill"
        case DriveMime.document:      return "doc.text.fill"
        case DriveMime.spreadsheet:   return "tablecells.fill"
        case DriveMime.presentation:  return "rectangle.on.rectangle.angled"
        default:
            if file.mimeType.hasPrefix("image/") { return "photo.fill" }
            return "doc.fill"
        }
    }

    /// A short extension for a linked file, from its name or, failing that, its type.
    static func fileExtension(for file: DriveFile) -> String {
        let fromName = (file.name as NSString).pathExtension.lowercased()
        if !fromName.isEmpty, fromName.count <= 8 { return fromName }
        switch file.mimeType {
        case "application/pdf":       return "pdf"
        case "image/jpeg":            return "jpg"
        case "image/png":             return "png"
        case DriveMime.document:      return "gdoc"
        case DriveMime.spreadsheet:   return "gsheet"
        case DriveMime.presentation:  return "gslides"
        default:                      return "file"
        }
    }

    /// The name without its extension, for the document title.
    static func title(for file: DriveFile) -> String {
        let ext = (file.name as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 8 else { return file.name }
        return (file.name as NSString).deletingPathExtension
    }

    /// Folders first, then by name (search results arrive unordered).
    static func sorted(_ files: [DriveFile]) -> [DriveFile] {
        files.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

/// Where the browser is: a stack of folders from My Drive down.
struct DrivePath: Equatable {
    struct Crumb: Equatable {
        var id: String
        var name: String
    }

    static let root = Crumb(id: "root", name: "My Drive")

    private(set) var crumbs: [Crumb] = [DrivePath.root]

    init() {}

    /// Starts inside a folder (the client's) with My Drive above it.
    init(startingIn folder: Crumb?) {
        if let folder, folder.id != DrivePath.root.id { crumbs.append(folder) }
    }

    var current: Crumb { crumbs.last ?? DrivePath.root }
    var canGoUp: Bool { crumbs.count > 1 }

    mutating func open(_ folder: DriveFile) {
        guard folder.isFolder else { return }
        crumbs.append(Crumb(id: folder.id, name: folder.name))
    }

    mutating func up() {
        if canGoUp { crumbs.removeLast() }
    }

    /// Jump back to a crumb already on the path.
    mutating func jump(to crumb: Crumb) {
        if let index = crumbs.firstIndex(of: crumb) { crumbs = Array(crumbs[...index]) }
    }
}

enum DriveLinkPlan {
    /// The files worth linking: not folders, and not already linked.
    static func newFiles(_ picked: [DriveFile], alreadyLinked: Set<String>) -> [DriveFile] {
        var seen = alreadyLinked
        return picked.filter { !$0.isFolder && seen.insert($0.id).inserted }
    }
}

enum DriveErrors {
    /// A plain-English reason for a failed Drive call.
    static func message(status: Int, body: String) -> String {
        let text = body.lowercased()
        switch status {
        case 401:
            return "Google sign-in expired. Reconnect Google in Settings."
        case 403 where text.contains("insufficient") || text.contains("scope"):
            return "Google needs your permission for Drive. In Settings ▸ Google, tap Reconnect to Google and allow Drive access."
        case 403 where text.contains("accessnotconfigured") || text.contains("has not been used") || text.contains("disabled"):
            return "The Google Drive API isn't turned on in your Google Cloud project. Enable it, then try again."
        case 403:
            return "Google wouldn't let the app see that (403). Check that this Google account can open the folder."
        case 404:
            return "That folder or file isn't available to this Google account any more."
        case 429:
            return "Google is asking us to slow down. Try again in a minute."
        default:
            return "Google Drive error (\(status))."
        }
    }
}
