import Foundation
import Security
import BuchhalterCore

/// The Google Books key in the keychain, as a generic password.
/// Its own target, shared by the app and `buchhalter-cli`, because
/// `BuchhalterCore` stays Foundation and SwiftData only.
/// The names carry no bundle id, so the item survives the change from
/// `local.buchhalter` to `de.juergenalbertsen.buchhalter`. `kSecAttrComment` holds the
/// key's last four characters, so the masked key shows without reading the
/// secret and without a permission prompt.
///
/// Three modes. `.fileBased` is the login keychain: no entitlement, and the
/// item trusts the code signature of the app that created it, so an ad-hoc
/// app is asked once per build. `buchhalter-cli` uses it. `.dataProtection` is
/// the keychain of a properly signed app (`kSecUseDataProtectionKeychain`,
/// with the `keychain-access-groups` entitlement): no prompt after a build.
/// With `migratingLegacy` the first read that finds nothing there reads the
/// old file-based item once and saves it into the data protection keychain.
/// `.synchronized` is the same keychain with `kSecAttrSynchronizable`, so
/// iCloud Keychain carries the key to every device of the Apple Account that
/// uses it, in the access group the Mac and iOS apps share. Its first read
/// that finds nothing carries over the data protection item of the app
/// before (and deletes it), then the file-based one. The file-based item
/// stays, because the command line tool still reads it. Removing the
/// synchronized item removes it on every device.
///
/// It never logs and never puts a secret in an error.
public actor KeychainSecretStore: SecretStore {
    public struct KeychainError: Error {
        /// The `OSStatus` only, never a value.
        public var status: OSStatus
    }

    public enum Mode: Sendable, Equatable {
        case fileBased
        case dataProtection(migratingLegacy: Bool)
        case synchronized(accessGroup: String)
    }

    public nonisolated static let service = "Buchhalter Google Books"
    public nonisolated static let account = "api-key"

    /// The secret after the first read, so one build asks the user once.
    private var cached: String?

    private let mode: Mode
    /// Set once the key was removed, so a removed key is not migrated back from
    /// an older item that could not be deleted.
    private var legacyIgnored = false

    /// The item in the file-based login keychain (on iOS: the one keychain,
    /// without iCloud).
    private var fileBasedQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
    }

    /// The item in the data protection keychain, not synchronized.
    private var dataProtectionQuery: [CFString: Any] {
        var query = fileBasedQuery
        query[kSecUseDataProtectionKeychain] = true
        return query
    }

    /// The item in this mode's keychain.
    private var itemQuery: [CFString: Any] {
        switch mode {
        case .fileBased:
            return fileBasedQuery
        case .dataProtection:
            return dataProtectionQuery
        case .synchronized(let group):
            var query = dataProtectionQuery
            query[kSecAttrSynchronizable] = true
            query[kSecAttrAccessGroup] = group
            return query
        }
    }

    /// Older items to carry over on the first read that finds nothing, in order.
    private var legacyQueries: [[CFString: Any]] {
        guard !legacyIgnored else { return [] }
        switch mode {
        case .fileBased: return []
        case .dataProtection(let migrating): return migrating ? [fileBasedQuery] : []
        case .synchronized: return [dataProtectionQuery, fileBasedQuery]
        }
    }

    public init(mode: Mode = .fileBased) {
        self.mode = mode
    }

    public func read() async throws -> String? {
        if let cached { return cached }
        if let text = try readSecret(itemQuery) {
            cached = text
            return text
        }
        // Nothing in this mode's keychain: carry an older item over once.
        for legacy in legacyQueries {
            guard let text = try? readSecret(legacy) else { continue }
            try? await save(text)
            // The Mac's own item before iCloud Keychain goes; the file-based one
            // stays for the command line tool.
            if case .synchronized = mode, legacy[kSecUseDataProtectionKeychain] != nil {
                _ = SecItemDelete(legacy as CFDictionary)
            }
            cached = text
            return text
        }
        return nil
    }

    private func readSecret(_ base: [CFString: Any]) throws -> String? {
        var query = base
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        return text
    }

    public func save(_ secret: String) async throws {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(secret.utf8), kSecAttrLabel: Self.service, kSecAttrComment: String(secret.suffix(4)),
        ]
        var status = SecItemUpdate(itemQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var added = itemQuery.merging(attributes) { _, new in new }
            // A synchronized item must not be bound to this device.
            if case .synchronized = mode { added[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock }
            status = SecItemAdd(added as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        cached = secret
    }

    /// Removes the key; a synchronized one on every device. The older items go
    /// too, or the next read would carry them back; if that is refused, they
    /// are ignored until the app quits.
    public func delete() async throws {
        cached = nil
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        for legacy in legacyQueries { _ = SecItemDelete(legacy as CFDictionary) }
        legacyIgnored = true
    }

    /// Carries an older item over now, at launch, instead of at the first
    /// Google Books request, so a key saved on the Mac reaches iCloud Keychain
    /// and the other devices right away. Does nothing when the item is already
    /// in this mode's keychain.
    public func migrateIfNeeded() async {
        guard attributes(of: itemQuery) == nil, !legacyQueries.isEmpty else { return }
        _ = try? await read()
    }

    /// Asks for attributes only, which does not touch the secret.
    public func exists() async -> Bool {
        attributes() != nil
    }

    /// The comment attribute. An item made elsewhere (`security
    /// add-generic-password`) has none; then the secret is read once.
    public func suffix() async -> String? {
        guard let item = attributes() else { return nil }
        if let comment = item[kSecAttrComment] as? String, !comment.isEmpty { return comment }
        guard let secret = try? await read() else { return nil }
        return String(secret.suffix(4))
    }

    /// The item's attributes, from this mode's keychain; in a migrating mode
    /// from an older item when the new one is not there yet, so Settings knows
    /// about a key before the first read has carried it over.
    private func attributes() -> [CFString: Any]? {
        if let found = attributes(of: itemQuery) { return found }
        for legacy in legacyQueries {
            if let found = attributes(of: legacy) { return found }
        }
        return nil
    }

    private func attributes(of base: [CFString: Any]) -> [CFString: Any]? {
        var query = base
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [CFString: Any]
    }
}
