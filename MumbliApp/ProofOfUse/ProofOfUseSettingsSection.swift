import SwiftUI
import AppKit

/// Settings section for the optional Proof-of-Use module.
struct ProofOfUseSettingsSection: View {
    @State private var enabled = ProofOfUseConfig.isEnabled
    @State private var installPublicKey: String = ""
    @State private var hasCredential = ProofOfUseFacade.shared.hasCredential
    @State private var receiptCount = ProofOfUseFacade.shared.localReceiptCount
    @State private var copiedInstallKey = false

    var body: some View {
        SettingsSection(title: "Usage Proof", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Sign dictation usage receipts", isOn: $enabled)
                    .toggleStyle(.switch)
                    .onChange(of: enabled) { newValue in
                        ProofOfUseConfig.isEnabled = newValue
                        refreshState()
                    }

                Text("Creates anonymous, signed receipts locally. No transcript text is included. Publish and verify with the proof-of-use CLI.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if enabled {
                    statusRow(label: "Receipts signed", value: "\(receiptCount)")
                    statusRow(label: "Credential", value: hasCredential ? "Enrolled" : "Missing")

                    if !installPublicKey.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Install public key")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(installPublicKey)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                            HStack(spacing: 8) {
                                Button(copiedInstallKey ? "Copied" : "Copy install key") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(installPublicKey, forType: .string)
                                    copiedInstallKey = true
                                }
                                .controlSize(.small)

                                Button("Open proof folder") {
                                    NSWorkspace.shared.open(ProofOfUseConfig.proofDirectory)
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    if !hasCredential {
                        Text("Run enrollment once: scripts/proof/enroll-install.sh (see docs/proof/README.md)")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Verification guide") {
                        if let url = URL(string: ProofOfUseConfig.verificationURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear { refreshState() }
    }

    private func refreshState() {
        installPublicKey = ProofOfUseFacade.shared.installPublicKey ?? ""
        hasCredential = ProofOfUseFacade.shared.hasCredential
        receiptCount = ProofOfUseFacade.shared.localReceiptCount
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }
}
