# Mumbli User Stories

## US-1: Hold Mode Dictation

**As a** Mac user,
**I want to** hold the Fn key and speak,
**so that** my speech is transcribed and inserted into the active text field when I release.

### Acceptance Criteria
- [ ] Holding Fn for >300ms enters hold mode and starts recording
- [ ] Overlay with listening indicator appears near the active cursor
- [ ] Releasing Fn stops recording and triggers finalization
- [ ] Polished text is injected at the cursor position in the active text field
- [ ] Entry is saved to dictation history with timestamp
- [ ] Overlay dismisses after text injection

---

## US-2: Hands-Free Mode Dictation

**As a** user who needs hands-free input,
**I want to** double-tap Fn to start continuous dictation and tap Fn once to stop,
**so that** I can dictate without holding a key.

### Acceptance Criteria
- [ ] Double-tapping Fn (within ~500ms) enters hands-free mode
- [ ] Dictation continues until Fn is pressed again
- [ ] No silence timeout — user controls stop explicitly
- [ ] Finalization (polishing + injection) happens after stop
- [ ] Overlay stays visible for the entire hands-free session

---

## US-3: Universal Text Input

**As a** user working across multiple apps,
**I want to** dictate into any text field on macOS (browser, email, Slack, Notes, IDE, terminal),
**so that** I don't need app-specific setup.

### Acceptance Criteria
- [ ] Text injection works via Accessibility API (AXUIElement) as primary method
- [ ] Clipboard paste (Cmd+V) is used as fallback when AX fails
- [ ] Works in: Safari, Chrome, Mail, Notes, Slack, VS Code, Terminal, Pages
- [ ] Text is inserted at the current cursor position, not replacing existing content
- [ ] If no text field is focused, text is copied to clipboard and saved to history

---

## US-4: Accessibility Use Case

**As a** user with limited typing ability (RSI, physical limitation, temporary injury),
**I want to** use Mumbli as my primary text input method,
**so that** I can use my Mac without relying on the keyboard.

### Acceptance Criteria
- [ ] Dictation is reliable — works on first activation without retries
- [ ] Latency from stop to text appearance is under 3 seconds
- [ ] No dropped audio or missed words in normal conditions
- [ ] Both hold mode and hands-free mode are always available without configuration
- [ ] App runs continuously in background without degradation

---

## US-5: Thinking Out Loud

**As a** user brainstorming or journaling,
**I want to** speak a stream of consciousness and get cleaned-up text,
**so that** my raw thoughts are readable without losing their meaning.

### Acceptance Criteria
- [ ] Filler words (um, uh, like, you know) are removed
- [ ] Basic grammar and punctuation are fixed
- [ ] Self-corrections are resolved (e.g., "at 4 pm, actually 3 pm" becomes "at 3 pm")
- [ ] The user's voice and intent are preserved — no heavy rewriting
- [ ] Long dictations are handled without timeout or truncation

---

## US-6: Quick Replies

**As a** user in a messaging app or email,
**I want to** speak a short reply and have it inserted naturally,
**so that** I can respond faster than typing.

### Acceptance Criteria
- [ ] Short dictations (a few words to a sentence) are polished and injected quickly
- [ ] Tone is preserved — polishing keeps it natural
- [ ] Works in messaging apps (Slack, Messages, WhatsApp web) and email clients

---

## US-7: Dictation History

**As a** user,
**I want to** view and reuse my past dictations from the menu bar,
**so that** I can copy previous text without re-dictating.

### Acceptance Criteria
- [ ] Menu bar dropdown shows scrollable history list, most recent first
- [ ] Each entry shows: truncated text preview + timestamp
- [ ] Clicking an entry copies full text to clipboard (pasteboard)
- [ ] Visual feedback on copy (checkmark or brief highlight)
- [ ] History persists across app restarts (stored locally)
- [ ] History is accessible even when no text field is focused

---

## US-8: Menu Bar App

**As a** user,
**I want** Mumbli to live in the menu bar with no Dock icon,
**so that** it stays out of the way while being quickly accessible.

### Acceptance Criteria
- [ ] App appears as a menu bar icon only — no Dock icon
- [ ] Clicking the menu bar icon shows dropdown with: history, settings, quit
- [ ] Settings allow microphone selection
- [ ] Quit option exits the app cleanly

---

## US-9: Overlay Indicator

**As a** user,
**I want to** see a small visual indicator when Mumbli is listening,
**so that** I know dictation is active.

### Acceptance Criteria
- [ ] Overlay is a small floating indicator (waveform or pulsing dot)
- [ ] Appears near the active text cursor
- [ ] No text preview — listening indicator only
- [ ] Semi-transparent background, minimal chrome
- [ ] Always-on-top, click-through when inactive
- [ ] Dismisses automatically after text injection

---

## US-10: First Launch Experience

**As a** new user,
**I want** the app to guide me through required permissions on first launch,
**so that** I can start using Mumbli immediately.

### Acceptance Criteria
- [ ] App requests Microphone permission on first launch
- [ ] App requests Accessibility permission and guides user to System Settings
- [ ] After permissions are granted, Fn key works immediately
- [ ] Clear messaging about why each permission is needed

---

## US-11: Multi-Language Support

**As a** user who speaks multiple languages,
**I want** Mumbli to detect my language automatically,
**so that** I can dictate without switching settings.

### Acceptance Criteria
- [ ] Language detection is automatic (handled by ElevenLabs)
- [ ] No manual language selection required
- [ ] Polishing handles non-English text appropriately

---

## US-12: Error — No Microphone

**As a** user whose microphone is unavailable or permission is denied,
**I want** clear feedback about the problem,
**so that** I know what to fix.

### Acceptance Criteria
- [ ] Error shown in overlay if microphone is unavailable
- [ ] Message prompts user to check System Settings
- [ ] App does not crash or hang

---

## US-13: Error — No Network

**As a** user who loses network connectivity,
**I want** Mumbli to handle the failure gracefully,
**so that** I don't lose my dictation.

### Acceptance Criteria
- [ ] Audio is cached locally if network fails mid-dictation
- [ ] Retry is attempted when connection restores, or error is shown
- [ ] User is informed of the network issue
- [ ] No silent failures — user always knows what happened

---

## US-14: Error — No Text Field Focused

**As a** user who activates dictation without a text field in focus,
**I want** my dictation to still be captured,
**so that** I don't lose what I said.

### Acceptance Criteria
- [ ] Dictation proceeds even without a focused text field
- [ ] Polished text is copied to clipboard
- [ ] Entry is saved to dictation history
- [ ] User is informed that text was copied to clipboard (not injected)

---

## US-15: App Loses Focus During Dictation

**As a** user who switches apps while dictating,
**I want** dictation to continue and complete,
**so that** I don't lose my speech.

### Acceptance Criteria
- [ ] Dictation continues if the active app changes mid-session
- [ ] Text is injected into the text field when done (or clipboard fallback)
- [ ] No crash or silent failure on focus loss

---

## US-16: WebSocket Connection

**As a** user,
**I want** audio to be streamed to the backend in real time,
**so that** transcription is fast and responsive.

### Acceptance Criteria
- [ ] WebSocket connection to /ws/transcribe is established on dictation start
- [ ] Auth token is sent as first text frame
- [ ] Audio chunks are sent as binary frames (PCM 16-bit 16kHz mono)
- [ ] "start" and "stop" text frames control the session
- [ ] Server responds with "listening", "final", or "error" frames
- [ ] Connection is closed cleanly after finalization
