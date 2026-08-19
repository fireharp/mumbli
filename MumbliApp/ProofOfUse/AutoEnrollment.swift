import Foundation

/// Offline auto-enrollment from embedded project grant + local app attestation.
enum AutoEnrollment {
    static func ensureCredential() throws {
        // Load the embedded grant up front (not just on the slow path) so a fresh
        // grant shipped in a new release is detected even when the epoch hasn't
        // rolled over. Without this, a credential from grant A stays cached under
        // grant B until the month changes — which is how the app kept reporting a
        // 0.5.0-dev grant three releases after a newer grant should have applied.
        let grant = try ProjectGrantLoader.loadEmbeddedGrant()

        if FileManager.default.fileExists(atPath: ProofOfUseConfig.credentialFile.path) {
            if let existing = try? UsageReceiptSigner.loadCredential() {
                // A credential is only usable within the epoch it was minted for; the
                // verifier rejects receipts whose credential epoch differs from the
                // statement epoch. It must also match the currently embedded grant —
                // re-mint instead of signing receipts under a stale grant_id.
                let epochCurrent = existing.body.epoch == ProofOfUseConfig.epoch
                let grantCurrent = existing.body.grant_id == grant.grant_id
                if epochCurrent && grantCurrent {
                    return
                }
                if !epochCurrent {
                    NSLog(
                        "[ProofOfUse] Credential epoch %@ is stale (now %@); re-enrolling",
                        existing.body.epoch, ProofOfUseConfig.epoch
                    )
                } else {
                    NSLog(
                        "[ProofOfUse] Credential grant %@ is stale (now %@); re-enrolling",
                        existing.body.grant_id ?? "?", grant.grant_id
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
