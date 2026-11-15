import Foundation
import Security
import BuchhalterCore

/// The Google Books key in the user's login keychain, as a generic password.
/// The names carry no bundle id, so the item survives the change from
/// `local.buchhalter` to a reverse-DNS id later. `kSecAttrComment` holds the
/// key's last four characters, so the masked key shows without reading the
/// secret and without a permission prompt.
///
/// This is the file-based keychain: no entitlement, and the item trusts the
/// code signature of the app that created it. Each ad-hoc build has a new
/// signature, so macOS asks once per build when the app reads the secret.
/// The data protection keychain needs a Developer team and comes with
/// proper signing (see architecture.md, Open points).
///
/// It never logs and never puts a secret in an error.
actor KeychainSecretStore: SecretStore {
    struct KeychainError: Error {
        /// The `OSStatus` only, never a value.
        var status: OSStatus
    }

    nonisolated static let service = "Buchhalter Google Books"
    nonisolated static let account = "api-key"

    /// The secret after the first read, so one build asks the user once.
    private var cached: String?

    private var itemQuery: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service, kSecAttrAccount: Self.account]
    }

    func read() async throws -> String? {
        if let cached { return cached }
        var query = itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: status)
        }
        cached = text
        return text
    }

    func save(_ secret: String) async throws {
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

    func delete() async throws {
        cached = nil
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    /// Asks for attributes only, which does not touch the secret.
    func exists() async -> Bool {
        attributes() != nil
    }

    /// The comment attribute. An item made elsewhere (`security
    /// add-generic-password`) has none; then the secret is read once.
    func suffix() async -> String? {
        guard let item = attributes() else { return nil }
        if let comment = item[kSecAttrComment] as? String, !comment.isEmpty { return comment }
        guard let secret = try? await read() else { return nil }
        return String(secret.suffix(4))
    }

    private func attributes() -> [CFString: Any]? {
        var query = itemQuery
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [CFString: Any]
    }
}
