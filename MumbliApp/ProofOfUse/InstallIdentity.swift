import CryptoKit
import Foundation
import Security

/// Epoch-scoped Ed25519 install identity stored in the Keychain.
final class InstallIdentity {
    static let shared = InstallIdentity()

    private let keychainAccount = "com.mumbli.proof.install"
    private let keychainService = "com.mumbli.proof"

    private init() {}

    func publicKeyBase64() throws -> String {
        let key = try loadOrCreatePrivateKey()
        return Base64URL.encode(key.publicKey.rawRepresentation)
    }

    func sign(_ message: Data) throws -> Data {
        let key = try loadOrCreatePrivateKey()
        return try key.signature(for: message)
    }

    private func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try loadPrivateKeyFromKeychain() {
            return existing
        }
        let key = Curve25519.Signing.PrivateKey()
        try savePrivateKeyToKeychain(key)
        return key
    }

    private func loadPrivateKeyFromKeychain() throws -> Curve25519.Signing.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw InstallIdentityError.keychainReadFailed(status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private func savePrivateKeyToKeychain(_ key: Curve25519.Signing.PrivateKey) throws {
        let data = key.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
            let attrs: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw InstallIdentityError.keychainWriteFailed(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw InstallIdentityError.keychainWriteFailed(status)
        }
    }
}

enum InstallIdentityError: Error, CustomStringConvertible {
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    var description: String {
        switch self {
        case .keychainReadFailed(let status):
            return "Keychain read failed: \(status)"
        case .keychainWriteFailed(let status):
            return "Keychain write failed: \(status)"
        }
    }
}
