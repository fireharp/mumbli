# Interfaze vs Groq vs ElevenLabs STT Benchmark

Generated: 2026-05-14T23:17:49

## Summary

- Files: 50
- Total audio: 2021.0s
- Audio range: 0.3s to 293.8s
- Judge requested: `none`
- Judge modes observed: `{'none': 50}`
- Raw JSON: `/Users/fireharp/Prog/mumbli/mac-app/benchmarks/results/interfaze_groq_elevenlabs_2026-05-14_231749.json`

Saved `.txt` files are included as historical app transcripts only. The current app preference is `fast`, which maps to Groq Whisper, so those files should not be treated as unbiased ground truth.

## Latency

| Provider | Model | Success | Median ms | p95 ms | Min ms | Max ms |
| --- | --- | --- | --- | --- | --- | --- |
| Interfaze STT | interfaze-beta | 50/50 | 8383 | 13584 | 5724 | 16308 |
| Interfaze Run Task | interfaze-beta <task>speech_to_text</task> no schema | 50/50 | 12004 | 21257 | 8798 | 22006 |
| Groq Whisper | whisper-large-v3-turbo | 50/50 | 534 | 1098 | 209 | 1785 |
| ElevenLabs Scribe | scribe_v1 | 50/50 | 2386 | 7472 | 299 | 24616 |

## Judge Wins

| Outcome | Count |
| --- | --- |
| Interfaze STT wins | 0 |
| Interfaze Run Task wins | 0 |
| Groq Whisper wins | 0 |
| ElevenLabs Scribe wins | 0 |
| Ties | 0 |
| Skipped/failed | 0 |

## Largest Judged Divergences

| File | Audio s | Winner | Interfaze | Interfaze Run Task | Groq | ElevenLabs | Material change |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-05-11_134134.wav | 48.7 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134207.wav | 26.6 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134316.wav | 65.9 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134347.wav | 22.0 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134441.wav | 28.2 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134500.wav | 18.3 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134514.wav | 13.6 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134516.wav | 1.3 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134521.wav | 3.4 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
| 2026-05-11_134553.wav | 23.8 |  | 0.0 | 0.0 | 0.0 | 0.0 | none |
