import Foundation
import Security
import CryptoKit

/// Outcome of a Trust-On-First-Use pin attempt for a daemon static key.
public enum PinOutcome: Equatable {
    /// No key was pinned for this host before — the presented key is now stored.
    case firstUse
    /// The presented key matches the already-pinned key for this host.
    case alreadyPinned
    /// A different key is already pinned for this host (potential MITM).
    case mismatch
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case dataCorrupted
    case identityCreationFailed
}

/// Stores the client's own X25519 static identity and the TOFU-pinned daemon
/// static keys in the iOS/macOS Keychain (generic-password items).
///
/// The `service` is injectable so tests can isolate themselves under a unique
/// service string and tear everything down afterward.
public final class KeychainStore {
    private let service: String
    private let identityAccount = "client.static.identity.x25519"
    private let pinPrefix = "daemon.pin."

    public init(service: String = "com.malhar.MaverickRemote.pairing") {
        self.service = service
    }

    // MARK: - Client static identity

    /// Load the persisted client static private key, generating and storing one
    /// on first call. Returns the SAME key (stable raw representation) on every
    /// subsequent call.
    public func loadOrCreateStaticIdentity() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = try read(account: identityAccount) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try write(account: identityAccount, data: key.rawRepresentation)
        return key
    }

    // MARK: - TOFU daemon-key pinning

    /// Pin a daemon's static public key for `host` (Trust On First Use).
    ///
    /// - `.firstUse` when nothing was pinned for the host (now stored).
    /// - `.alreadyPinned` when the presented key matches the stored one.
    /// - `.mismatch` when a different key is stored (no overwrite).
    ///
    /// The host string may be a hostname or a deviceId — callers choose the
    /// pinning granularity; the store treats it as an opaque account suffix.
    public func pin(host: String, key: Data) throws -> PinOutcome {
        let account = pinPrefix + host
        if let existing = try read(account: account) {
            return constantTimeEqual(existing, key) ? .alreadyPinned : .mismatch
        }
        try write(account: account, data: key)
        return .firstUse
    }

    /// The currently-pinned key for `host`, if any.
    public func pinnedKey(host: String) throws -> Data? {
        try read(account: pinPrefix + host)
    }

    /// Remove all Keychain items under this store's service (test/reset helper).
    public func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Low-level Keychain access

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.dataCorrupted }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func write(account: String, data: Data) throws {
        // Try add; if it already exists, update in place.
        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [String: Any] = [kSecValueData as String: data]
            let upStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                         update as CFDictionary)
            guard upStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(upStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Constant-time compare

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[a.index(a.startIndex, offsetBy: i)] ^ b[b.index(b.startIndex, offsetBy: i)]
        }
        return diff == 0
    }
}
