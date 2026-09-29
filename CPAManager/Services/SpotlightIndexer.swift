import Foundation
import SwiftData
@preconcurrency import CoreSpotlight
import UniformTypeIdentifiers

/// Puts clients, work, open tasks, and invoices into system Spotlight so you can find
/// them from the home screen / ⌘Space and jump straight to the record. The index lives
/// on the device only; it is rebuilt (throttled) whenever the app comes to the foreground.
enum SpotlightIndexer {
    private static let domain = "com.gottfriedcpa.ProjectManager.records"
    private static var lastIndexed = Date.distantPast

    /// Kinds worth surfacing system-wide (notes, inbox scraps and expenses stay in-app).
    private static let indexedKinds: Set<SearchDoc.Kind> = [.client, .project, .task, .invoice]

    @MainActor
    static func reindex(context: ModelContext, force: Bool = false) {
        if !force && Date.now.timeIntervalSince(lastIndexed) < 300 { return }
        lastIndexed = .now

        let items: [CSSearchableItem] = SearchIndexBuilder.docs(context: context)
            .filter { indexedKinds.contains($0.kind) }
            .map { doc in
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = doc.title
                attributes.contentDescription = doc.subtitle
                attributes.keywords = doc.keywords.split(separator: " ").map(String.init)
                return CSSearchableItem(uniqueIdentifier: doc.id, domainIdentifier: domain, attributeSet: attributes)
            }

        let index = CSSearchableIndex.default()
        // Replace the whole domain so deleted records disappear from Spotlight too.
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }
}
