import CryptoKit
import Foundation
import Security

struct AppAttestationInfo {
    let teamID: String
    let bundleID: String
    let cdhash: String
    let appIdentityHex: String
}

/// Local package verification via macOS code signing APIs.
enum AppAttestation {
    static func verifyRunningApp() throws -> AppAttestationInfo {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let code = staticCode else {
            throw AppAttestationError.copySelfFailed(createStatus)
        }

        let valid = SecStaticCodeCheckValidity(code, SecCSFlags(), nil)
        guard valid == errSecSuccess else {
            throw AppAttestationError.signatureInvalid
        }

        var infoCF: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &infoCF
        )
        guard infoStatus == errSecSuccess, let info = infoCF as? [String: Any] else {
            throw AppAttestationError.signingInfoFailed(infoStatus)
        }

        let teamID = stringValue(info[kSecCodeInfoTeamIdentifier as String]) ?? ""
        let bundleID = stringValue(info[kSecCodeInfoIdentifier as String]) ?? ""
        let cdhash = cdhashHex(from: info[kSecCodeInfoUnique as String])

        guard !bundleID.isEmpty else {
            throw AppAttestationError.missingBundleID
        }

        let appIdentity = try computeAppIdentity(teamID: teamID, bundleID: bundleID, cdhash: cdhash)
        return AppAttestationInfo(
            teamID: teamID,
            bundleID: bundleID,
            cdhash: cdhash,
            appIdentityHex: appIdentity
        )
    }

    static func computeAppIdentity(teamID: String, bundleID: String, cdhash: String) throws -> String {
        let payload: [String: Any] = [
            "bundle_id": bundleID,
            "cdhash": cdhash,
            "team_id": teamID,
        ]
        let raw = try CanonicalJSON.bytes(payload)
        let digest = SHA256.hash(data: raw)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func cdhashHex(from value: Any?) -> String {
        if let data = value as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        if let string = value as? String {
            return string.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return ""
    }
}

enum AppAttestationError: Error, CustomStringConvertible {
    case copySelfFailed(OSStatus)
    case signatureInvalid
    case signingInfoFailed(OSStatus)
    case missingBundleID

    var description: String {
        switch self {
        case .copySelfFailed(let status):
            return "Failed to read running app static code: \(status)"
        case .signatureInvalid:
            return "App code signature is not valid"
        case .signingInfoFailed(let status):
            return "Failed to read code signing information: \(status)"
        case .missingBundleID:
            return "App bundle identifier missing from signing info"
        }
    }
}
