# Mumbli Regression Test Checklist

Run through this checklist before every release to catch regressions across all features.

**Prerequisites:**
- macOS with microphone, Accessibility, and Input Monitoring permissions granted
- Valid ElevenLabs and OpenAI API keys configured in Settings
- A text editor open (TextEdit or Notes) with cursor in a text field

---

## 1. Fn Key — Hold Mode

- [ ] **Fn hold -> overlay appears**: Press and hold Fn for 300ms+. Overlay appears at center-bottom of screen.
- [ ] **Fn release -> overlay dismisses**: Release Fn. Overlay disappears after text finalization.
- [ ] **Fn release -> text injected**: After release, transcribed/polished text appears in the active text field.
- [ ] **Fn does NOT trigger system language switch**: Pressing Fn does not open the macOS Input Sources / Globe / Emoji picker. The app consumes the event.

## 2. Fn Key — Hands-Free Mode

- [ ] **Fn double-tap -> hands-free mode activates**: Double-tap Fn within 500ms. Overlay appears and stays visible.
- [ ] **Hands-free mode persists**: Overlay remains on-screen; dictation continues without holding any key.
- [ ] **Single Fn press stops hands-free**: Press Fn once while in hands-free mode. Dictation stops, text is injected, overlay dismisses.

## 3. Overlay

- [ ] **Overlay at center-bottom**: Overlay window appears at the horizontal center, near the bottom of the main screen (UI Test: `testOverlayPositionedAtBottomOfScreen`).
- [ ] **Overlay is always-on-top**: Overlay stays visible above other windows during dictation (UI Test: `testOverlayIsFloatingAboveOtherWindows`).
- [ ] **Overlay is click-through**: Mouse clicks pass through the overlay to windows behind it.
- [ ] **Overlay dismisses after finalization**: Overlay disappears once text injection (or clipboard copy) completes (UI Test: `testOverlayDismissesAfterDictationEnds`).

## 4. VU Waveform Bars (Listening Indicator) — per `reports/vu-prominent-spec.md`

- [ ] **5 VU bars present**: Overlay contains exactly 5 waveform bars with accessibility IDs `mumbli-vu-bar-0` through `mumbli-vu-bar-4` (UI Test: `testOverlayHasFiveVUBars`).
- [ ] **Bars react to audio level (center bar tallest)**: Speak while dictating; bars visibly respond to voice volume with per-bar multipliers [0.6, 0.8, 1.0, 0.8, 0.6].
- [ ] **Bars are short when silent**: Resting height 6pt (outer bars) / 8pt (center bar). Opacity 0.7.
- [ ] **Spring animation**: response=0.10, dampingFraction=0.75. 15ms stagger from center outward.
- [ ] **Max height 24pt**: Bars reach max height at loud speech, center bar is tallest.
- [ ] **Glow effect**: When audioLevel > 0.3, accent-colored shadow appears (radius 8pt).
- [ ] **Hold mode: accent-colored bars**: In hold mode, all 5 bars use the system accent color. No REC dot visible (UI Test: `testHoldModeShowsListeningIndicator`).
- [ ] **Hands-free mode: orange bars + red REC dot**: Bars turn orange, REC dot (`mumbli-rec-dot`) visible, orange border on pill (UI Test: `testHandsFreeModeShowsRecDot`).
- [ ] **Hands-free mode: 5 bars still present**: All 5 VU bars exist in hands-free mode (UI Test: `testHandsFreeModeHasFiveVUBars`).

## 5. Processing State (UI Test: `testProcessingStateShowsIndicator`)

- [ ] **Processing indicator appears**: After Fn release, overlay transitions to a 3-dot processing indicator (`mumbli-processing-indicator`).
- [ ] **Processing dots cycle**: The 3 dots animate left-to-right at 0.3s interval.
- [ ] **Processing dismisses after completion**: Overlay dismisses once transcription + polishing completes.

## 6. Text Injection

- [ ] **Text appears in TextEdit**: Dictate with cursor in TextEdit; polished text is inserted at cursor.
- [ ] **Text appears in Notes**: Dictate with cursor in Notes; polished text is inserted at cursor.
- [ ] **Text appears in Safari text field**: Dictate into a web form input in Safari.
- [ ] **Text appears in Slack message input**: Dictate into Slack; text is not auto-sent.
- [ ] **Clipboard fallback when no text field**: Dictate with no text field focused; text is copied to clipboard and user is notified.
- [ ] **Existing content not overwritten**: Injected text is inserted at cursor, not replacing existing content.
- [ ] **Filler words removed**: Spoken "um", "uh" are not present in the injected text.
- [ ] **Punctuation and capitalization correct**: Polished text has proper grammar.

