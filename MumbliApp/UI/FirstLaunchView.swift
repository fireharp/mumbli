import SwiftUI
import AVFoundation

/// Step-by-step first launch permission flow for microphone and accessibility access.
struct FirstLaunchView: View {
    @State private var currentStep: PermissionStep = .welcome
    @State private var micGranted = false
    @State private var accessibilityGranted = false
    @State private var appearAnimation = false

    var onComplete: () -> Void

    enum PermissionStep: CaseIterable {
        case welcome
        case microphone
        case accessibility
        case ready
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Step content with transitions
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .microphone:
                    microphoneStep
                case .accessibility:
                    accessibilityStep
                case .ready:
                    readyStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(currentStep)

            Spacer()

            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(stepIndex >= index
                            ? LinearGradient(
                                colors: [Color(nsColor: .systemPurple), Color(nsColor: .systemBlue)],
                                startPoint: .leading,
                                endPoint: .trailing
                              )
                            : LinearGradient(
                                colors: [Color.primary.opacity(0.1), Color.primary.opacity(0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                              )
                        )
                        .frame(width: stepIndex == index ? 24 : 6, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: stepIndex)
                }
            }
            .accessibilityIdentifier("mumbli-step-indicator")
            .padding(.bottom, 28)
        }
        .frame(width: 420, height: 380)
        .onAppear {
            checkExistingPermissions()
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                appearAnimation = true
            }
        }
    }

    private var stepIndex: Int {
        switch currentStep {
        case .welcome: return 0
        case .microphone: return 1
        case .accessibility: return 2
        case .ready: return 3
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            // App icon area with gradient glow
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(0.15),
                                Color(nsColor: .systemBlue).opacity(0.05),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple),
                                Color(nsColor: .systemBlue),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .opacity(appearAnimation ? 1 : 0)
                    .scaleEffect(appearAnimation ? 1 : 0.8)
            }

            VStack(spacing: 8) {
                Text("Welcome to Mumbli")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .accessibilityIdentifier("mumbli-welcome-title")

                Text("Voice-to-text for your Mac.\nA few quick permissions to get started.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(3)
            }

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentStep = .microphone }
            }) {
                Text("Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 160)
            }
            .accessibilityIdentifier("mumbli-get-started")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(nsColor: .systemPurple))
        }
    }

    private var microphoneStep: some View {
        VStack(spacing: 24) {
            PermissionIcon(
                systemName: "mic.fill",
                granted: micGranted,
                gradientColors: [Color(nsColor: .systemOrange), Color(nsColor: .systemRed)]
            )

            VStack(spacing: 8) {
                Text("Microphone Access")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                if micGranted {
                    PermissionGrantedBadge(text: "Microphone access granted")
                } else {
                    Text("Mumbli needs microphone access\nto hear your dictation.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 10) {
                if !micGranted {
                    Button(action: requestMicrophoneAccess) {
                        Text("Grant Microphone Access")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 220)
                    }
                    .accessibilityIdentifier("mumbli-grant-mic")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(nsColor: .systemOrange))
                }

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentStep = .accessibility }
                }) {
                    Text(micGranted ? "Continue" : "Skip for now")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 24) {
            PermissionIcon(
                systemName: "hand.raised.fill",
                granted: accessibilityGranted,
                gradientColors: [Color(nsColor: .systemBlue), Color(nsColor: .systemCyan)]
            )

            VStack(spacing: 8) {
                Text("Accessibility Access")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                if accessibilityGranted {
                    PermissionGrantedBadge(text: "Accessibility access granted")
                } else {
                    Text("Mumbli needs Accessibility access to detect\nthe Fn key and insert text at your cursor.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 10) {
                if !accessibilityGranted {
                    Button(action: openAccessibilitySettings) {
                        Text("Open System Settings")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 220)
                    }
                    .accessibilityIdentifier("mumbli-open-accessibility")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(nsColor: .systemBlue))

                    Button("Check Again") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            checkAccessibilityPermission()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { currentStep = .ready }
                }) {
                    Text(accessibilityGranted ? "Continue" : "Skip for now")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            ZStack {
                // Celebratory glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(nsColor: .systemGreen).opacity(0.15),
                                Color(nsColor: .systemTeal).opacity(0.05),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemGreen),
                                Color(nsColor: .systemTeal),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 12) {
                Text("You're all set!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                // Quick reference cards
                VStack(spacing: 6) {
                    QuickRefCard(icon: "keyboard", text: "Hold Fn to dictate", accent: Color(nsColor: .systemPurple))
                    QuickRefCard(icon: "hand.tap", text: "Double-tap Fn for hands-free", accent: Color(nsColor: .systemBlue))
                    QuickRefCard(icon: "cursor.rays", text: "Text appears at your cursor", accent: Color(nsColor: .systemCyan))
                }
                .padding(.top, 4)
            }

            Button(action: {
                UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
                onComplete()
            }) {
                Text("Start Using Mumbli")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 200)
            }
            .accessibilityIdentifier("mumbli-start-using")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(nsColor: .systemGreen))
        }
    }

    // MARK: - Permissions

    private func checkExistingPermissions() {
        // Check mic
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micGranted = true
        default:
            break
        }

        // Check accessibility
        checkAccessibilityPermission()
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micGranted = granted
            }
        }
    }

    private func checkAccessibilityPermission() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Reusable Components

/// An animated permission icon with gradient and granted state.
struct PermissionIcon: View {
    let systemName: String
    let granted: Bool
    let gradientColors: [Color]

    @State private var scaleIn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (granted ? Color(nsColor: .systemGreen) : gradientColors.first ?? .blue).opacity(0.12),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 45
                    )
                )
                .frame(width: 90, height: 90)

            Image(systemName: granted ? "checkmark.circle.fill" : systemName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(
                    granted
                        ? LinearGradient(colors: [Color(nsColor: .systemGreen), Color(nsColor: .systemTeal)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .scaleEffect(scaleIn ? 1 : 0.7)
                .opacity(scaleIn ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05)) {
                scaleIn = true
            }
        }
    }
}

/// A green "granted" badge label.
struct PermissionGrantedBadge: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(nsColor: .systemGreen))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .systemGreen).opacity(0.08))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(nsColor: .systemGreen).opacity(0.15), lineWidth: 0.5)
                    )
            )
    }
}

/// A compact quick reference card for the ready step.
struct QuickRefCard: View {
    let icon: String
    let text: String
    var accent: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(accent.opacity(0.7))
                .frame(width: 20)

            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
        .frame(width: 280)
    }
}
