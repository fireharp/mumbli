# Interfaze vs Groq STT Benchmark

Generated: 2026-05-11T23:47:44

## Summary

- Files: 50
- Total audio: 2021.0s
- Audio range: 0.3s to 293.8s
- Judge requested: `audio`
- Judge modes observed: `{'audio': 37, 'text_reference_fallback': 13}`
- Raw JSON: `/Users/fireharp/Prog/mumbli/mac-app/benchmarks/results/interfaze_groq_2026-05-11_234744.json`

Saved `.txt` files are included as historical app transcripts only. The current app preference is `fast`, which maps to Groq Whisper, so those files should not be treated as unbiased ground truth.

## Latency

| Provider | Model | Success | Median ms | p95 ms | Min ms | Max ms |
| --- | --- | --- | --- | --- | --- | --- |
| Interfaze STT | interfaze-beta | 50/50 | 8383 | 13584 | 5724 | 16308 |
| Groq Whisper | whisper-large-v3-turbo | 50/50 | 534 | 1098 | 209 | 1785 |

## Judge Wins

| Outcome | Count |
| --- | --- |
| Interfaze wins | 14 |
| Groq wins | 15 |
| Ties | 21 |
| Skipped/failed | 0 |

## Largest Judged Divergences

| File | Audio s | Winner | Interfaze | Groq | Material change |
| --- | --- | --- | --- | --- | --- |
| 2026-05-11_134521.wav | 3.4 | Interfaze STT | 10.0 | 1.0 | none |
| 2026-05-11_134500.wav | 18.3 | Interfaze STT | 8.0 | 2.0 | none |
| 2026-05-11_144253.wav | 21.1 | Groq Whisper | 6.0 | 10.0 | Material proper-noun/role phrase differs from reference ('SVPS Steel' vs 'SPS deal'). |
| 2026-05-11_134316.wav | 65.9 | Interfaze STT | 9.0 | 7.0 | none |
| 2026-05-11_134847.wav | 87.7 | Groq Whisper | 7.0 | 9.0 | minor changes in phrasing and missing 'aside from that' altered meaning slightly |
| 2026-05-11_135111.wav | 49.2 | Groq Whisper | 7.0 | 9.0 | minor (genetic -> changing) |
| 2026-05-11_135140.wav | 23.2 | Interfaze STT | 9.0 | 7.0 | none |
| 2026-05-11_135253.wav | 44.3 | Groq Whisper | 8.0 | 10.0 | minor change in 'faced agents' which could alter meaning slightly |
| 2026-05-11_135322.wav | 25.5 | Groq Whisper | 8.0 | 10.0 | minor changes: 'waste' instead of 'based' and 'hubs' instead of 'code' |
| 2026-05-11_135743.wav | 59.1 | Groq Whisper | 8.0 | 10.0 | minor |
