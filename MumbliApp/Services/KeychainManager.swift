import Foundation
import Security

/// Stores API keys in the macOS Keychain.
///
/// Release builds have carried a stable Developer ID signing identity since
/// v0.5.0, so the Keychain no longer re-prompts on every rebuild the way it
/// did under ad-hoc signing — the concern the previous UserDefaults-backed
/// implementation was written to avoid. Local dev builds without a
/// Development Team may still prompt once per rebuild; see
/// docs/for-developers/accessibility-permissions.mdx.
final class KeychainManager {
    static let shared = KeychainManager()

    static let elevenLabsAPIKeyKey = "com.mumbli.elevenlabs-api-key"
    static let openAIAPIKeyKey = "com.mumbli.openai-api-key"
    static let groqAPIKeyKey = "com.mumbli.groq-api-key"
    static let deepgramAPIKeyKey = "com.mumbli.deepgram-api-key"

    private let service = "com.mumbli.app"

    /// One-time migration marker so an existing UserDefaults value is moved
    /// into the Keychain at most once per key.
    private let defaults = UserDefaults.standard

    private init() {}

    func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.writeFailed(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = query
            attributes.forEach { addQuery[$0] = $1 }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.writeFailed(addStatus)
            }
        default:
            throw KeychainError.writeFailed(status)
        }

        // The value now lives in the Keychain; drop any pre-migration
        // UserDefaults copy so it can't drift out of sync or linger in a
        // plain-text plist.
        defaults.removeObject(forKey: key)
    }

    func get(key: String) -> String? {
        if let value = readFromKeychain(key: key) {
            return value
        }
        // Fall back to the pre-Keychain UserDefaults location so upgrading
        // users don't lose keys they already entered, then migrate it.
        if let legacy = defaults.string(forKey: key), !legacy.isEmpty {
            try? save(key: key, value: legacy)
            return legacy
        }
        return nil
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: key)
    }

    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

enum KeychainError: Error, CustomStringConvertible {
    case writeFailed(OSStatus)

    var description: String {
        switch self {
        case .writeFailed(let status):
            return "Keychain write failed: \(status)"
        }
    }
}
