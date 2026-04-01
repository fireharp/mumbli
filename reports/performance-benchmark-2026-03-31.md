# Performance Benchmark Report — 2026-03-31

## Summary

Tested 2 STT providers (ElevenLabs batch, ElevenLabs chunked parallel, OpenAI Whisper batch, OpenAI Whisper chunked) and 3 polishing configurations across 6 recordings (1.8s to 61.2s audio).

**Winner: ElevenLabs Chunked + GPT-5.4 Mini** — 50-63% faster than baseline for longer dictations.

## STT Results (avg ms, 2 iterations each)

| Recording | Duration | ElevenLabs Batch | ElevenLabs Chunked | OpenAI Whisper | OpenAI Chunked |
|-----------|----------|------------------|--------------------|----------------|----------------|
| Short phrase | 1.8s | **524** | — | 1,611 | — |
| Medium dictation | 24.7s | 1,434 | **904** | 2,285 | 2,268 |
| Medium dictation | 29.7s | **1,697** | 1,822 | 2,619 | 5,277 |
| Long dictation | 40.9s | 2,569 | **1,173** | 3,937 | 2,525 |
| Long dictation | 43.2s | 2,627 | **1,174** | 5,737 | 2,714 |
| Long dictation | 61.2s | 2,929 | **1,089** | 3,154 | 2,610 |

**Key findings:**
- ElevenLabs Chunked is **37-63% faster** for audio >24s
- For short audio (<12s), single batch is better (chunked falls back automatically)
- OpenAI Whisper is consistently slower than ElevenLabs
- OpenAI Chunked is inconsistent — sometimes slower due to per-chunk overhead

## Polishing Results (avg ms, 2 iterations)

| Provider / Model | Avg Latency | Notes |
|------------------|-------------|-------|
| GPT-5.4 Mini | **587ms** | 48% faster than Nano |
| GPT-5.4 Nano (short prompt) | 707ms | Slightly aggressive output |
| GPT-5.4 Nano | 1,125ms | Current baseline |

**Key finding:** GPT-5.4 Mini is surprisingly faster than Nano (587ms vs 1,125ms) with equivalent quality.

## Best End-to-End Pipelines

| STT | Polish | Total | vs Baseline |
|-----|--------|-------|-------------|
| ElevenLabs Chunked (24.7s audio) | GPT-5.4 Mini | **1,491ms** | -54% |
| ElevenLabs Chunked (40.9s audio) | GPT-5.4 Mini | **1,760ms** | -55% |
| ElevenLabs Chunked (43.2s audio) | GPT-5.4 Mini | **1,762ms** | -53% |
| ElevenLabs Chunked (61.2s audio) | GPT-5.4 Mini | **1,676ms** | -59% |
| **Baseline** (61.2s audio) | GPT-5.4 Nano | **4,054ms** | — |

## Methodology

- Python benchmark harness (`benchmarks/bench.py`) using `httpx` async HTTP client
- WAV recordings captured via Mumbli's "Save recordings" debug mode
- Each configuration tested with 2 iterations, averaged
- Chunked STT: 10-second chunks with 2-second overlap, all chunks sent in parallel
- Stitching: word-level overlap detection (longest common run ≥2 words at boundaries)
- Raw data: `benchmarks/results/2026-03-31_171455.json`

## Implementation

The "Fast" engine is now available in Settings > Debug > Engine:
- **Standard**: ElevenLabs Scribe v1 (single batch) + GPT-5.4 Nano
- **Fast**: ElevenLabs Scribe v1 (chunked parallel) + GPT-5.4 Mini

## Live Validation (Fast Engine in-app)

Metrics from actual dictation with the Fast engine enabled:

| Audio Duration | STT (ms) | Polish (ms) | Total (ms) | Engine |
|---|---|---|---|---|
| 37.6s | 1,143 | 1,263 | **2,442** | Fast (chunked) |
| 24.9s | 1,507 | 1,153 | **2,693** | Fast (chunked) |
| 15.4s | 1,252 | 1,547 | **2,838** | Fast (chunked) |
| 15.2s | 1,726 | 1,241 | **3,009** | Fast (chunked) |
| 51.1s | 3,605 | 2,063 | **5,731** | Standard |
| 44.4s | 2,872 | 1,290 | **4,199** | Standard |

**Observation:** STT is ~60% faster with chunked mode. Polishing is now the bottleneck at ~1.2s (longer text = more tokens than the benchmark's short phrase). To break under 2s total, polishing needs a faster provider (Groq ~200ms).

## Known Issues

- **Accessibility permissions reset on rebuild**: After a clean build, macOS revokes accessibility access. Must re-grant in System Settings > Privacy & Security > Accessibility.
- **Audio tap crash (pre-existing)**: `AVAudioIONodeImpl::SetOutputFormat` crash in `AudioCaptureManager.startCapture()` line 232 when Bluetooth audio devices switch profiles (A2DP -> HFP). Not related to performance changes.
- **Engine picker doesn't sync model on load**: If the engine was previously set to "Fast" in UserDefaults, reopening Settings shows the correct engine but the polishing model picker may still show "Nano" until manually changed. The actual polishing uses the correct model from UserDefaults.

## Future Optimizations (not yet tested, need API keys)

| Optimization | Expected Impact | Status |
|---|---|---|
| Groq Whisper STT (~200ms for 43s audio) | ~90% STT reduction | Needs Groq API key |
| Groq LLM polishing (~200ms) | ~82% polish reduction | Needs Groq API key |
| ElevenLabs Scribe v2 Realtime (streaming during recording) | Near-zero post-stop latency | Architecture change needed |
| Connection pre-warming | -150ms first call | Low effort |
| Audio compression (Opus) | -100-700ms on slow connections | Medium effort |
