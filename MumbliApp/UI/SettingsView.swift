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
    @State private var groqKey: String = ""
    @State private var hasGroqKey: Bool = false
    @State private var groqMasked: String = ""
    @State private var groqSavedConfirm: Bool = false
    @State private var groqIsEditing: Bool = false

    // Polishing settings
    @State private var polishingEnabled: Bool = true
    @State private var polishingPreset: String = PolishingPreset.light.rawValue
    @State private var customPolishingPrompt: String = ""
    @State private var activePromptText: String = ""
    @State private var polishingModel: String = PolishingModel.gpt5_4_nano.rawValue
    @State private var customPolishingModel: String = ""

    // Debug settings
    @State private var saveRecordings: Bool = false
    @State private var dictationEngine: String = DictationEngine.standard.rawValue

    // Quota display
    @State private var elevenLabsQuota: String?
    @State private var elevenLabsQuotaWarning: Bool = false
    @State private var isCheckingQuota: Bool = false

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

                            // ElevenLabs quota display
                            if hasElevenLabsKey {
                                VStack(alignment: .leading, spacing: 4) {
                                    if isCheckingQuota {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                                .frame(width: 12, height: 12)
                                            Text("Checking...")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                    } else if let quota = elevenLabsQuota {
                                        HStack(spacing: 6) {
                                            Image(systemName: elevenLabsQuotaWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(elevenLabsQuotaWarning ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen))
                                            Text(quota)
                                                .font(.system(size: 11))
                                                .foregroundColor(elevenLabsQuotaWarning ? Color(nsColor: .systemOrange) : .secondary)
                                            Spacer()
                                            Button(action: checkElevenLabsQuota) {
                                                Text("Refresh")
                                                    .font(.system(size: 11))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.accentColor)
                                        }
                                    } else {
                                        HStack {
                                            Spacer()
                                            Button(action: checkElevenLabsQuota) {
                                                Text("Check quota")
                                                    .font(.system(size: 11))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }

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

                            Divider().opacity(0.1)

                            // Groq row
                            APIKeyRow(
                                serviceName: "Groq",
                                iconName: "bolt.fill",
                                placeholder: "gsk_...paste key",
                                keyText: $groqKey,
                                isSet: hasGroqKey,
                                maskedValue: groqMasked,
                                isEditing: $groqIsEditing,
                                savedConfirm: groqSavedConfirm,
                                accessibilityID: "mumbli-groq-key",
                                onCommit: { commitGroqKey() }
                            )
                            .accessibilityLabel("Groq API Key, \(hasGroqKey ? "configured" : "not set")")

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

                    // Text Polishing section
                    SettingsSection(title: "Text Polishing", icon: "wand.and.stars") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Enable/disable toggle
                            Toggle("Enable text polishing", isOn: $polishingEnabled)
                                .font(.system(size: 13))
                                .onChange(of: polishingEnabled) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "polishingEnabled")
                                }

                            if polishingEnabled {
                                Divider().opacity(0.1)

                                // Prompt preset picker
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prompt preset")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Picker("Preset", selection: $polishingPreset) {
                                        ForEach(PolishingPreset.allCases) { preset in
                                            Text(preset.displayName).tag(preset.rawValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .onChange(of: polishingPreset) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "polishingPreset")
                                    }
                                }

                                // Prompt editor — always visible, shows preset prompt or custom
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prompt")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    ZStack(alignment: .topLeading) {
                                        if activePromptText.isEmpty {
                                            Text("Enter your polishing prompt...")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary.opacity(0.5))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 8)
                                        }
                                        TextEditor(text: $activePromptText)
                                            .font(.system(size: 12))
                                            .frame(height: 80)
                                            .scrollContentBackground(.hidden)
                                            .onChange(of: activePromptText) { newValue in
                                                // Save edits — if user modifies a preset, switch to custom
                                                UserDefaults.standard.set(newValue, forKey: "customPolishingPrompt")
                                            }
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .textBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                                .onChange(of: polishingPreset) { newValue in
                                    // When preset changes, load its prompt into the editor
                                    if let preset = PolishingPreset(rawValue: newValue), preset != .custom {
                                        activePromptText = preset.prompt
                                        UserDefaults.standard.set(activePromptText, forKey: "customPolishingPrompt")
                                    }
                                }

                                Divider().opacity(0.1)

                                // Model selector
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Model")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Picker("Model", selection: $polishingModel) {
                                        ForEach(PolishingModel.allCases) { model in
                                            Text(model.displayName).tag(model.rawValue)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .onChange(of: polishingModel) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "polishingModel")
                                    }
                                }

                                // Custom model field
                                if polishingModel == PolishingModel.other.rawValue {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Custom model ID")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                        TextField("e.g. gpt-4-turbo", text: $customPolishingModel)
                                            .font(.system(size: 12, design: .monospaced))
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: customPolishingModel) { newValue in
                                                UserDefaults.standard.set(newValue, forKey: "customPolishingModel")
                                            }
                                    }
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

                    // Debug section
                    SettingsSection(title: "Debug", icon: "ant.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            // Engine picker
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Engine")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Picker("Engine", selection: $dictationEngine) {
                                    ForEach(DictationEngine.allCases) { engine in
                                        Text(engine.displayName).tag(engine.rawValue)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .onChange(of: dictationEngine) { newValue in
                                    UserDefaults.standard.set(newValue, forKey: "dictationEngine")
                                    if let engine = DictationEngine(rawValue: newValue) {
                                        polishingModel = engine.defaultPolishModel
                                        UserDefaults.standard.set(engine.defaultPolishModel, forKey: "polishingModel")
                                    }
                                }
                                Text(DictationEngine(rawValue: dictationEngine)?.engineDescription ?? "")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Divider().opacity(0.1)

                            // Save recordings toggle
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Save recordings", isOn: $saveRecordings)
                                    .font(.system(size: 13))
                                    .onChange(of: saveRecordings) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "debugSaveRecordings")
                                    }

                                Text("Saves each dictation as a WAV file for benchmarking")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
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
            loadPolishingSettings()
            saveRecordings = UserDefaults.standard.bool(forKey: "debugSaveRecordings")
            dictationEngine = UserDefaults.standard.string(forKey: "dictationEngine") ?? DictationEngine.standard.rawValue
            if hasElevenLabsKey { checkElevenLabsQuota() }
        }
    }

    private func loadAudioDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )

        audioDevices = discoverySession.devices
            .filter { !$0.localizedName.hasPrefix("CADefaultDevice") }
            .map { device in
                AudioDevice(id: device.uniqueID, name: device.localizedName)
            }

        if selectedDeviceID.isEmpty, let defaultDevice = AVCaptureDevice.default(for: .audio) {
            selectedDeviceID = defaultDevice.uniqueID
        }
    }

    private func loadPolishingSettings() {
        polishingEnabled = UserDefaults.standard.object(forKey: "polishingEnabled") as? Bool ?? true
        polishingPreset = UserDefaults.standard.string(forKey: "polishingPreset") ?? PolishingPreset.light.rawValue
        customPolishingPrompt = UserDefaults.standard.string(forKey: "customPolishingPrompt") ?? ""
        // Load active prompt text — if custom prompt exists use it, otherwise load preset's prompt
        if let preset = PolishingPreset(rawValue: polishingPreset), preset != .custom {
            activePromptText = customPolishingPrompt.isEmpty ? preset.prompt : customPolishingPrompt
        } else {
            activePromptText = customPolishingPrompt
        }
        polishingModel = UserDefaults.standard.string(forKey: "polishingModel") ?? PolishingModel.gpt5_4_nano.rawValue
        customPolishingModel = UserDefaults.standard.string(forKey: "customPolishingModel") ?? ""
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
        if let key = KeychainManager.shared.get(key: KeychainManager.groqAPIKeyKey) {
            hasGroqKey = true
            groqMasked = Self.maskKey(key)
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

    private func commitGroqKey() {
        let trimmed = groqKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if hasGroqKey {
                KeychainManager.shared.delete(key: KeychainManager.groqAPIKeyKey)
                hasGroqKey = false
                groqMasked = ""
            }
        } else {
            try? KeychainManager.shared.save(key: KeychainManager.groqAPIKeyKey, value: trimmed)
            hasGroqKey = true
            groqMasked = Self.maskKey(trimmed)
            groqKey = ""
            groqIsEditing = false
            groqSavedConfirm = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { groqSavedConfirm = false }
        }
    }

    private func checkElevenLabsQuota() {
        guard let apiKey = KeychainManager.shared.get(key: KeychainManager.elevenLabsAPIKeyKey) else { return }
        isCheckingQuota = true
        elevenLabsQuota = nil

        Task {
            do {
                var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
                request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    await MainActor.run {
                        elevenLabsQuota = "Unable to check — verify API key"
                        elevenLabsQuotaWarning = true
                        isCheckingQuota = false
                    }
                    return
                }

                let tier = (json["tier"] as? String ?? "unknown").capitalized
                let status = json["status"] as? String ?? "unknown"
                let resetUnix = json["next_character_count_reset_unix"] as? TimeInterval
                let isActive = status == "active"

                // Format reset date
                var resetLabel = ""
                if let resetUnix = resetUnix {
                    let resetDate = Date(timeIntervalSince1970: resetUnix)
                    let formatter = RelativeDateTimeFormatter()
                    formatter.unitsStyle = .abbreviated
                    resetLabel = " \u{00B7} resets \(formatter.localizedString(for: resetDate, relativeTo: Date()))"
                }

                let finalResetLabel = resetLabel
                await MainActor.run {
                    if isActive {
                        elevenLabsQuota = "\(tier) plan \u{00B7} active\(finalResetLabel)"
                        elevenLabsQuotaWarning = false
                    } else {
                        elevenLabsQuota = "\(tier) plan \u{00B7} \(status)"
                        elevenLabsQuotaWarning = true
                    }
                    isCheckingQuota = false
                }
            } catch {
                await MainActor.run {
                    elevenLabsQuota = "Check failed"
                    elevenLabsQuotaWarning = true
                    isCheckingQuota = false
                }
            }
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
