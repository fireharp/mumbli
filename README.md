# Mumbli

A macOS menu bar app for voice-to-text dictation. Hold or double-tap the **Fn key** to dictate into any text field. Audio is transcribed via [ElevenLabs STT](https://elevenlabs.io/), [Groq Whisper](https://groq.com/), or [Deepgram](https://deepgram.com/) and optionally polished with [OpenAI](https://openai.com/) or [Groq LLM](https://groq.com/).

## Install

Download the latest DMG and drag Mumbli into Applications:

**[Download Mumbli.dmg](https://github.com/fireharp/mumbli/releases/latest/download/Mumbli.dmg)** — signed with a Developer ID certificate and notarized by Apple.

Or use the install script, which downloads the same DMG and copies the app across for you:

```bash
curl -fsSL https://raw.githubusercontent.com/fireharp/mumbli/main/install.sh | bash
```

Requires **macOS 13.0+** (Ventura or later). API keys can be configured in the app's Settings after first launch.

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

   Enter your API keys in the app's Settings after first launch (ElevenLabs, OpenAI, Groq, Deepgram — depending on which engines you use). The app never reads a `.env` file.

   A `.env` file is only used by the Python benchmark harness in `benchmarks/` — see `benchmarks/.env.example` for the keys it expects.

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
```

Build products land in Xcode's DerivedData directory (there is no local `./build` folder), so the easiest way to run the app is **Product > Run** in Xcode.

### Run UI tests

```bash
xcodebuild test -project MumbliApp.xcodeproj -scheme MumbliApp -destination 'platform=macOS'
```

(`MumbliApp` is the only shared scheme; it includes the `MumbliAppUITests` target.)

## Permissions

On first launch, macOS will prompt for:

| Permission | Why |
|---|---|
| **Microphone** | Audio capture for dictation |
| **Accessibility** | Injecting transcribed text at the cursor, and detecting Fn key presses |

Grant both for full functionality. Fn detection uses NSEvent monitors plus a CGEvent tap, which run under the Accessibility permission — these two are the only permissions the app requests.

## How It Works

1. Press and hold **Fn** (or double-tap for hands-free mode) to start recording — Settings > Shortcuts shows both gestures
2. Speak — audio is captured via `AVAudioEngine` (PCM 16-bit, 16 kHz mono)
3. Release Fn — audio is sent to STT API (ElevenLabs, Groq Whisper, or Deepgram)
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
| **Fast** | Groq Whisper large-v3-turbo | Groq gpt-oss-20b | ~0.5-1s |
| **Deepgram** | Deepgram Nova-3 | OpenAI GPT-5.4 Nano | ~2-4s |

## Project Structure

```
MumbliApp/
├── MumbliApp.swift              # App entry point
├── AppDelegate.swift            # Lifecycle & component wiring
├── Assets.xcassets              # App icon (cream waveform)
├── Core/
│   ├── HotkeyManager.swift      # Fn key detection (NSEvent monitors + CGEvent tap)
│   ├── AudioCaptureManager.swift # Microphone capture
│   ├── TextInjector.swift        # Cursor text injection (Accessibility)
│   ├── FileLogger.swift          # Debug logging
│   ├── PipelineTimer.swift       # Pipeline latency measurement
│   ├── AppVersion.swift          # Real version & commit for Settings > About
│   └── RecordingManager.swift    # Save dictation WAVs for benchmarking
├── Protocols/
│   └── DictationServiceProtocol.swift # STT / polishing service protocols
├── Services/
│   ├── ElevenLabsSTTService.swift    # ElevenLabs STT (standard engine)
│   ├── GroqWhisperSTTService.swift   # Groq Whisper STT (fast engine)
│   ├── DeepgramSTTService.swift      # Deepgram STT (Deepgram engine)
│   ├── OpenAIPolishingService.swift  # OpenAI polishing + engine/preset enums
│   ├── GroqPolishingService.swift    # Groq LLM polishing (fast engine)
│   ├── VocabularyStore.swift         # Custom vocabulary persistence & formatting
│   ├── RepetitionGuard.swift        # Post-polish safety guard
│   └── KeychainManager.swift         # Credential storage
├── ProofOfUse/                  # Opt-in, local-only signed usage receipts
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

Polishing LLMs (especially small, fast models) can hallucinate, repeat phrases in a loop, or leak system prompt tags when the dictated speech sounds conversational. Mumbli has three layers of defense:

1. **XML boundary** — Raw transcription is wrapped in `<dictation>` tags before polishing, creating a clear separation between system instructions and user content.
2. **Injection-hardened prompts** — The polishing prompt explicitly forbids the LLM from adding, inventing, or continuing content beyond what was spoken.
3. **RepetitionGuard** — A deterministic post-polish check with five guards:
   - **Tag leakage** — system prompt tags (`<dictation>`, `<terms>`) appearing in output
   - **Invention** — more than 40% of output words never appeared in the raw transcription
   - **Length explosion** — output is >2x the input character count
   - **Truncation** — output retains fewer than 60% of the input's words
   - **Hallucinated URLs** — links the speaker never dictated are stripped

   An earlier sentence-count rule was deliberately removed: recalibrated against 4,657 real dictation pairs, it flagged 7.1% of dictations while catching none of the genuine failures the other guards caught.

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
4. CI builds the app, signs it with a Developer ID certificate, notarizes and staples the DMG, computes `checksums.txt` after stapling, attests build provenance, and uploads two byte-identical DMGs: `Mumbli-X.Y.Z.dmg` and the stable-named `Mumbli.dmg`

### Manual install

1. Go to [Releases](https://github.com/fireharp/mumbli/releases) — or grab the stable URL directly: [`Mumbli.dmg`](https://github.com/fireharp/mumbli/releases/latest/download/Mumbli.dmg)
2. Download `Mumbli-x.y.z.dmg` (or the byte-identical `Mumbli.dmg`)
3. Mount it, drag **Mumbli** onto the **Applications** alias in the DMG window
4. Launch from Applications

To verify a download, `checksums.txt` on the release lists the SHA-256 of both DMGs, and `gh attestation verify Mumbli.dmg --repo fireharp/mumbli` checks the build provenance.

Releases are signed with a Developer ID certificate and notarized by Apple, so
macOS opens them without a Gatekeeper prompt. The `xattr -cr` workaround older
instructions mention is no longer needed.

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
- The project can be regenerated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen). Caveat: XcodeGen 2.45 ignores `options.objectVersion` and always writes `objectVersion = 77`, which needs Xcode 16+ to open — the checked-in project is `objectVersion = 56`. The release scripts regenerate only when you pass `REGENERATE=1`

## License

Licensed under the [Apache License, Version 2.0](LICENSE).

Attribution is appreciated. If you build on Mumbli or use substantial parts of it, please keep the license/NOTICE files and consider linking back to the original repository.
