import SwiftUI
import AVFoundation

/// SwiftUI view for app settings, primarily microphone selection.
struct SettingsView: View {
    @State private var audioDevices: [AudioDevice] = []
    @State private var selectedDeviceID: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("Configure your Mumbli experience")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Subtle app icon
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(0.4),
                                Color(nsColor: .systemBlue).opacity(0.3),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 20)

            // Content
            VStack(spacing: 20) {
                // Audio Input section
                SettingsSection(title: "Audio Input", icon: "mic.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Microphone", selection: $selectedDeviceID) {
                            ForEach(audioDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .accessibilityIdentifier("mumbli-mic-picker")
                        .labelsHidden()
                        .onChange(of: selectedDeviceID) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "selectedMicrophoneID")
                        }

                        if audioDevices.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(nsColor: .systemYellow))
                                Text("No audio input devices found")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Shortcuts section
                SettingsSection(title: "Shortcuts", icon: "keyboard") {
                    VStack(spacing: 10) {
                        ShortcutRow(
                            label: "Hold to dictate",
                            keys: "Fn"
                        )
                        ShortcutRow(
                            label: "Hands-free mode",
                            keys: "Fn Fn"
                        )
                    }
                }

                // About section
                SettingsSection(title: "About", icon: "info.circle") {
                    HStack {
                        Text("Version")
                            .font(.system(size: 12))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(width: 420, height: 320)
        .onAppear {
            loadAudioDevices()
            selectedDeviceID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
        }
    }

    private func loadAudioDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        audioDevices = discoverySession.devices.map { device in
            AudioDevice(id: device.uniqueID, name: device.localizedName)
        }

        // If no saved selection, default to system default
        if selectedDeviceID.isEmpty, let defaultDevice = AVCaptureDevice.default(for: .audio) {
            selectedDeviceID = defaultDevice.uniqueID
        }
    }
}

/// A styled settings section with an icon and title.
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))

                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    .tracking(0.5)
            }

            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
    }
}

/// A row displaying a keyboard shortcut.
struct ShortcutRow: View {
    let label: String
    let keys: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.primary.opacity(0.06))
                                .shadow(color: Color.primary.opacity(0.04), radius: 0, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

/// A simple audio device model for the picker.
struct AudioDevice: Identifiable {
    let id: String
    let name: String
}
