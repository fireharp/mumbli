import CryptoKit
import Foundation
import Security

func b64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let service = "com.mumbli.proof"
let account = "com.mumbli.proof.install"

func loadPrivateKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
}

func savePrivateKey(_ key: Curve25519.Signing.PrivateKey) -> Bool {
    let data = key.rawRepresentation
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecDuplicateItem
}

let privateKey: Curve25519.Signing.PrivateKey
if let existing = loadPrivateKey() {
    privateKey = existing
} else {
    let fresh = Curve25519.Signing.PrivateKey()
    guard savePrivateKey(fresh) else {
        fputs("Failed to save install key to Keychain\n", stderr)
        exit(1)
    }
    privateKey = fresh
}

print(b64url(privateKey.publicKey.rawRepresentation))