## 7. Menu Bar

- [ ] **Menu bar icon visible**: Mumbli icon appears in the macOS menu bar after launch.
- [ ] **Click -> popover opens**: Clicking the menu bar icon shows the popover with History, Settings, Quit.
- [ ] **No Dock icon**: App does not appear in the macOS Dock (LSUIElement behavior).

## 8. History

- [ ] **Dictation entries saved**: After a dictation, a new entry appears in the history list (UI Test: `testFullFlowShowsOverlayAndSavesToHistory`).
- [ ] **Most recent first**: History entries are ordered newest at top.
- [ ] **Click to copy**: Clicking a history entry copies its text to the clipboard.
- [ ] **Copy feedback shown**: Visual feedback (checkmark or highlight) appears after clicking to copy.
- [ ] **History persists across restart**: Quit and relaunch the app; history entries are still present.

## 9. Settings (UI Tests: `SettingsUITests`)

- [ ] **Settings view accessible**: Settings can be opened from the menu bar popover.
- [ ] **All sections present**: Audio Input, API Keys, Text Polishing, Shortcuts, About (UI Test: `testSettingsHasAllSections`).
- [ ] **Microphone picker works**: Audio Input section shows available microphones.

### 9a. API Keys

- [ ] **ElevenLabs field present**: ElevenLabs API key label and field visible (UI Test: `testAPIKeysHasElevenLabsAndOpenAIFields`).
- [ ] **OpenAI field present**: OpenAI API key label and field visible.
- [ ] **API keys can be entered**: ElevenLabs and OpenAI API key fields accept input (UI Test: `testAPIKeyFieldsExist`).
- [ ] **API keys persist across restart**: Enter keys, quit, relaunch; keys are still saved (stored in Keychain).
- [ ] **Invalid key shows error**: Enter a bad API key; an appropriate error is shown on next dictation attempt.

### 9b. Text Polishing

- [ ] **Enable/disable toggle**: Toggle exists and controls polishing behavior (UI Test: `testTextPolishingHasToggle`).
- [ ] **5 prompt presets**: Light cleanup, Formal, Casual, Verbatim, Custom (UI Test: `testTextPolishingHasFivePresets`).
- [ ] **3 model options**: GPT-5.4 Nano, GPT-5.4 Mini, Other (UI Test: `testTextPolishingHasThreeModels`).
- [ ] **Custom preset shows editor**: Selecting "Custom" reveals a text editor for custom prompt (UI Test: `testCustomPresetShowsTextEditor`).
- [ ] **Other model shows field**: Selecting "Other" reveals a text field for custom model ID (UI Test: `testOtherModelShowsTextField`).

### 9c. Shortcuts

- [ ] **Hold shortcut displayed**: "Hold to dictate" row shows Fn key cap.
- [ ] **Hands-free shortcut displayed**: "Hands-free mode" row shows Fn double-tap key caps.

## 10. First Launch / Permissions

- [ ] **Microphone permission requested**: On first launch (or after revoking), microphone permission dialog appears.
- [ ] **Accessibility permission guidance**: User is guided to grant Accessibility access in System Settings.
- [ ] **Works immediately after granting**: No app restart required after granting permissions.

## 11. Error Handling

- [ ] **No crash on mic disconnect**: Unplug external mic mid-dictation; app shows error, does not crash.
- [ ] **No crash on network loss**: Drop network mid-dictation; app handles gracefully with error message.
- [ ] **No crash on no text field**: Dictate with no focused text field; falls back to clipboard.

## 12. Dictation Flow Simulation (UI Tests: `DictationUITests`)

- [ ] **--test-inject does not crash**: App remains stable when injecting text with no focused field (UI Test: `testInjectDoesNotCrash`).
- [ ] **--test-full shows overlay**: Full flow simulation displays the overlay (UI Test: `testFullFlowShowsOverlayAndSavesToHistory`).
- [ ] **--test-full saves to history**: Full flow simulation creates a history entry.
- [ ] **--test-full overlay dismisses**: Overlay dismisses after injection completes (UI Test: `testFullFlowOverlayDismisses`).
- [ ] **--test-fn-hold activates overlay**: Fn hold simulation shows and dismisses overlay (UI Test: `testFnHoldShowsAndDismissesOverlay`).

---

**Date tested:** _______________
**Tester:** _______________
**Build/Commit:** _______________
**Result:** [ ] PASS / [ ] FAIL — Notes: _______________
