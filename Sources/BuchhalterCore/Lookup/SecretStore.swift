import Foundation

/// Where the one secret of a service lives: the Google Books API key. The
/// core only knows this protocol; the app implements it with the Keychain
/// (Security.framework is outside the core's imports, and a Keychain cannot be
/// unit-tested without touching the user's real one). Tests use a fake.
///
/// Implementations never log a secret and never put it in an error.
public protocol SecretStore: Sendable {
    /// The secret, or nil when none is saved. Reading may ask the user for
    /// permission, so callers read only when they are about to use it.
    func read() async throws -> String?
    func save(_ secret: String) async throws
    func delete() async throws
    /// Whether a secret is saved. Never reads the secret itself.
    func exists() async -> Bool
    /// The secret's last four characters, for the masked display. Nil when
    /// none is saved.
    func suffix() async -> String?
}
