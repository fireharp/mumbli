# Mumbli Manual Test Checklist

All manual tests require a Mac with microphone, accessibility permissions granted, and a running backend.

---

## Prerequisites

- [ ] Mumbli app installed and launched
- [ ] Microphone permission granted
- [ ] Accessibility permission granted
- [ ] Input Monitoring permission granted
- [ ] Backend server running and reachable
- [ ] Valid auth token / user account

---

## MAN-01: Fn Hold Mode with Actual Speech

**Story**: US-1 (Hold Mode Dictation)

1. Open Notes and place cursor in a new note
2. Press and hold Fn key
3. Wait for overlay to appear (~300ms)
4. Speak clearly: "Hello, this is a test of hold mode dictation"
5. Release Fn key
6. **Verify**:
   - [ ] Overlay appeared near the cursor while Fn was held
   - [ ] Overlay showed listening indicator (waveform or pulsing dot)
   - [ ] After release, text appeared in the note within 3 seconds
   - [ ] Text is polished (proper capitalization, punctuation)
   - [ ] Overlay dismissed after text injection
   - [ ] Entry appears in dictation history

---

## MAN-02: Fn Double-Tap Hands-Free Mode

**Story**: US-2 (Hands-Free Mode Dictation)

1. Open Notes and place cursor in a new note
2. Double-tap Fn key quickly (within ~500ms)
3. Speak: "This is a hands-free test. I can take my time speaking without holding any keys."
4. Wait a few seconds (verify no silence timeout)
5. Press Fn once to stop
6. **Verify**:
   - [ ] Hands-free mode activated on double-tap
   - [ ] Overlay stayed visible throughout entire session
   - [ ] No automatic timeout during silence
   - [ ] Single Fn press stopped dictation
   - [ ] Polished text injected into note
   - [ ] Entry saved to history

---

## MAN-03: Text Injection — Safari

**Story**: US-3 (Universal Text Input)

1. Open Safari, navigate to a page with a text input (e.g., Google search bar)
2. Click in the text field
3. Activate dictation (hold Fn), speak "Search for Mumbli voice dictation", release
4. **Verify**:
   - [ ] Text injected at cursor position in Safari
   - [ ] No extra text or artifacts
   - [ ] Overlay appeared near the text field

---

## MAN-04: Text Injection — Notes

**Story**: US-3

1. Open Notes, place cursor in an existing note with content
2. Activate dictation, speak a sentence, release
3. **Verify**:
   - [ ] Text inserted at cursor position
   - [ ] Existing note content not overwritten
   - [ ] Cursor moves to end of injected text

---

## MAN-05: Text Injection — Slack

**Story**: US-3

1. Open Slack desktop app, go to a DM or channel
2. Click in the message input
3. Activate dictation, speak "Hey, just testing voice input", release
4. **Verify**:
   - [ ] Text appears in Slack message input
   - [ ] Text is not auto-sent (user still controls Enter)
   - [ ] Formatting preserved

---

## MAN-06: Text Injection — VS Code

**Story**: US-3

1. Open VS Code with a file open
2. Place cursor at a specific line
3. Activate dictation, speak "add a comment here", release
4. **Verify**:
   - [ ] Text injected at cursor position in the editor
   - [ ] No disruption to existing code
   - [ ] Works with both AX API and clipboard fallback

---

## MAN-07: Text Injection — Terminal

**Story**: US-3

1. Open Terminal, ensure cursor is at command prompt
2. Activate dictation, speak "list all files", release
3. **Verify**:
   - [ ] Text appears at Terminal prompt
   - [ ] Command is not auto-executed
   - [ ] Works via clipboard fallback if AX not available

---

## MAN-08: Text Injection — Chrome

**Story**: US-3

1. Open Chrome, navigate to a form or text area
2. Activate dictation, speak a sentence, release
3. **Verify**:
   - [ ] Text injected into Chrome text field
   - [ ] Works with both standard inputs and contenteditable areas

---

## MAN-09: Text Injection — Mail

**Story**: US-3

1. Open Mail, compose a new email
2. Click in the body field
3. Activate dictation, speak a few sentences, release
4. **Verify**:
   - [ ] Text appears in email body
   - [ ] No formatting corruption
   - [ ] Subject field also works if focused

---

## MAN-10: Extended Dictation Session

