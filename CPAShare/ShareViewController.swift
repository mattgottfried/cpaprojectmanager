import UIKit
import SwiftUI

/// Principal class of the share extension. Reads what was shared, shows `ShareView`,
/// and on Save queues the capture in the App Group for the app to import.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        Task { @MainActor [weak self] in
            guard let self else { return }
            let payload = await ShareExtractor.extract(from: self.extensionContext)

            let root = ShareView(
                text: payload.text,
                link: payload.link,
                attachmentNames: payload.attachmentNames,
                onSave: { [weak self] text, sourceRaw in
                    self?.save(text: text, sourceRaw: sourceRaw, payload: payload)
                },
                onCancel: { [weak self] in
                    self?.cancel(payload: payload)
                }
            )
            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            host.didMove(toParent: self)
        }
    }

    private func save(text: String, sourceRaw: String, payload: SharePayload) {
        if payload.attachmentNames.isEmpty {
            PendingCaptures.enqueue(PendingCapture(text: text, sourceRaw: sourceRaw, link: payload.link))
        } else {
            // One Inbox item per file so each can be filed separately; the note text
            // rides along on the first.
            for (index, name) in payload.attachmentNames.enumerated() {
                PendingCaptures.enqueue(PendingCapture(
                    text: index == 0 ? text : "",
                    sourceRaw: sourceRaw,
                    link: payload.link,
                    attachmentName: name
                ))
            }
        }
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel(payload: SharePayload) {
        // Don't leave copied files behind when the user backs out.
        for name in payload.attachmentNames {
            if let url = PendingCaptures.attachmentURL(name) { try? FileManager.default.removeItem(at: url) }
        }
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}
