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

2. **Set up git hooks** (enforces conventional commit messages)

   ```bash
   git config core.hooksPath .githooks
   ```

3. **Configure API keys**

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

### Custom Vocabulary

Add words that are often mistranscribed (proper nouns, technical terms) in **Settings > Custom Vocabulary**. These words improve accuracy at two levels:

1. **STT level** — vocabulary is sent as a prompt hint to Groq Whisper, biasing transcription toward correct spellings (e.g. "wheat press" → "vitepress")
2. **Polishing level** — vocabulary is injected into the LLM system prompt, so the polisher corrects any remaining errors (e.g. "11 labs" → "ElevenLabs")

Benchmarked at **36% → 100%** exact spelling accuracy across 11 real vocabulary instances.

> **Note:** ElevenLabs Scribe v1 does not support vocabulary hints at the STT level — corrections happen during polishing only.

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
│   ├── VocabularyStore.swift         # Custom vocabulary persistence & formatting
│   ├── RepetitionGuard.swift        # Post-polish safety guard
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

## Safety Guards

Polishing LLMs (especially smaller models like Groq Llama 3.1 8B) can hallucinate, repeat phrases in a loop, or leak system prompt tags when the dictated speech sounds conversational. Mumbli has three layers of defense:

1. **XML boundary** — Raw transcription is wrapped in `<dictation>` tags before polishing, creating a clear separation between system instructions and user content.
2. **Injection-hardened prompts** — The polishing prompt explicitly forbids the LLM from adding, inventing, or continuing content beyond what was spoken.
3. **RepetitionGuard** — A deterministic post-polish check that catches:
   - **Sentence explosion** — output has more sentences than input
   - **Length explosion** — output is >2x the input character count
   - **Tag leakage** — system prompt tags (`<dictation>`, `<terms>`) appearing in output

   If the guard trips on the Groq (Fast) engine, it automatically retries with GPT-5.4 Nano. If that also fails, it falls back to the raw transcription.

## Benchmarking

A Python benchmark harness lives in `benchmarks/`:

```bash
cd benchmarks
cp .env.example .env   # add your API keys
uv run bench.py        # latency benchmark across providers
uv run quality.py      # transcription quality comparison (LLM-as-judge)
uv run vocab_bench.py  # vocabulary prompt accuracy benchmark
uv run polish_bench.py # polishing prompt injection & hallucination benchmark
```

Results and reports are saved in `benchmarks/results/` and `reports/`.

## Releases & Versioning

Mumbli uses **semantic versioning** (`0.MINOR.PATCH`) with fully automated releases:

- **`fix:` commits** → patch bump (0.1.0 → 0.1.1)
- **`feat:` commits** (or anything else) → minor bump (0.1.0 → 0.2.0)

### How it works

1. Push to `main` (directly or via PR merge)
2. [release-please](https://github.com/googleapis/release-please) analyzes commits and opens a **Release PR** with a generated changelog
3. Merge the Release PR → version is bumped, git tag created, GitHub Release published
4. A DMG is automatically built and attached to the release

### Install from DMG

1. Go to [Releases](https://github.com/fireharp/mumbli/releases)
2. Download the latest `Mumbli-x.y.z.dmg`
3. Mount it (double-click)
4. Drag **Mumbli** to **Applications**
5. Launch from Applications

### Contributing

Use [conventional commit](https://www.conventionalcommits.org/) prefixes in commit messages or PR titles:

| Prefix | Effect |
|--------|--------|
| `feat:` | New feature → minor version bump |
| `fix:` | Bug fix → patch version bump |
| `docs:` | Documentation (no release) |
| `chore:` | Maintenance (no release) |

## Notes

- The app runs as a **menu bar only** app (no Dock icon)
- No code signing is required for local development builds
- The project can be regenerated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen)
