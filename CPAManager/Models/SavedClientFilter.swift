import Foundation
import SwiftData

/// A named client-list filter ("Active S-Corps", "Referrals with open work").
/// Stored in SwiftData (not UserDefaults) so it syncs to every device.
@Model
final class SavedClientFilter {
    var id: UUID = UUID()
    var name: String = ""
    /// Empty string = any.
    var statusRaw: String = ""
    var entityTypeRaw: String = ""
    var tag: String = ""
    var onlyWithOpenWork: Bool = false
    var createdAt: Date = Date.now

    init(name: String = "", filter: ClientFilter = ClientFilter()) {
        self.id = UUID()
        self.name = name
        self.statusRaw = filter.status?.rawValue ?? ""
        self.entityTypeRaw = filter.entityType?.rawValue ?? ""
        self.tag = filter.tag ?? ""
        self.onlyWithOpenWork = filter.onlyWithOpenWork
        self.createdAt = .now
    }

    var filter: ClientFilter {
        ClientFilter(
            status: ClientStatus(rawValue: statusRaw),
            entityType: EntityType(rawValue: entityTypeRaw),
            tag: tag.isEmpty ? nil : tag,
            onlyWithOpenWork: onlyWithOpenWork
        )
    }
}
