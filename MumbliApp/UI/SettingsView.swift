import SwiftUI
import AVFoundation

/// SwiftUI view for app settings: microphone selection and API key configuration.
struct SettingsView: View {
    @State private var audioDevices: [AudioDevice] = []
    @State private var selectedDeviceID: String = ""
    @State private var elevenLabsKey: String = ""
    @State private var openAIKey: String = ""
    @State private var hasElevenLabsKey: Bool = false
    @State private var hasOpenAIKey: Bool = false
    @State private var elevenLabsMasked: String = ""
    @State private var openAIMasked: String = ""
    @State private var elevenLabsSavedConfirm: Bool = false
    @State private var openAISavedConfirm: Bool = false
    @State private var elevenLabsIsEditing: Bool = false
    @State private var openAIIsEditing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Settings")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 28)

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    // Audio Input section
                    SettingsSection(title: "Audio Input", icon: "mic.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(audioDevices.isEmpty
                                        ? Color(nsColor: .systemYellow)
                                        : Color(nsColor: .systemGreen))
                                    .frame(width: 6, height: 6)

                                Picker("Microphone", selection: $selectedDeviceID) {
                                    ForEach(audioDevices) { device in
                                        Text(device.name).tag(device.id)
                                    }
                                }
                                .accessibilityIdentifier("mumbli-mic-picker")
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .onChange(of: selectedDeviceID) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "selectedMicrophoneID")
                                }
                            }

                            if audioDevices.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(nsColor: .systemYellow))
                                    Text("No audio input devices found")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // API Keys section
                    SettingsSection(title: "API Keys", icon: "key.fill") {
                        VStack(spacing: 12) {
                            // ElevenLabs row
                            APIKeyRow(
                                serviceName: "ElevenLabs",
                                iconName: "waveform",
                                placeholder: "xi-...paste key",
                                keyText: $elevenLabsKey,
                                isSet: hasElevenLabsKey,
                                maskedValue: elevenLabsMasked,
                                isEditing: $elevenLabsIsEditing,
                                savedConfirm: elevenLabsSavedConfirm,
                                accessibilityID: "mumbli-elevenlabs-key",
                                onCommit: { commitElevenLabsKey() }
                            )
                            .accessibilityLabel("ElevenLabs API Key, \(hasElevenLabsKey ? "configured" : "not set")")

                            Divider().opacity(0.1)

                            // OpenAI row
                            APIKeyRow(
                                serviceName: "OpenAI",
                                iconName: "brain",
                                placeholder: "sk-...paste key",
                                keyText: $openAIKey,
                                isSet: hasOpenAIKey,
                                maskedValue: openAIMasked,
                                isEditing: $openAIIsEditing,
                                savedConfirm: openAISavedConfirm,
                                accessibilityID: "mumbli-openai-key",
                                onCommit: { commitOpenAIKey() }
                            )
                            .accessibilityLabel("OpenAI API Key, \(hasOpenAIKey ? "configured" : "not set")")

                            if !hasElevenLabsKey || !hasOpenAIKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(nsColor: .systemOrange))
                                    Text("Required for dictation")
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
                                keys: ["Fn"]
                            )
                            ShortcutRow(
                                label: "Hands-free mode",
                                keys: ["Fn", "Fn"],
                                isDoubleTap: true
                            )
                        }
                    }

                    // About section
                    SettingsSection(title: "About", icon: "info.circle") {
                        HStack {
                            Text("Version")
                                .font(.system(size: 13))
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: 460, minHeight: 580, maxHeight: 700)
        .onAppear {
            loadAudioDevices()
            selectedDeviceID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
            loadKeyStates()
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

        if selectedDeviceID.isEmpty, let defaultDevice = AVCaptureDevice.default(for: .audio) {
            selectedDeviceID = defaultDevice.uniqueID
        }
    }

    private func loadKeyStates() {
        if let key = KeychainManager.shared.get(key: KeychainManager.elevenLabsAPIKeyKey) {
            hasElevenLabsKey = true
            elevenLabsMasked = Self.maskKey(key)
        }
        if let key = KeychainManager.shared.get(key: KeychainManager.openAIAPIKeyKey) {
            hasOpenAIKey = true
            openAIMasked = Self.maskKey(key)
        }
    }

    private func commitElevenLabsKey() {
        let trimmed = elevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if hasElevenLabsKey {
                KeychainManager.shared.delete(key: KeychainManager.elevenLabsAPIKeyKey)
                hasElevenLabsKey = false
                elevenLabsMasked = ""
            }
        } else {
            try? KeychainManager.shared.save(key: KeychainManager.elevenLabsAPIKeyKey, value: trimmed)
            hasElevenLabsKey = true
            elevenLabsMasked = Self.maskKey(trimmed)
            elevenLabsKey = ""
            elevenLabsIsEditing = false
            elevenLabsSavedConfirm = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { elevenLabsSavedConfirm = false }
        }
    }

    private func commitOpenAIKey() {
        let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if hasOpenAIKey {
                KeychainManager.shared.delete(key: KeychainManager.openAIAPIKeyKey)
                hasOpenAIKey = false
                openAIMasked = ""
            }
        } else {
            try? KeychainManager.shared.save(key: KeychainManager.openAIAPIKeyKey, value: trimmed)
            hasOpenAIKey = true
            openAIMasked = Self.maskKey(trimmed)
            openAIKey = ""
            openAIIsEditing = false
            openAISavedConfirm = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { openAISavedConfirm = false }
        }
    }

    static func maskKey(_ key: String) -> String {
        guard key.count > 7 else { return "****" }
        let prefix = String(key.prefix(3))
        let suffix = String(key.suffix(4))
        return "\(prefix)****...\(suffix)"
    }
}

/// A single API key row with service icon, name, status dot, and secure field.
struct APIKeyRow: View {
    let serviceName: String
    let iconName: String
    let placeholder: String
    @Binding var keyText: String
    let isSet: Bool
    let maskedValue: String
    @Binding var isEditing: Bool
    let savedConfirm: Bool
    let accessibilityID: String
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text(serviceName)
                    .font(.system(size: 13))

                Spacer()

                Circle()
                    .fill(isSet
                        ? Color(nsColor: .systemGreen)
                        : Color(nsColor: .systemOrange))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)

                if isSet && !isEditing {
                    Text(maskedValue)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 180, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .onTapGesture {
                            isEditing = true
                        }
                } else {
                    SecureField(placeholder, text: $keyText, onCommit: onCommit)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .accessibilityIdentifier(accessibilityID)
                }
            }

            if savedConfirm {
                Text("Key saved")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .systemGreen))
                    .transition(.opacity)
            }
        }
    }
}

/// A styled settings section with an icon and title.
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))

                Text(title)
                    .font(.system(size: 12, weight: .semibold).smallCaps())
                    .foregroundColor(.secondary)
            }

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        }
    }
}

/// A row displaying a keyboard shortcut with realistic key caps.
struct ShortcutRow: View {
    let label: String
    let keys: [String]
    var isDoubleTap: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            HStack(spacing: isDoubleTap ? 2 : 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if isDoubleTap && index > 0 {
                        Text("\u{00B7}")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    KeyCap(label: key)
                }
            }
        }
    }
}

/// A keyboard key cap styled to look like a physical key.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlColor))

                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.6))
                            .frame(height: 1)
                        Spacer()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
    }
}

/// A simple audio device model for the picker.
struct AudioDevice: Identifiable {
    let id: String
    let name: String
}
