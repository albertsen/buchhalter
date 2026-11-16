import Foundation
import Security
import BuchhalterCore

/// The Google Books key in the user's login keychain, as a generic password.
/// Its own target, shared by the app and `buchhalter-cli`, because
/// `BuchhalterCore` stays Foundation and SwiftData only.
/// The names carry no bundle id, so the item survives the change from
/// `local.buchhalter` to `de.juergenalbertsen.buchhalter`. `kSecAttrComment` holds the
/// key's last four characters, so the masked key shows without reading the
/// secret and without a permission prompt.
///
/// Two modes. `.fileBased` is the login keychain: no entitlement, and the
/// item trusts the code signature of the app that created it, so an ad-hoc
/// app is asked once per build. `buchhalter-cli` uses it. `.dataProtection` is
/// the keychain of a properly signed app (`kSecUseDataProtectionKeychain`,
/// with the `keychain-access-groups` entitlement): no prompt after a build.
/// With `migratingLegacy` the first read that finds nothing there reads the
/// old file-based item once and saves it into the data protection keychain.
/// The old item stays, because the command line tool still reads it.
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
    }

    public nonisolated static let service = "Buchhalter Google Books"
    public nonisolated static let account = "api-key"

    /// The secret after the first read, so one build asks the user once.
    private var cached: String?

    private let mode: Mode
    /// Set once the key was removed, so a removed key is not migrated back from
    /// the legacy item that could not be deleted.
    private var legacyIgnored = false

    /// The item in this mode's keychain.
    private var itemQuery: [CFString: Any] {
        var query = legacyQuery
        if case .dataProtection = mode { query[kSecUseDataProtectionKeychain] = true }
        return query
    }

    /// The item in the file-based login keychain.
    private var legacyQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
    }

    private var migratesLegacy: Bool {
        if case .dataProtection(let migrating) = mode { return migrating && !legacyIgnored }
        return false
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
        // Nothing in the data protection keychain: carry the old item over once.
        guard migratesLegacy, let text = try? readSecret(legacyQuery) else { return nil }
        try? await save(text)
        cached = text
        return text
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
            status = SecItemAdd(itemQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        cached = secret
    }

    /// Removes the key. In the migrating mode the old file-based item goes too,
    /// or the next read would carry it back; if that is refused, it is ignored
    /// until the app quits.
    public func delete() async throws {
        cached = nil
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        if migratesLegacy {
            legacyIgnored = true
            _ = SecItemDelete(legacyQuery as CFDictionary)
        }
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

    /// The item's attributes, from this mode's keychain; in the migrating mode
    /// from the old item when the new one is not there yet, so Settings knows
    /// about a key before the first read has carried it over.
    private func attributes() -> [CFString: Any]? {
        attributes(of: itemQuery) ?? (migratesLegacy ? attributes(of: legacyQuery) : nil)
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
