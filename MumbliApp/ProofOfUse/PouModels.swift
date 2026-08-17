import Foundation

// MARK: - Wire types matching proof-of-use pou-v1 schema

struct PouCredentialBody: Codable {
    let type: String
    let credential_id: String
    let project_id: String
    let epoch: String
    let install_public_key: String
    let issued_at: String
    let app_identity: String?
    let grant_id: String?
}

struct PouCredential: Codable {
    let body: PouCredentialBody
    let issuer_signature: String?
    let grant: PouProjectGrant?
}

struct PouAuthorizedApp: Codable {
    let bundle_id: String
    let team_id: String
    let cdhash: String?
}

struct PouProjectGrant: Codable {
    let type: String
    let grant_id: String
    let project_id: String
    let epoch: String
    let release: String
    let authorized_app: PouAuthorizedApp
    let issued_at: String
    let issuer_signature: String
}

struct PouGrantSignBody: Codable {
    let type: String
    let grant_id: String
    let project_id: String
    let epoch: String
    let release: String
    let authorized_app: PouAuthorizedApp
    let issued_at: String
}

struct PouEventBody: Codable {
    let type: String
    let event_id: String
    let project_id: String
    let epoch: String
    let function_name: String
    let nullifier: String
    let time_bucket: String
    let app_identity: String?
}

struct PouReceipt: Codable {
    let install_public_key: String
    let credential: PouCredential
    let body: PouEventBody
    let install_signature: String
}

struct PouReceiptWithCommitment: Codable {
    let commitment: String
    let receipt: PouReceipt
}

// MARK: - Dictation event input

struct ProofDictationEvent {
    let engine: String
    let mode: String
    let audioDurationSec: Double
    let polished: Bool
}

extension ActivationMode {
    var proofLabel: String {
        switch self {
        case .hold: return "hold"
        case .handsFree: return "handsfree"
        }
    }
}
