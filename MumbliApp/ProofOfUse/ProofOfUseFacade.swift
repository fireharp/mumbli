import Foundation

/// Single public entry point for the optional Proof-of-Use module.
/// Call sites outside this folder should only reference this type.
final class ProofOfUseFacade {
    static let shared = ProofOfUseFacade()

    private init() {}

    /// Record a successful dictation. No-op when proof-of-use is disabled.
    ///
    /// `onRecorded` receives the receipt's commitment hash on success, so a caller can
    /// link the signed receipt back to the history entry it covers. It is invoked on
    /// the main actor and never called when proof-of-use is disabled or signing fails.
    func recordDictation(_ event: ProofDictationEvent, onRecorded: (@MainActor (String) -> Void)? = nil) {
        guard ProofOfUseConfig.isEnabled else { return }

        Task.detached(priority: .utility) {
            do {
                try AutoEnrollment.ensureCredential()
                let installPub = try InstallIdentity.shared.publicKeyBase64()
                let credential = try UsageReceiptSigner.loadCredential()
                let appIdentity = credential.body.app_identity
                let receipt = try UsageReceiptSigner.signDictation(
                    event: event,
                    credential: credential,
                    installPublicKey: installPub,
                    appIdentity: appIdentity
                )
                try UsageReceiptStore.shared.append(receipt)
                NSLog("[ProofOfUse] Recorded receipt (total=%d)", UsageReceiptStore.shared.receiptCount())
                if let onRecorded {
                    await MainActor.run { onRecorded(receipt.commitment) }
                }
            } catch {
                NSLog("[ProofOfUse] Failed to record receipt: %@", error.localizedDescription)
            }
        }
    }

    var localReceiptCount: Int {
        UsageReceiptStore.shared.receiptCount()
    }

    var installPublicKey: String? {
        try? InstallIdentity.shared.publicKeyBase64()
    }

    var hasCredential: Bool {
        FileManager.default.fileExists(atPath: ProofOfUseConfig.credentialFile.path)
    }

    var grantID: String? {
        guard let credential = try? UsageReceiptSigner.loadCredential() else { return nil }
        return credential.body.grant_id ?? credential.grant?.grant_id
    }

    var isReady: Bool {
        ProofOfUseConfig.isEnabled && hasCredential
    }
}
