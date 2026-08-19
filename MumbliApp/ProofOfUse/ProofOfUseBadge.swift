import AppKit
import SwiftUI

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