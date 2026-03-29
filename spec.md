# Mumbli — Product Specification

> Voice-to-text for macOS. Speak into any text field, get clean text.
> Inspired by [Wispr Flow](https://wisprflow.ai/). Stripped to essentials.

---

## 1. Product Overview

Mumbli is a macOS-native voice-to-text app. It runs as a system overlay that lets you dictate into any text field on your Mac. Speech is transcribed via ElevenLabs, lightly polished by a small LLM (GPT-4o-mini or equivalent), and injected at the cursor.

**Core loop**: Hold Fn (or double-tap Fn to lock) → speak → polished text appears in the active text field.

Multi-language works out of the box — ElevenLabs handles language detection automatically.

---

## 2. Core Features

### 2.1 Dictation Engine
- Real-time speech-to-text via ElevenLabs STT
- Works in any text field across any macOS application (via Accessibility API)
- Automatic language detection (multi-language supported natively by STT provider)

### 2.2 Light Text Polishing
- Simple LLM pass (GPT-4o-mini or similar small/fast model) on final transcription
- Removes filler words ("um", "uh")
- Fixes basic grammar and punctuation
- Structures rambled speech into cleaner sentences
- NOT heavy rewriting — preserves the user's voice and intent
- Handles self-corrections (e.g., "at 4 pm, actually 3 pm" → "at 3 pm")

### 2.3 System Overlay
- Floating UI element near the active text field
- Shows listening indicator only (waveform or pulsing dot) — no live transcription text
- Non-intrusive — disappears after dictation ends
- Always-on-top, click-through when inactive

### 2.4 Dictation History
- All dictations are saved locally with timestamp
- Accessible from menu bar dropdown
- Each history entry: click to copy to clipboard (pasteboard)
- Simple scrollable list, most recent first
- Persistent across app restarts (stored locally)

---

## 3. Platform

**macOS only** — Apple Silicon (M1+) and Intel.

---

## 4. User Scenarios

### 4.1 Universal Text Input
The primary scenario: user is in any app (browser, email, Slack, Notes, IDE, terminal, etc.), activates Mumbli, speaks, and text appears. No app-specific setup, no integrations. If there's a text cursor, Mumbli works there.

### 4.2 Accessibility
Users who can't type comfortably (RSI, physical limitations, temporary injury) use Mumbli as their primary text input method. This is the most important use case to get right — it needs to be reliable, fast, and low-friction.

### 4.3 Thinking Out Loud
User speaks a stream of consciousness into a note or document. The light polishing cleans it up enough to be readable without losing the raw thought. Good for brainstorming, journaling, first drafts.

### 4.4 Quick Replies
User is in a messaging app or email. Instead of typing a reply, they speak it. The polishing keeps it natural but removes verbal tics. Faster than typing for anything longer than a few words.

---

## 5. Core Dictation Flow (The Main Loop)

This is the critical flow. Everything else is secondary.

### 5.1 Activation Modes

**Two ways to activate, one Fn key:**

| Mode | Action | Behavior | Stop |
|---|---|---|---|
| **Hold mode** | Press and hold Fn | Dictates while Fn is held down | Release Fn |
| **Hands-free mode** | Double-tap Fn | Dictates continuously, hands-free | Press Fn once |

Both modes are always available. No configuration needed.

### 5.2 Flow Diagram

```
┌─────────────────────────────────────────────────────┐
│                    IDLE STATE                        │
│         Menu bar app, waiting for Fn key             │
└──────────┬──────────────────────┬───────────────────┘
           │ Fn held down         │ Fn double-tapped
           ▼                      ▼
┌─────────────────────┐  ┌─────────────────────┐
│    HOLD MODE        │  │   HANDS-FREE MODE   │
│                     │  │                      │
│  Listening while    │  │  Listening until     │
│  Fn is held         │  │  Fn pressed again    │
│                     │  │                      │
│  Stop: release Fn   │  │  Stop: press Fn      │
└─────────┬───────────┘  └──────────┬───────────┘
          │                         │
          └────────────┬────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                 ACTIVE DICTATION                     │
│  1. Overlay appears near cursor (listening indicator)│
│  2. Microphone capture starts                        │
│  3. Audio chunks streamed to backend via WebSocket   │
│  4. Backend streams to ElevenLabs STT                │
│  5. Transcription accumulated server-side            │
└──────────────────────┬──────────────────────────────┘
                       │ Stop signal (Fn release or press)
                       ▼
┌─────────────────────────────────────────────────────┐
│                FINALIZATION                           │
│  1. Final transcription from ElevenLabs              │
│  2. LLM polishing pass (GPT-4o-mini)                │
│  3. Polished text injected into active text field    │
│     - Primary: Accessibility API (AXUIElement)       │
│     - Fallback: Clipboard paste (Cmd+V)              │
│  4. Entry saved to dictation history                 │
│  5. Overlay dismissed                                │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│                 BACK TO IDLE                          │
└─────────────────────────────────────────────────────┘
```

### 5.3 Edge Cases
- **No text field focused**: Still transcribe, save to history, copy to clipboard
- **App loses focus during dictation**: Continue transcription, inject when done (or clipboard fallback)
- **Microphone unavailable**: Show error in overlay, prompt to check System Settings
- **Network failure mid-dictation**: Cache audio locally, retry when connection restored (or show error)
- **Very long dictation**: No hard limit, but consider chunking polishing requests to avoid LLM timeouts

---

## 6. UX Patterns

### 6.1 Menu Bar App
- Lives in macOS menu bar (no Dock icon)
- Click menu bar icon → dropdown with:
  - **Dictation history** (scrollable list, most recent first)
  - Settings
  - Quit
- Settings: microphone selection, other preferences

### 6.2 Dictation History (Menu Bar)
- Each entry shows: truncated text preview + timestamp
- **Click any entry → copies full text to clipboard** (pasteboard)
- Visual feedback on copy (checkmark or brief highlight)
- Stored locally, persists across restarts
- Scrollable, most recent first

### 6.3 Overlay
- Small floating indicator (~minimal size)
- Appears near the active text cursor
- Shows: listening indicator only (waveform or pulsing dot)
- No text preview — just a visual signal that Mumbli is recording
- Dismisses automatically after text injection
- Semi-transparent background, minimal chrome

### 6.4 Activation
- **Default hotkey**: `Fn` key
  - **Hold**: dictate while held, release to stop and inject
  - **Double-tap**: hands-free mode, dictate until Fn pressed again
- No silence timeout — user controls start/stop explicitly

### 6.5 First Launch
1. App opens → request Microphone permission
2. Request Accessibility permission (guide user to System Settings)
3. Ready to use (Fn key works immediately)

---

## Part 2: Development Documentation

### 7. Architecture Overview

```
┌──────────────┐        WSS/REST        ┌──────────────┐        HTTP         ┌──────────────┐
│              │ ──────────────────────> │              │ ─────────────────> │              │
│  macOS App   │                         │   FastAPI    │                     │  ElevenLabs  │
│  (Swift)     │ <────────────────────── │   Backend    │ <───────────────── │  STT API     │
│              │    polished text        │              │   transcriptions   │              │
└──────────────┘                         └──────┬───────┘                    └──────────────┘
                                                │
                                                │ HTTP
                                                ▼
                                         ┌──────────────┐
                                         │              │
                                         │  OpenAI API  │
                                         │  (polishing) │
                                         │              │
                                         └──────────────┘

                                         ┌──────────────┐
                                         │              │
                                         │  Supabase    │
                                         │  (Auth)      │
                                         │              │
                                         └──────────────┘
```

**Components**:
- **macOS App (Swift)**: System overlay, audio capture, text injection, local history, local preferences
- **FastAPI Backend (Python)**: Transcription orchestration, LLM polishing, auth
- **ElevenLabs**: Speech-to-text API (streaming)
- **OpenAI**: Light text polishing (GPT-4o-mini or similar)
- **Supabase**: Authentication (JWT-based)

---

### 8. macOS App Architecture

#### 8.1 Tech Stack
- **Language**: Swift
- **UI**: AppKit for system overlay + SwiftUI for settings/menu bar
- **Audio**: AVFoundation for microphone capture
- **Networking**: URLSession with async/await, URLSessionWebSocketTask for streaming
- **Storage**: Local file or SQLite for dictation history
- **Distribution**: Direct download (DMG)

#### 8.2 Core Components

| Component | Responsibility |
|---|---|
| **OverlayController** | Floating NSWindow near active text field; always-on-top, shows listening indicator (waveform/pulsing dot) only |
| **AudioCaptureManager** | Microphone access via AVFoundation, audio stream buffering, configurable audio format (PCM/Opus) |
| **TranscriptionClient** | WebSocket connection to backend, sends audio chunks, receives final polished text |
| **TextInjector** | Inserts text at cursor via Accessibility API (`AXUIElement`). Fallback: clipboard + simulated Cmd+V |
| **HotkeyManager** | Fn key monitoring: detects hold vs double-tap, manages activation/deactivation |
| **HistoryManager** | Stores dictation entries locally (text + timestamp), provides list for menu bar, handles copy-to-clipboard |
| **MenuBarController** | NSStatusItem setup, dropdown menu with history list, settings, quit |
| **AppDelegate** | Lifecycle, permission requests, component wiring |

#### 8.3 Fn Key Detection Logic

```
Fn key down:
  → Start a short timer (~300ms)
  → If Fn released before timer fires → it was a tap
      → If second tap within double-tap window (~500ms) → HANDS-FREE MODE
      → Else → ignore (single short tap does nothing)
  → If Fn still held when timer fires → HOLD MODE
      → Start dictation immediately
      → Stop when Fn released

HOLD MODE active:
  → Fn released → stop dictation → finalize

HANDS-FREE MODE active:
  → Fn pressed → stop dictation → finalize
```

#### 8.4 Activation & Dictation Flow

1. `HotkeyManager` detects Fn hold or double-tap
2. `AudioCaptureManager.startCapture()` begins mic recording
3. `OverlayController` detects cursor position via AX API, shows listening indicator
4. `TranscriptionClient` opens WebSocket to `/ws/transcribe`
5. Audio chunks streamed as binary WebSocket frames
6. On stop (Fn release or Fn press):
   - `AudioCaptureManager.stopCapture()`
   - Send stop signal to backend
   - Receive final polished text
   - `TextInjector` inserts text into focused field
   - `HistoryManager` saves entry (text + timestamp)
   - `OverlayController` dismisses overlay

#### 8.5 Text Injection Strategy
1. **Primary**: Use `AXUIElement` to find focused element, set `AXValue` or insert at `AXSelectedTextRange`
2. **Fallback**: Copy text to `NSPasteboard`, simulate `Cmd+V` keypress via `CGEvent`
3. Detection: try AX first, if element doesn't support `AXValue`, use clipboard fallback

#### 8.6 Permissions Required
- **Microphone**: `NSMicrophoneUsageDescription` in Info.plist
- **Accessibility**: User must grant in System Settings → Privacy & Security → Accessibility
- **Input Monitoring**: Required for Fn key detection via CGEvent tap

---

### 9. Backend Architecture

#### 9.1 Tech Stack
- **Framework**: FastAPI (Python 3.12+)
- **Auth**: Supabase Auth (JWT validation)
- **STT**: ElevenLabs Speech-to-Text API
- **LLM**: OpenAI API (GPT-4o-mini for text polishing)
- **Transport**: WebSocket for streaming, REST for utilities
- **Deployment**: TBD (containerized)

#### 9.2 Core Services

| Service | Responsibility |
|---|---|
| **AuthMiddleware** | Validates Supabase JWT on all requests |
| **TranscriptionService** | Receives audio stream from client, forwards to ElevenLabs, accumulates transcription |
| **PolishingService** | Takes final transcription, runs through GPT-4o-mini to clean up |
| **WebSocketManager** | Connection lifecycle, chunked audio handling, error recovery |

#### 9.3 Text Polishing Prompt (Simple)
```
You are a text polishing assistant. Clean up this dictated text:
- Remove filler words (um, uh, like, you know)
- Fix grammar and punctuation
- If the speaker corrected themselves (e.g., "at 4, actually 3"), keep only the correction
- Keep the speaker's voice and intent — do NOT rewrite heavily
- Output only the cleaned text, nothing else

Dictated text: {transcription}
```

#### 9.4 ElevenLabs STT Integration
- Streaming WebSocket or chunked HTTP to ElevenLabs
- Audio format: PCM 16-bit 16kHz mono (or Opus if supported)
- Language: auto-detect (no language hint needed)
- Accumulate transcription server-side during session
- Final accumulated result triggers polishing pipeline on stop

---

### 10. API Contract

#### 10.1 REST Endpoints

```
GET    /health                — Health check
POST   /auth/verify           — Verify Supabase JWT, return user info
```

#### 10.2 WebSocket Endpoint

```
WS     /ws/transcribe         — Streaming transcription + polishing

Client → Server:
  Binary frames: audio chunks (PCM 16-bit 16kHz mono)
  Text frames:
    { "type": "start" }                    — begin transcription session
    { "type": "stop" }                     — end session, trigger polishing

Server → Client:
  Text frames:
    { "type": "listening" }                — server ready, recording active
    { "type": "final", "text": "..." }     — polished final text
    { "type": "error", "message": "..." }  — error

Authentication:
  First text frame must be: { "type": "auth", "token": "<supabase_jwt>" }
```

---

### 11. Data Model (Supabase)

```sql
-- Auth handled by Supabase Auth (built-in users table)
-- Minimal settings table for user preferences

CREATE TABLE user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
```

Settings are minimal. Most preferences (mic selection) stored locally on the Mac.
Dictation history is local-only (not synced to backend).
