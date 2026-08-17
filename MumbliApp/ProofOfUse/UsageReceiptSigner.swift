import CryptoKit
import Foundation

/// Builds and signs proof-of-use receipts for dictation events.
enum UsageReceiptSigner {
    static func signDictation(
        event: ProofDictationEvent,
        credential: PouCredential,
        installPublicKey: String,
        appIdentity: String?
    ) throws -> PouReceiptWithCommitment {
        let nullifier = try computeNullifier(
            projectID: ProofOfUseConfig.projectID,
            epoch: ProofOfUseConfig.epoch,
            installPublicKey: installPublicKey
        )

        let timeBucket = hourBucket(for: Date())
        let eventBody = PouEventBody(
            type: "usage-event:v1",
            event_id: newEventID(),
            project_id: ProofOfUseConfig.projectID,
            epoch: ProofOfUseConfig.epoch,
            function_name: ProofOfUseConfig.functionName,
            nullifier: nullifier,
            time_bucket: timeBucket,
            app_identity: appIdentity
        )

        let bodyBytes = try CanonicalJSON.bytes(eventBody)
        let installSig = try InstallIdentity.shared.sign(bodyBytes)

        let receipt = PouReceipt(
            install_public_key: installPublicKey,
            credential: credential,
            body: eventBody,
            install_signature: Base64URL.encode(installSig)
        )

        let commitment = try computeCommitment(receipt: receipt)
        return PouReceiptWithCommitment(commitment: commitment, receipt: receipt)
    }

    static func computeNullifier(projectID: String, epoch: String, installPublicKey: String) throws -> String {
        let payload: [String: Any] = [
            "epoch": epoch,
            "install_public_key": installPublicKey,
            "project_id": projectID,
        ]
        let raw = try CanonicalJSON.bytes(payload)
        let digest = SHA256.hash(data: raw)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func computeCommitment(receipt: PouReceipt) throws -> String {
        let raw = try CanonicalJSON.bytes(receipt)
        var prefixed = Data("usage-receipt-leaf:".utf8)
        prefixed.append(raw)
        let digest = SHA256.hash(data: prefixed)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func loadCredential() throws -> PouCredential {
        let url = ProofOfUseConfig.credentialFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw UsageReceiptSignerError.missingCredential
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(PouCredential.self, from: data)
    }

    private static func hourBucket(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return String(format: "%04d-%02d-%02dT%02d:00:00Z",
                        components.year ?? 1970,
                        components.month ?? 1,
                        components.day ?? 1,
                        components.hour ?? 0)
    }

    private static func newEventID() -> String {
        UUID().uuidString.lowercased()
    }
}

enum UsageReceiptSignerError: Error, CustomStringConvertible {
    case missingCredential

    var description: String {
        switch self {
        case .missingCredential:
            return "Proof-of-use credential not found. Enable Usage Proof to auto-enroll from embedded grant."
        }
    }
}
