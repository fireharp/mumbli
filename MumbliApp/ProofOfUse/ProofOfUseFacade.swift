import Foundation

/// Single public entry point for the optional Proof-of-Use module.
/// Call sites outside this folder should only reference this type.
final class ProofOfUseFacade {
    static let shared = ProofOfUseFacade()

    private init() {}

    /// Record a successful dictation. No-op when proof-of-use is disabled.
    func recordDictation(_ event: ProofDictationEvent) {
        guard ProofOfUseConfig.isEnabled else { return }

        Task.detached(priority: .utility) {
            do {
                let installPub = try InstallIdentity.shared.publicKeyBase64()
                let credential = try UsageReceiptSigner.loadCredential()
                let receipt = try UsageReceiptSigner.signDictation(
                    event: event,
                    credential: credential,
                    installPublicKey: installPub
                )
                try UsageReceiptStore.shared.append(receipt)
                NSLog("[ProofOfUse] Recorded receipt (total=%d)", UsageReceiptStore.shared.receiptCount())
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

    var isReady: Bool {
        ProofOfUseConfig.isEnabled && hasCredential
    }
}
