# Interfaze vs Groq vs ElevenLabs STT Benchmark

Generated: 2026-05-12T15:09:44

## Summary

- Files: 50
- Total audio: 2021.0s
- Audio range: 0.3s to 293.8s
- Judge requested: `audio`
- Judge modes observed: `{'audio': 48, 'skipped': 1, 'text_reference_fallback': 1}`
- Raw JSON: `/Users/fireharp/Prog/mumbli/mac-app/benchmarks/results/raw.json`

Saved `.txt` files are included as historical app transcripts only. The current app preference is `fast`, which maps to Groq Whisper, so those files should not be treated as unbiased ground truth.

## Latency

| Provider | Model | Success | Median ms | p95 ms | Min ms | Max ms |
| --- | --- | --- | --- | --- | --- | --- |
| Interfaze STT | interfaze-beta | 50/50 | 8383 | 13584 | 5724 | 16308 |
| Groq Whisper | whisper-large-v3-turbo | 50/50 | 534 | 1098 | 209 | 1785 |
| ElevenLabs Scribe | scribe_v1 | 50/50 | 2386 | 7472 | 260 | 24616 |

## Judge Wins

| Outcome | Count |
| --- | --- |
| Interfaze STT wins | 6 |
| Groq Whisper wins | 2 |
| ElevenLabs Scribe wins | 25 |
| Ties | 16 |
| Skipped/failed | 1 |

## Largest Judged Divergences

| File | Audio s | Winner | Interfaze | Groq | ElevenLabs | Material change |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-05-11_134521.wav | 3.4 | Interfaze STT | 10.0 | 0.0 | 0.0 | complete mismatch; complete mismatch |
| 2026-05-11_134516.wav | 1.3 | Interfaze STT | 10.0 | 9.0 | 2.0 | significant |
| 2026-05-11_134316.wav | 65.9 | Interfaze STT | 9.0 | 7.0 | 6.0 | minor; moderate |
| 2026-05-11_134648.wav | 46.2 | Groq Whisper | 9.0 | 10.0 | 7.0 | some |
| 2026-05-11_134948.wav | 51.9 | ElevenLabs Scribe | 7.0 | 8.0 | 10.0 | some changes in meaning due to missing disfluencies, changed words like 'prior' vs 'triage', and ... |
| 2026-05-11_135111.wav | 49.2 | ElevenLabs Scribe | 7.0 | 7.0 | 10.0 | minor; minor |
| 2026-05-11_135140.wav | 23.2 | ElevenLabs Scribe | 7.0 | 6.0 | 9.0 | low; medium |
| 2026-05-11_144155.wav | 6.8 | Interfaze STT | 10.0 | 9.0 | 7.0 | minor |
| 2026-05-11_150758.wav | 39.9 | ElevenLabs Scribe | 7.0 | 8.0 | 10.0 | minor; minor |
| 2026-05-11_161450.wav | 16.7 | ElevenLabs Scribe | 6.0 | 6.0 | 9.0 | Yes: 'if it's just 4' is altered to 'if it's just for this', changing the comparison number.; Yes... |
