import CryptoKit
import Foundation

/// Loads and verifies the embedded project grant shipped in the app bundle.
enum ProjectGrantLoader {
    static let resourceName = "project-grant"

    static func loadEmbeddedGrant() throws -> PouProjectGrant {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            throw ProjectGrantError.missingResource
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let grant = try decoder.decode(PouProjectGrant.self, from: data)
        try verify(grant: grant)
        return grant
    }

    static func verify(grant: PouProjectGrant) throws {
        guard grant.type == "project-grant:v1" else {
            throw ProjectGrantError.invalidType
        }
        guard !grant.grant_id.isEmpty, !grant.project_id.isEmpty, !grant.epoch.isEmpty else {
            throw ProjectGrantError.invalidFields
        }
        guard !grant.authorized_app.bundle_id.isEmpty, !grant.authorized_app.team_id.isEmpty else {
            throw ProjectGrantError.invalidAuthorizedApp
        }

        let bodyBytes = try CanonicalJSON.bytes(grantSignPayload(for: grant))
        guard let sigData = Base64URL.decode(grant.issuer_signature),
              let issuerRaw = Base64URL.decode(ProofOfUseConfig.issuerPublicKey) else {
            throw ProjectGrantError.invalidIssuerSignature
        }
        let issuerKey = try Curve25519.Signing.PublicKey(rawRepresentation: issuerRaw)
        guard issuerKey.isValidSignature(sigData, for: bodyBytes) else {
            throw ProjectGrantError.invalidIssuerSignature
        }
    }

    static func matchesRunningApp(grant: PouProjectGrant, attestation: AppAttestationInfo) throws {
        if grant.authorized_app.bundle_id != attestation.bundleID {
            throw ProjectGrantError.bundleMismatch
        }
        if grant.authorized_app.team_id != "PLACEHOLDER",
           !attestation.teamID.isEmpty,
           grant.authorized_app.team_id != attestation.teamID {
            throw ProjectGrantError.teamMismatch
        }
        if let grantHash = grant.authorized_app.cdhash, !grantHash.isEmpty,
           !attestation.cdhash.isEmpty,
           grantHash.caseInsensitiveCompare(attestation.cdhash) != .orderedSame {
            throw ProjectGrantError.cdhashMismatch
        }
    }

    private static func grantSignPayload(for grant: PouProjectGrant) -> [String: Any] {
        var app: [String: Any] = [
            "bundle_id": grant.authorized_app.bundle_id,
            "team_id": grant.authorized_app.team_id,
        ]
        if let cdhash = grant.authorized_app.cdhash, !cdhash.isEmpty {
            app["cdhash"] = cdhash
        }
        return [
            "type": grant.type,
            "grant_id": grant.grant_id,
            "project_id": grant.project_id,
            "epoch": grant.epoch,
            "release": grant.release,
            "authorized_app": app,
            "issued_at": grant.issued_at,
        ]
    }
}

enum ProjectGrantError: Error, CustomStringConvertible {
    case missingResource
    case invalidType
    case invalidFields
    case invalidAuthorizedApp
    case invalidIssuerSignature
    case bundleMismatch
    case teamMismatch
    case cdhashMismatch

    var description: String {
        switch self {
        case .missingResource:
            return "Embedded project grant not found in app bundle"
        case .invalidType:
            return "Invalid project grant type"
        case .invalidFields:
            return "Project grant missing required fields"
        case .invalidAuthorizedApp:
            return "Project grant missing authorized_app"
        case .invalidIssuerSignature:
            return "Project grant issuer signature is invalid"
        case .bundleMismatch:
            return "Running app bundle id does not match grant"
        case .teamMismatch:
            return "Running app team id does not match grant"
        case .cdhashMismatch:
            return "Running app cdhash does not match grant"
        }
    }
}
