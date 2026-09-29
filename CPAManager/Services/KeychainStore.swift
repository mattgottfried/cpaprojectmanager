import Foundation
import Security

/// Minimal Keychain wrapper for small secrets (OAuth tokens, API credentials).
/// These never touch UserDefaults, disk, or SwiftData — Keychain only.
///
/// Items are **synchronizable**: with iCloud Keychain on, a Google / QuickBooks
/// connection made on one device appears on the others. (With it off they simply stay
/// on the device.) Items written by earlier builds were device-only; `get` upgrades
/// them the first time they're read.
enum KeychainStore {
    private static let service = "com.gottfriedcpa.ProjectManager.qbo"

    /// The fields that identify an item, before choosing sync vs. device-only.
    private static func identity(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        #if os(macOS)
        // Synchronizable items live in the data-protection keychain on macOS.
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    static func set(_ value: String, forKey key: String) {
        // Replace any existing synced copy.
        var stale = identity(key)
        stale[kSecAttrSynchronizable as String] = true
        SecItemDelete(stale as CFDictionary)

        var add = identity(key)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrSynchronizable as String] = true
        let status = SecItemAdd(add as CFDictionary, nil)

        if status == errSecSuccess {
            // Only now is it safe to drop a legacy device-only copy.
            var legacy = identity(key)
            legacy[kSecAttrSynchronizable as String] = false
            SecItemDelete(legacy as CFDictionary)
        } else {
            print("KeychainStore: couldn't save \(key) (status \(status))")
        }
    }

    static func get(_ key: String) -> String? {
        if let synced = read(key, synchronizable: true) { return synced }

        // Legacy device-only item from an earlier build: return it and upgrade it.
        if let legacy = read(key, synchronizable: false) {
            set(legacy, forKey: key)
            return legacy
        }
        return nil
    }

    static func remove(_ key: String) {
        var query = identity(key)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }

    private static func read(_ key: String, synchronizable: Bool) -> String? {
        var query = identity(key)
        query[kSecAttrSynchronizable as String] = synchronizable
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
