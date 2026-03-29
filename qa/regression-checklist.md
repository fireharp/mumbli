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

- [ ] **Overlay at center-bottom**: Overlay window appears at the horizontal center, near the bottom of the main screen.
- [ ] **Overlay is always-on-top**: Overlay stays visible above other windows during dictation.
- [ ] **Overlay is click-through**: Mouse clicks pass through the overlay to windows behind it.
- [ ] **Overlay dismisses after finalization**: Overlay disappears once text injection (or clipboard copy) completes.

## 4. Dot Animation (Listening Indicator) — per `reports/dot-animation-spec.md`

- [ ] **Dots react to actual mic input**: Speak while dictating; dots visibly respond to voice volume (scale 1.0-1.6x proportional to audioLevel).
- [ ] **Dots are nearly still when silent**: audioLevel < 0.02: scale 1.0 with random micro-jitter up to 1.02 max. Opacity constant 0.55. **No breathing pulse, no easeInOut cycle, no opacity pulsing.**
- [ ] **Spring animation**: response=0.10, dampingFraction=0.75, blendDuration=0. Single spring for ALL transitions (no animation system switching).
- [ ] **No brightness/white shift**: Dots remain solid Color.accentColor at all volume levels. No `.brightness()` modifier.
- [ ] **Speech opacity**: 0.6 + (audioLevel * 0.4), range 0.6-1.0.
- [ ] **Dot stagger (ripple)**: Left-to-right ripple via circular buffer (dot 0 = current level, dot 1 = 1 tick ago, dot 2 = 2 ticks ago). No stagger during silence. *[FOLLOW-UP: not yet implemented, designer approved as non-blocking polish item]*
- [ ] **Max scale 1.6x (not 1.8x)**: Dots must not visually merge at loud volumes.

## 5. Text Injection

- [ ] **Text appears in TextEdit**: Dictate with cursor in TextEdit; polished text is inserted at cursor.
- [ ] **Text appears in Notes**: Dictate with cursor in Notes; polished text is inserted at cursor.
- [ ] **Text appears in Safari text field**: Dictate into a web form input in Safari.
- [ ] **Text appears in Slack message input**: Dictate into Slack; text is not auto-sent.
- [ ] **Clipboard fallback when no text field**: Dictate with no text field focused; text is copied to clipboard and user is notified.
- [ ] **Existing content not overwritten**: Injected text is inserted at cursor, not replacing existing content.
- [ ] **Filler words removed**: Spoken "um", "uh" are not present in the injected text.
- [ ] **Punctuation and capitalization correct**: Polished text has proper grammar.

## 6. Menu Bar

- [ ] **Menu bar icon visible**: Mumbli icon appears in the macOS menu bar after launch.
- [ ] **Click -> popover opens**: Clicking the menu bar icon shows the popover with History, Settings, Quit.
- [ ] **No Dock icon**: App does not appear in the macOS Dock (LSUIElement behavior).

## 7. History

- [ ] **Dictation entries saved**: After a dictation, a new entry appears in the history list.
- [ ] **Most recent first**: History entries are ordered newest at top.
- [ ] **Click to copy**: Clicking a history entry copies its text to the clipboard.
- [ ] **Copy feedback shown**: Visual feedback (checkmark or highlight) appears after clicking to copy.
- [ ] **History persists across restart**: Quit and relaunch the app; history entries are still present.

## 8. Settings / API Keys

- [ ] **Settings view accessible**: Settings can be opened from the menu bar popover.
- [ ] **API keys can be entered**: ElevenLabs and OpenAI API key fields accept input.
- [ ] **API keys persist across restart**: Enter keys, quit, relaunch; keys are still saved (stored in Keychain).
- [ ] **Invalid key shows error**: Enter a bad API key; an appropriate error is shown on next dictation attempt.

## 9. First Launch / Permissions

- [ ] **Microphone permission requested**: On first launch (or after revoking), microphone permission dialog appears.
- [ ] **Accessibility permission guidance**: User is guided to grant Accessibility access in System Settings.
- [ ] **Works immediately after granting**: No app restart required after granting permissions.

## 10. Error Handling

- [ ] **No crash on mic disconnect**: Unplug external mic mid-dictation; app shows error, does not crash.
- [ ] **No crash on network loss**: Drop network mid-dictation; app handles gracefully with error message.
- [ ] **No crash on no text field**: Dictate with no focused text field; falls back to clipboard.

---

**Date tested:** _______________
**Tester:** _______________
**Build/Commit:** _______________
**Result:** [ ] PASS / [ ] FAIL — Notes: _______________
