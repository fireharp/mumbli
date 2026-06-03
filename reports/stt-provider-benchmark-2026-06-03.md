# STT Provider Benchmark

Generated: 2026-06-03T18:02:22

## Summary

- Files: 50
- Total audio: 896.4s
- Audio range: 0.9s to 90.7s
- Judge requested: `audio`
- Judge modes observed: `{'audio': 45, 'skipped': 3, 'text_reference_fallback': 2}`
- Raw JSON: `/Users/fireharp/Prog/mumbli/mac-app/benchmarks/results/stt_providers_2026-06-03_180222.json`

Saved `.txt` files are included as historical app transcripts only. They should not be treated as unbiased ground truth.

## Latency

| Provider | Model | Success | Median ms | p95 ms | Min ms | Max ms |
| --- | --- | --- | --- | --- | --- | --- |
| Interfaze STT | interfaze-beta | 50/50 | 22371 | 36445 | 15376 | 61043 |
| Interfaze Run Task | interfaze-beta <task>speech_to_text</task> no schema | 50/50 | 22206 | 54628 | 15867 | 71862 |
| Groq Whisper | whisper-large-v3-turbo | 50/50 | 1048 | 3037 | 323 | 4135 |
| ElevenLabs Scribe | scribe_v1 | 50/50 | 2538 | 8570 | 718 | 10268 |
| Deepgram Nova-3 | nova-3 | 50/50 | 1928 | 6831 | 888 | 13357 |

## Judge Wins

| Outcome | Count |
| --- | --- |
| Interfaze STT wins | 3 |
| Interfaze Run Task wins | 2 |
| Groq Whisper wins | 3 |
| ElevenLabs Scribe wins | 16 |
| Deepgram Nova-3 wins | 4 |
| Ties | 19 |
| Skipped/failed | 3 |

## Largest Judged Divergences

| File | Audio s | Winner | Interfaze | Interfaze Run Task | Groq | ElevenLabs | Deepgram Nova-3 | Material change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-06-03_172246.wav | 4.8 | Deepgram Nova-3 | 9.0 | 9.0 | 9.0 | 2.0 | 10.0 | significant |
| 2026-06-03_164934.wav | 22.2 | Groq Whisper | 9.0 | 10.0 | 10.0 | 6.0 | 5.0 | minor: missing 'an' before 'observation'; significant change: 'LMS' instead of 'LLM'; significant... |
| 2026-06-03_173338.wav | 7.8 | Deepgram Nova-3 | 5.0 | 5.0 | 5.0 | 8.0 | 10.0 | significant meaning change due to 'the value' instead of 'DeValley' and missing 'Can we'; signifi... |
| 2026-06-03_170557.wav | 17.3 | Interfaze Run Task | 9.0 | 10.0 | 10.0 | 8.0 | 6.0 | none |
| 2026-06-03_172627.wav | 19.4 | Interfaze Run Task | 10.0 | 10.0 | 10.0 | 6.0 | 7.0 | minor; minor |
| 2026-06-03_164442.wav | 18.6 | ElevenLabs Scribe | 8.0 | 9.0 | 9.0 | 10.0 | 7.0 | minor omissions of filler and 'it's'; minor omissions of filler and 'it's', 'hashed'; minor omiss... |
| 2026-06-03_164519.wav | 2.4 | ElevenLabs Scribe | 7.0 | 7.0 | 7.0 | 10.0 | 7.0 | background audio missing; background audio missing; background audio missing; background audio mi... |
| 2026-06-03_164601.wav | 33.9 | ElevenLabs Scribe | 7.0 | 7.0 | 7.0 | 10.0 | 9.0 | minor repetition and phrasing differences; minor repetition and phrasing differences; minor repet... |
| 2026-06-03_164627.wav | 21.1 | ElevenLabs Scribe | 8.0 | 9.0 | 9.0 | 10.0 | 7.0 | minor meaning change due to missing 'you can,' and 'the'; minor meaning change due to missing 'yo... |
| 2026-06-03_164818.wav | 17.7 | ElevenLabs Scribe | 9.0 | 9.0 | 8.0 | 10.0 | 7.0 | minor preposition difference; missing 'we' changes meaning slightly |
