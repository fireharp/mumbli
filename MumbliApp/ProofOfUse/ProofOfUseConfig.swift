import Foundation

/// Configuration for the optional Proof-of-Use module.
/// All proof-of-use code lives under `ProofOfUse/` and can be removed independently.
enum ProofOfUseConfig {
    static let projectID = "github.com/fireharp/mumbli"
    static let epoch = "2026-07"
    static let functionName = "dictation.complete"
    static let verificationURL = "https://github.com/fireharp/mumbli/blob/main/docs/proof/README.md"

    /// Trusted issuer public key (base64url). Must match docs/proof/trusted-keys.json.
    static let issuerPublicKey = "EXg1RwYqPuMTRMQTwpVzXd79NnnM4ycmtMIHltcVkUM"

    static let enabledDefaultsKey = "proofOfUseEnabled"

    static var isEnabled: Bool {
        get {
            if CommandLine.arguments.contains("--enable-proof-of-use") {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey)
        }
    }

    static var proofDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Mumbli/proof", isDirectory: true)
    }

    static var receiptsFile: URL {
        proofDirectory.appendingPathComponent("receipts.jsonl")
    }

    static var credentialFile: URL {
        proofDirectory.appendingPathComponent("credential.json")
    }
}
