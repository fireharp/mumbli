import SwiftUI
import AppKit

/// Settings section for the optional Proof-of-Use module.
struct ProofOfUseSettingsSection: View {
    @State private var enabled = ProofOfUseConfig.isEnabled
    @State private var installPublicKey: String = ""
    @State private var hasCredential = ProofOfUseFacade.shared.hasCredential
    @State private var receiptCount = ProofOfUseFacade.shared.localReceiptCount
    @State private var grantID = ProofOfUseFacade.shared.grantID ?? ""
    @State private var copiedInstallKey = false
    @State private var attestationStatus = "Unknown"

    var body: some View {
        SettingsSection(title: "Usage Proof", icon: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Sign dictation usage receipts", isOn: $enabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("mumbli-proof-toggle")
                    .onChange(of: enabled) { newValue in
                        ProofOfUseConfig.isEnabled = newValue
                        refreshState()
                    }

                Text("Creates anonymous, signed receipts locally from the embedded project grant. No transcript text is included.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if enabled {
                    statusRow(label: "Receipts signed", value: "\(receiptCount)")
                    statusRow(label: "Credential", value: hasCredential ? "Ready" : "Pending auto-enroll")
                    statusRow(label: "Package", value: attestationStatus)
                    if !grantID.isEmpty {
                        statusRow(label: "Grant", value: grantID)
                    }

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
                        Text("Credential auto-enrolls on first dictation from the embedded project grant. Grant verification status is checked when publishing proof.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Verification guide") {
                        ProofOfUseConfig.openVerificationGuide()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("mumbli-proof-verify-guide")
                }
            }
        }
        .onAppear { refreshState() }
    }

    private func refreshState() {
        installPublicKey = ProofOfUseFacade.shared.installPublicKey ?? ""
        hasCredential = ProofOfUseFacade.shared.hasCredential
        receiptCount = ProofOfUseFacade.shared.localReceiptCount
        grantID = ProofOfUseFacade.shared.grantID ?? ""
        attestationStatus = (try? AppAttestation.verifyRunningApp()) != nil ? "Signed" : "Unsigned / invalid"
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
    }
}
