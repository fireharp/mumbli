import Foundation

/// Offline auto-enrollment from embedded project grant + local app attestation.
enum AutoEnrollment {
    static func ensureCredential() throws {
        // Load the embedded grant up front (not just on the re-enrollment path) so a
        // fresh grant shipped in a new build is detected even when the cached
        // credential's epoch still matches — otherwise a re-issued grant would sit
        // unused until the next month, and Settings would keep reporting a grant id
        // from a release that shipped weeks or months ago.
        let grant = try ProjectGrantLoader.loadEmbeddedGrant()

        if FileManager.default.fileExists(atPath: ProofOfUseConfig.credentialFile.path) {
            if let existing = try? UsageReceiptSigner.loadCredential() {
                // A credential is only usable within the epoch it was minted for, and
                // only for the grant it was minted from. Re-mint on either change
                // instead of signing receipts against a stale epoch or grant.
                if existing.body.epoch == ProofOfUseConfig.epoch,
                   existing.body.grant_id == grant.grant_id {
                    return
                }
                if existing.body.epoch != ProofOfUseConfig.epoch {
                    NSLog(
                        "[ProofOfUse] Credential epoch %@ is stale (now %@); re-enrolling",
                        existing.body.epoch, ProofOfUseConfig.epoch
                    )
                } else {
                    NSLog(
                        "[ProofOfUse] Credential grant %@ differs from embedded grant %@; re-enrolling",
                        existing.body.grant_id ?? "nil", grant.grant_id
                    )
                }
            }
        }

        let attestation = try AppAttestation.verifyRunningApp()
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
            epoch: ProofOfUseConfig.epoch,
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
