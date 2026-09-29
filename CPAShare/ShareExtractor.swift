import Foundation
import UniformTypeIdentifiers

/// What the host app (Mail, Gmail, Files, Safari…) handed to the share sheet, boiled
/// down to text, a link, and any files copied into the shared attachments folder.
struct SharePayload {
    var text = ""
    var link = ""
    var attachmentNames: [String] = []
}

enum ShareExtractor {
    static func extract(from context: NSExtensionContext?) async -> SharePayload {
        var payload = SharePayload()
        var textParts: [String] = []

        for case let item as NSExtensionItem in context?.inputItems ?? [] {
            if let title = item.attributedTitle?.string, !title.isEmpty { textParts.append(title) }
            if let body = item.attributedContentText?.string, !body.isEmpty { textParts.append(body) }

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(provider) {
                        if url.isFileURL {
                            if let name = PendingCaptures.saveAttachment(from: url) { payload.attachmentNames.append(name) }
                        } else if payload.link.isEmpty {
                            payload.link = url.absoluteString
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(provider) { textParts.append(text) }
                } else if let type = [UTType.pdf, .image, .data].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                    if let name = await loadFile(provider, type: type) { payload.attachmentNames.append(name) }
                }
            }
        }

        // De-duplicate while keeping order (hosts often repeat the title inside the body).
        var seen = Set<String>()
        payload.text = textParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: "\n")
        return payload
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    /// The temporary file only exists inside the completion handler, so copy it there.
    private static func loadFile(_ provider: NSItemProvider, type: UTType) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: PendingCaptures.saveAttachment(from: url))
            }
        }
    }
}
