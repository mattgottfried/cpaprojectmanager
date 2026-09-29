import Foundation

/// A capture handed over by the share extension (or a Control Center control), waiting
/// for the app to turn it into an Inbox item. Extensions can't open the app's
/// CloudKit-backed store, so they queue here (App Group) and the app drains the queue.
/// Compiled into the app and the extensions.
struct PendingCapture: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    /// Raw `InboxSource` ("email", "note", …); kept as a string so this file stays
    /// independent of app-only types.
    var sourceRaw: String = "email"
    var createdAt: Date = Date.now
    var link: String = ""
    /// File saved in the shared attachments folder (a PDF, image, …), if any.
    var attachmentName: String = ""
}

enum PendingCaptures {
    static let key = "pendingCaptures"
    static let openRequestKey = "pendingOpenRequest"

    // MARK: Queue

    static func encode(_ captures: [PendingCapture]) -> Data? {
        try? JSONEncoder().encode(captures)
    }

    static func decode(_ data: Data?) -> [PendingCapture] {
        guard let data, let captures = try? JSONDecoder().decode([PendingCapture].self, from: data) else { return [] }
        return captures
    }

    static func enqueue(_ capture: PendingCapture) {
        guard let defaults = AppGroup.sharedDefaults else { return }
        var queue = decode(defaults.data(forKey: key))
        queue.append(capture)
        defaults.set(encode(queue), forKey: key)
    }

    /// Returns and clears the queue.
    static func drain() -> [PendingCapture] {
        guard let defaults = AppGroup.sharedDefaults else { return [] }
        let queue = decode(defaults.data(forKey: key))
        defaults.removeObject(forKey: key)
        return queue
    }

    // MARK: Attachments

    static var attachmentsDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("SharedAttachments", isDirectory: true)
    }

    /// Copies `source` into the shared folder under a unique name; returns that name.
    static func saveAttachment(from source: URL) -> String? {
        guard let directory = attachmentsDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)"
        do {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    static func attachmentURL(_ name: String) -> URL? {
        guard !name.isEmpty else { return nil }
        return attachmentsDirectory?.appendingPathComponent(name)
    }

    /// "1A2B3C4D-Statement.pdf" → ("Statement", "pdf"): drops the uniqueness prefix.
    static func displayParts(_ storedName: String) -> (base: String, ext: String) {
        var name = storedName
        if let dash = name.firstIndex(of: "-"), name.distance(from: name.startIndex, to: dash) == 8 {
            name = String(name[name.index(after: dash)...])
        }
        let url = URL(fileURLWithPath: name)
        return (url.deletingPathExtension().lastPathComponent, url.pathExtension.lowercased())
    }

    // MARK: "Open the app to…" requests (Control Center controls)

    static func requestOpen(_ target: String) {
        AppGroup.sharedDefaults?.set(target, forKey: openRequestKey)
    }

    static func consumeOpenRequest() -> String? {
        guard let defaults = AppGroup.sharedDefaults, let target = defaults.string(forKey: openRequestKey) else { return nil }
        defaults.removeObject(forKey: openRequestKey)
        return target
    }
}
