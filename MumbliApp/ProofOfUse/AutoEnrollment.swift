import Foundation

/// Offline auto-enrollment from embedded project grant + local app attestation.
enum AutoEnrollment {
    static func ensureCredential() throws {
        if FileManager.default.fileExists(atPath: ProofOfUseConfig.credentialFile.path) {
            if (try? UsageReceiptSigner.loadCredential()) != nil {
                return
            }
        }

        let attestation = try AppAttestation.verifyRunningApp()
        let grant = try ProjectGrantLoader.loadEmbeddedGrant()
        try ProjectGrantLoader.matchesRunningApp(grant: grant, attestation: attestation)

        let installPub = try InstallIdentity.shared.publicKeyBase64()
        let credential = try assembleGrantCredential(
            grant: grant,
            installPublicKey: installPub,
            appIdentity: attestation.appIdentityHex
        )

        try FileManager.default.createDirectory(
            at: ProofOfUseConfig.proofDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credential)
        try data.write(to: ProofOfUseConfig.credentialFile, options: .atomic)
        NSLog("[ProofOfUse] Auto-enrolled credential for grant %@", grant.grant_id)
    }

    static func assembleGrantCredential(
        grant: PouProjectGrant,
        installPublicKey: String,
        appIdentity: String
    ) throws -> PouCredential {
        let body = PouCredentialBody(
            type: "usage-credential:v1",
            credential_id: newCredentialID(),
            project_id: grant.project_id,
            epoch: grant.epoch,
            install_public_key: installPublicKey,
            issued_at: iso8601Now(),
            app_identity: appIdentity,
            grant_id: grant.grant_id
        )
        return PouCredential(body: body, issuer_signature: nil, grant: grant)
    }

    private static func newCredentialID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
