# Mumbli Settings -- API Keys Section Design Spec

> Reference apps: macOS System Settings (Internet Accounts), Raycast API key fields, 1Password vault entries

---

## 1. Position in Settings Order

The API Keys section goes **between Audio Input and Shortcuts**.

Audio Input configures *how* audio is captured; API Keys configures *where* it is sent for processing. These two sections form the "setup" group -- both must be configured before dictation works. Shortcuts and About are informational/reference sections and belong below.

```
[Audio Input card]
    16px gap
[API Keys card]      <-- new
    16px gap
[Shortcuts card]
    16px gap
[About card]
```

---

## 2. Section Header

Uses the existing `SettingsSection` component:

| Property | Value |
|----------|-------|
| Title | "API Keys" |
| Icon | `key.fill` (SF Symbols) |
| Style | 12pt small caps semibold, `secondaryLabelColor` -- matches all other section headers |

---

## 3. Card Layout

The card contains two key rows stacked vertically with a `Divider()` between them. Each row follows the same structure.

```
+--------------------------------------------------+
|  API KEYS                                        |
| +----------------------------------------------+ |
| |  [icon] ElevenLabs          [status] [field] | |
| |----------------------------------------------| |
| |  [icon] OpenAI              [status] [field] | |
| +----------------------------------------------+ |
+--------------------------------------------------+
```

### Row structure (per key)

```
HStack(spacing: 10) {
    [Service icon]    -- 14pt, secondaryLabelColor
    [Service name]    -- 13pt regular, primary
    Spacer()
    [Status dot]      -- 6px circle
    [SecureField]     -- native password field
}
```

Vertical spacing between rows: **12px**, with a `Divider().opacity(0.1)` separator.

---

## 4. SecureField Appearance

Use a native `SecureField` for macOS-standard password field behavior (bullet masking, system paste support, password manager integration).

| Property | Value |
|----------|-------|
| Placeholder | `"sk-...paste key"` (ElevenLabs: `"xi-...paste key"`) |
| Font | `.system(size: 12, design: .monospaced)` |
| Width | `frame(width: 180)` -- fixed width so rows align |
| Style | `.textFieldStyle(.roundedBorder)` -- native macOS bordered input |
| Padding | Default native padding (do not override) |

When a key is already saved, the field displays a masked placeholder (e.g., `"xi-****...7f2a"`) showing only the prefix and last 4 characters. The actual key value is never displayed in full. Clicking into the field clears the masked display and allows pasting a new key.

---

## 5. Status Indicator

A **6px circle** to the left of the SecureField, matching the Audio Input microphone status dot pattern already in the design system.

| State | Color | Meaning |
|-------|-------|---------|
| Key saved and valid | `Color(nsColor: .systemGreen)` | Key is configured |
| Key missing | `Color(nsColor: .systemOrange)` | Key needs to be set |

Orange (not red) for the missing state -- a missing key is a setup step, not an error. Red should be reserved for actual failures (e.g., key rejected by the API).

---

## 6. Save Interaction

**Auto-save on commit (press Return or blur).**

No explicit "Save" button. Rationale:
- The Audio Input picker already auto-saves on selection change (via `onChange` writing to `UserDefaults`). API keys should follow the same implicit-save pattern for consistency.
- An explicit save button adds a click, adds a state to manage (dirty/clean), and creates the possibility of forgetting to save.

### Save flow

1. User pastes or types a key into the SecureField.
2. On field commit (Return key) or focus loss (blur), the key is saved to the macOS Keychain (not UserDefaults -- keys are secrets).
3. The status dot transitions from orange to green.
4. A brief inline confirmation appears below the field: `"Key saved"` in 11pt `systemGreen`, fading out after 2 seconds with a `.opacity` animation.

### Clearing a key

If the user clears the field and commits, the stored key is removed from Keychain and the status dot returns to orange.

---

## 7. Test Button

**No test button in v1.**

Rationale:
- Testing requires a network call to each provider's API, adding latency and error states to a simple settings form.
- A "Test" button that fails due to network issues (not key issues) creates confusion.
- The key will be validated on first use (dictation attempt), which is a more natural feedback point.

**Future consideration:** If users report confusion about whether their key works, add a small `"Verify"` link (not button) to the right of the status dot that triggers a lightweight API ping and shows a transient checkmark or error inline.

---

## 8. Missing Key Warning on Dictation

When the user attempts to dictate (holds Fn) without a required API key configured, show a warning in the **listening overlay**, not in settings.

| Property | Value |
|----------|-------|
| Message | `"API key required -- open Settings to add your [ElevenLabs/OpenAI] key"` |
| Style | 12pt regular, `systemOrange` color |
| Position | Below the waveform in the listening overlay |
| Duration | Persistent while overlay is visible |
| Action | Clicking the message opens the Settings window with the API Keys section visible |

This is preferable to a modal alert because:
- It appears in context (the user just tried to dictate).
- It does not require dismissal.
- It provides a direct path to fix the issue.

Additionally, show a **subtle hint in the settings card itself** when a key is missing:

```
HStack(spacing: 4) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 11))
        .foregroundColor(Color(nsColor: .systemOrange))
    Text("Required for dictation")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
}
```

This mirrors the existing "No audio input devices found" warning pattern in the Audio Input section.

---

## 9. Window Size Impact

The new section adds approximately **80px** of height. Update the window constraints:

| Property | Current | Proposed |
|----------|---------|----------|
| Min height | 400px | **480px** |
| Max height | 520px | **600px** |

The `ScrollView` safety net already exists and will handle overflow if content exceeds max height.

---

## 10. Dark Mode

All tokens used are system-adaptive (same as existing sections):

| Element | Token |
|---------|-------|
| Card background | `controlBackgroundColor` |
| Field border | Native `roundedBorder` style (auto-adapts) |
| Status dots | `systemGreen`, `systemOrange` (adaptive) |
| Text | `.primary`, `.secondary` (adaptive) |

No `@Environment(\.colorScheme)` branching needed.

---

## 11. Accessibility

- Each `SecureField` gets an `accessibilityIdentifier`: `"mumbli-elevenlabs-key"`, `"mumbli-openai-key"`.
- Each row gets an `accessibilityLabel`: `"ElevenLabs API Key, [status]"` where status is "configured" or "not set".
- The status dots are decorative (the label carries the state), so mark them with `accessibilityHidden(true)`.

---

## 12. Security

- API keys are stored in the **macOS Keychain** via `Security.framework`, not in `UserDefaults` or plain files.
- Keys are never logged, printed to console, or included in crash reports.
- The masked display (`"xi-****...7f2a"`) is generated from the stored key on read -- the full key is only held in memory during the save operation.

---

## Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Position | After Audio Input, before Shortcuts | Groups "setup" sections together |
| Field style | Native `SecureField` with `roundedBorder` | macOS-standard, supports password managers |
| Status indicator | 6px dot (green/orange) | Matches existing Audio Input pattern |
| Test button | None in v1 | Avoid network complexity in settings |
| Save interaction | Auto-save on blur/commit | Matches Audio Input picker pattern |
| Missing key warning | Inline in overlay + hint in settings | Contextual, non-modal |
| Storage | macOS Keychain | Keys are secrets, not preferences |
