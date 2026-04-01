# Mumbli

A macOS menu bar app for voice-to-text dictation. Hold or double-tap the **Fn key** to dictate into any text field. Audio is transcribed via [ElevenLabs STT](https://elevenlabs.io/) or [Groq Whisper](https://groq.com/) and optionally polished with [OpenAI](https://openai.com/) or [Groq LLM](https://groq.com/).

## Requirements

- **macOS 13.0+** (Ventura or later)
- **Xcode 15.0+** (includes Swift 5.9)
- No external package dependencies — built entirely on Apple system frameworks

## Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/fireharp/mumbli.git
   cd mumbli
   ```

2. **Configure API keys**

   Create a `.env` file in the project root (this file is gitignored):

   ```
   ELEVENLABS_API_KEY=your_elevenlabs_key
   OPENAI_API_KEY=your_openai_key
   GROQ_API_KEY=your_groq_key          # optional, for Fast engine
   ```

   Alternatively, you can enter API keys in the app's Settings view after first launch.

## Build & Run

### Using Xcode (recommended)

```bash
open MumbliApp.xcodeproj
```

Then **Product > Build** (`Cmd+B`) and **Product > Run** (`Cmd+R`).

### Using the command line

```bash
# Debug build
xcodebuild -project MumbliApp.xcodeproj -scheme MumbliApp -configuration Debug build

# Release build
xcodebuild -project MumbliApp.xcodeproj -scheme MumbliApp -configuration Release build

# Run the app
open build/Debug/Mumbli.app
```

### Run UI tests

```bash
xcodebuild test -project MumbliApp.xcodeproj -scheme MumbliAppUITests -destination 'platform=macOS'
```

## Permissions

On first launch, macOS will prompt for:

| Permission | Why |
|---|---|
| **Microphone** | Audio capture for dictation |
| **Accessibility** | Injecting transcribed text at the cursor |
| **Input Monitoring** | Detecting Fn key presses |

Grant all three for full functionality.

## How It Works

1. Press and hold **Fn** (or double-tap, configurable in Settings) to start recording
2. Speak — audio is captured via `AVAudioEngine` (PCM 16-bit, 16 kHz mono)
3. Release Fn — audio is sent to STT API (ElevenLabs or Groq Whisper)
4. Transcribed text is optionally polished by LLM (OpenAI or Groq), then injected at the cursor
5. Dictation history is accessible from the menu bar icon

### Engine Modes

Switch between engines in **Settings > Debug > Engine**:

| Engine | STT | Polish | Typical Latency |
|--------|-----|--------|-----------------|
| **Standard** | ElevenLabs Scribe v1 | OpenAI GPT-5.4 Nano | ~3-5s |
| **Fast** | Groq Whisper large-v3-turbo | Groq Llama 3.1 8B | ~0.5-1s |

## Project Structure

```
MumbliApp/
├── MumbliApp.swift              # App entry point
├── AppDelegate.swift            # Lifecycle & component wiring
├── Core/
│   ├── HotkeyManager.swift      # Fn key detection (Carbon)
│   ├── AudioCaptureManager.swift # Microphone capture
│   ├── TextInjector.swift        # Cursor text injection (Accessibility)
│   ├── FileLogger.swift          # Debug logging
│   ├── PipelineTimer.swift       # Pipeline latency measurement
│   └── RecordingManager.swift    # Save dictation WAVs for benchmarking
├── Services/
│   ├── ElevenLabsSTTService.swift    # ElevenLabs STT (standard engine)
│   ├── GroqWhisperSTTService.swift   # Groq Whisper STT (fast engine)
│   ├── OpenAIPolishingService.swift  # OpenAI polishing + engine/preset enums
│   ├── GroqPolishingService.swift    # Groq LLM polishing (fast engine)
│   └── KeychainManager.swift         # Credential storage
├── Models/
│   └── HistoryManager.swift     # Dictation history persistence
└── UI/
    ├── MenuBarController.swift  # Status bar & popover
    ├── HistoryView.swift        # History list
    ├── SettingsView.swift       # Preferences
    ├── FirstLaunchView.swift    # Onboarding
    └── OverlayController.swift  # Listening indicator
```

## Benchmarking

A Python benchmark harness lives in `benchmarks/`:

```bash
cd benchmarks
cp .env.example .env   # add your API keys
uv run bench.py        # latency benchmark across providers
uv run quality.py      # transcription quality comparison (LLM-as-judge)
```

Results and reports are saved in `benchmarks/results/` and `reports/`.

## Notes

- The app runs as a **menu bar only** app (no Dock icon)
- No code signing is required for local development builds
- The project can be regenerated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen)
