import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Configuration for the optional Proof-of-Use module.
/// All proof-of-use code lives under `ProofOfUse/` and can be removed independently.
enum ProofOfUseConfig {
    static let projectID = "github.com/fireharp/mumbli"
    static let epoch = "2026-07"
    static let functionName = "dictation.complete"
    static let verificationURL = "https://github.com/fireharp/mumbli/blob/main/docs/proof/README.md"

    /// Opens a local verification guide in ~/Library/Application Support/Mumbli/proof/README.md
    static func openVerificationGuide() {
        let readme = proofDirectory.appendingPathComponent("README.md")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try? FileManager.default.createDirectory(at: proofDirectory, withIntermediateDirectories: true)
            try? localVerificationGuideMarkdown.write(to: readme, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(readme)
    }

    private static let localVerificationGuideMarkdown = """
    # Mumbli Usage Proof — Local Guide

    Signed receipts are stored in `receipts.jsonl` in this folder.

    ## Verify with pou CLI

    ```bash
    cd mac-app
    POU_REPO=$HOME/Prog/Stuff/proof-of-use
    $POU_REPO/ProofOfUseLocal/scripts/verify-local.sh
    ```

    See the Mumbli repo `docs/proof/README.md` for full documentation.
    """

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