**Story**: US-4 (Accessibility)

1. Open a document (Notes or Pages)
2. Activate hands-free mode (double-tap Fn)
3. Dictate continuously for 5+ minutes
4. Press Fn to stop
5. **Verify**:
   - [ ] No audio dropout during long session
   - [ ] Polished text is complete (no truncation)
   - [ ] App remains responsive throughout
   - [ ] Memory usage stable (no leaks)
   - [ ] Finalization completes within reasonable time

---

## MAN-11: Quick Reply in Messaging App

**Story**: US-6 (Quick Replies)

1. Open a messaging app (Slack, Messages, or WhatsApp web)
2. Be in a conversation with messages visible
3. Hold Fn, speak a short reply like "Sounds good, see you at three", release
4. **Verify**:
   - [ ] Text appears quickly in the message input
   - [ ] Tone is natural (not overly formal)
   - [ ] Filler words removed if any were spoken
   - [ ] Ready to send immediately

---

## MAN-12: Microphone Permission Denied

**Story**: US-12 (Error — No Microphone)

1. Go to System Settings > Privacy & Security > Microphone
2. Deny microphone access for Mumbli
3. Try to activate dictation
4. **Verify**:
   - [ ] Error shown in overlay
   - [ ] Message prompts to check System Settings
   - [ ] App does not crash
   - [ ] After re-granting permission, dictation works without restart

---

## MAN-13: Microphone Disconnected Mid-Dictation

**Story**: US-12

1. Use an external USB microphone
2. Start dictation (hold Fn)
3. While speaking, unplug the microphone
4. **Verify**:
   - [ ] Error shown to user
   - [ ] No crash or hang
   - [ ] Partial audio (if any) handled gracefully

---

## MAN-14: Dictation with No Text Field Focused

**Story**: US-14 (Error — No Text Field)

1. Click on the desktop (no app in focus) or on an area with no text field
2. Activate dictation, speak a sentence, stop
3. **Verify**:
   - [ ] Dictation proceeds normally (overlay appears, recording works)
   - [ ] Polished text copied to clipboard
   - [ ] Entry saved to dictation history
   - [ ] User informed that text was copied to clipboard

---

## MAN-15: Switch Apps During Dictation

**Story**: US-15 (App Loses Focus)

1. Open Notes and place cursor in a note
2. Activate hands-free mode (double-tap Fn)
3. Start speaking
4. While still dictating, Cmd+Tab to switch to another app
5. Press Fn to stop
6. **Verify**:
   - [ ] Dictation continued during app switch
   - [ ] Text injected (into focused field or clipboard fallback)
   - [ ] No crash or lost audio
   - [ ] Entry saved to history

---

## MAN-16: First Launch Permission Flow

**Story**: US-10 (First Launch)

1. Delete Mumbli from Accessibility and Microphone permissions (simulate fresh install)
2. Launch Mumbli
3. **Verify**:
   - [ ] Microphone permission dialog appears
   - [ ] Accessibility permission guidance is shown (with link/instructions to System Settings)
   - [ ] After granting both, Fn key works immediately
   - [ ] No restart required

---

## MAN-17: Overlay Position in Various Apps

**Story**: US-9 (Overlay Indicator)

1. Test dictation in each of: Notes, Safari, VS Code, Slack
2. For each, note where the overlay appears
3. **Verify**:
   - [ ] Overlay appears near the active text cursor (not in a fixed position)
   - [ ] Overlay does not obscure the text being entered
   - [ ] Overlay is always-on-top (visible even if other windows overlap)
   - [ ] Overlay is click-through when not showing listening state

---

## MAN-18: Long Stream-of-Consciousness Dictation

**Story**: US-5 (Thinking Out Loud)

1. Open a blank document
2. Activate hands-free mode
3. Speak naturally for 2-3 minutes with pauses, filler words, self-corrections:
   "So um I was thinking about the project and uh we should probably move the deadline to Friday, actually no Thursday would be better because um..."
4. Stop dictation
5. **Verify**:
   - [ ] Filler words (um, uh) removed
   - [ ] Self-corrections resolved ("Friday, actually no Thursday" -> "Thursday")
   - [ ] Grammar and punctuation cleaned up
   - [ ] Original meaning and voice preserved
   - [ ] Text is readable as coherent prose
