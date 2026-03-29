# VU Prominence Upgrade Spec

**Approach: 5 waveform bars** (like Siri/Shazam) replacing the 3 dots.

Bars are inherently taller, more dynamic, and read as "audio" at a glance. Dots are ambiguous -- bars are unmistakably a microphone/listening indicator.

## Spec

- **Bar count**: 5
- **Bar width**: 3pt each, corner radius fully rounded (capsule)
- **Bar gap**: 3pt between bars
- **Resting height**: 6pt (silence), center bar 8pt
- **Max height**: 24pt (loud speech), staggered per bar
- **Height mapping**: `restHeight + (audioLevel * (maxHeight - restHeight))`, with per-bar multipliers [0.6, 0.8, 1.0, 0.8, 0.6] so center bar leads
- **Color**: `Color.accentColor`, opacity 0.7 at rest, 1.0 at full level
- **Animation**: Same spring as dot-animation-spec (response: 0.10s, dampingFraction: 0.75)
- **Stagger**: 15ms delay per bar from center outward (center reacts first, edges last)
- **Pill size**: widen to ~36pt wide x 40pt tall (was 52x52 square). Padding 10pt horizontal, 8pt vertical.
- **Glow**: When audioLevel > 0.3, add a soft `Color.accentColor.opacity(audioLevel * 0.25)` shadow with radius 8pt behind the bars. Makes the indicator pop on dark backgrounds without being garish.

All other overlay properties (position, background material, appear/disappear animation) unchanged.

---

## Processing State (after Fn release, waiting for transcription + polishing)

- Bars spring down to resting height (6-8pt) over 0.2s, color fades to `Color.secondary` (gray) at 0.35 opacity.
- Sequential highlight: each bar lights up to `Color.accentColor` at 1.0 opacity for 0.3s, sweeping left-to-right, 1.5s per cycle, repeating.
- No spinner, no text. The bar sweep IS the loading indicator -- same layout, zero added complexity.
- On completion: freeze bars, standard dismiss (fade out + 4px slide down, 0.2s). No success animation.
- If entering from hands-free mode: REC dot and orange border fade out during the 0.2s transition.
