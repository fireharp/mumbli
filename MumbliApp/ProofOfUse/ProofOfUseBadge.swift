import AppKit
import SwiftUI

/// Optional menu bar badge showing locally signed proof-of-use receipt count.
struct ProofOfUseMenuBarBadge: View {
    var body: some View {
        if ProofOfUseConfig.isEnabled {
            let count = ProofOfUseFacade.shared.localReceiptCount
            if count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(nsColor: .systemGreen))
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
                        )
                )
                .help("Signed usage receipts (verify with proof-of-use)")
                .accessibilityIdentifier("mumbli-proof-badge")
            }
        }
    }
}

/// Footer link to the public verification guide.
struct ProofOfUseMenuBarLink: View {
    var body: some View {
        if ProofOfUseConfig.isEnabled {
            MenuBarActionButton(
                icon: "checkmark.seal",
                label: "Verify usage proof",
                accessibilityID: "mumbli-proof-verify-link",
                action: {
                    ProofOfUseConfig.openVerificationGuide()
                }
            )
        }
    }
}