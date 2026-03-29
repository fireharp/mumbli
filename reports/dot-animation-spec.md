# Dot Animation Spec -- Mumbli Listening Overlay

> Replaces the dot behavior defined in sections 4 and 6 of `overlay-design-spec.md`.
> Reference animations: Apple Siri voice orb, Spotify "listening" waveform, Discord voice activity indicator.

---

## Design Philosophy

The dots are a **VU meter**, not a screensaver. They exist to show the user that their voice is being heard and how loud it is. Every visual change must be directly caused by audio input. If the mic is silent, the dots are nearly still. If the user speaks, the dots jump. There is no idle animation that could be mistaken for activity.

---

## 1. Audio Level Input

The animation consumes a single normalized float (`audioLevel`: 0.0 to 1.0) updated at 15-20 Hz from the audio capture pipeline. No changes to the existing `AudioLevelProvider` contract.

| Parameter | Value |
|-----------|-------|
| Update rate | 15-20 Hz (~50-65ms) |
| Noise floor | -50 dB (anything below maps to 0.0) |
| Smoothing | Exponential moving average, alpha = 0.3 |
| Range | 0.0 (silence) to 1.0 (loud speech) |

---

## 2. Silence State (audioLevel < 0.02)

The dots must appear **nearly still**. The user should not perceive any animation during silence. This is the critical difference from the old spec.

| Property | Value |
|----------|-------|
| Scale | 1.0 baseline, with random micro-jitter up to **1.02** max |
| Opacity | 0.55 constant (no pulsing) |
| Animation | None. No breathing. No easeInOut cycle. Flat. |
| Color | `Color.accentColor` at base brightness |

The micro-jitter is NOT a repeating animation. It is a tiny random perturbation applied per audio-level update tick to avoid the dots looking frozen/dead. The human eye cannot perceive a 2% scale change but it prevents the "static image" uncanny feeling.

Implementation: on each audio tick during silence, set scale to `1.0 + Float.random(in: 0...0.02)`. The spring animation (see section 4) handles interpolation.

---

## 3. Active Speech State (audioLevel >= 0.02)

Dots scale proportionally to audio energy. The mapping is linear and direct.

| Property | Formula |
|----------|---------|
| Scale | `1.0 + (audioLevel * 0.6)` -- range: 1.0 (whisper) to 1.6 (loud) |
| Opacity | `0.6 + (audioLevel * 0.4)` -- range: 0.6 to 1.0 |
| Color | `Color.accentColor` -- **no brightness shift, no white blend** |

### Why max scale is 1.6, not 1.8

The old spec used 1.8x which caused dots to visually merge at loud volumes given the 6pt spacing. At 1.6x, a 5pt dot reaches 8pt diameter -- still well within the 6pt gap between dot centers (11pt center-to-center). Loud speech looks energetic without the dots colliding.

### No brightness/white shift

The old spec blended toward white at high levels. This is removed. Color stays solid `Color.accentColor` at all levels. Reasons:
- Brightness shifts read as a UI state change (selected, highlighted), not as volume.
- The scale change alone communicates energy clearly.
- Solid color is more polished.

---

## 4. Animation Curve -- Spring

All dot scale and opacity changes use a single spring animation. No switching between easeInOut and spring depending on state.

```
Spring Parameters:
  response:         0.10s    (fast attack -- dots snap to new level)
  dampingFraction:  0.75     (slightly underdamped -- tiny overshoot then settle)
  blendDuration:    0.0      (no blend delay)
```

### Why these values

| Parameter | Old | New | Reason |
|-----------|-----|-----|--------|
| response | 0.15s | **0.10s** | 0.15 felt sluggish on speech onset. 0.10 snaps to level within one audio tick. |
| dampingFraction | 0.7 | **0.75** | 0.7 had visible bounce. 0.75 has a hair of overshoot then settles -- feels physical without being bouncy. |
| Silence animation | 2.0s easeInOut loop | **None** | The old breathing pulse was the core complaint. Removed entirely. |

The spring is used for **all transitions**: silence-to-speech, speech-to-silence, and level-to-level changes. This means there is no jarring switch between animation systems. When the user stops talking, the dots spring back to 1.0 scale with a natural decay -- fast down, gentle settle.

---

## 5. Dot Stagger (Ripple Effect)

Each dot receives the audio level with a time offset to create a left-to-right ripple.

| Dot | Index | Delay from dot 0 |
|-----|-------|-------------------|
| Left | 0 | 0 ms |
| Center | 1 | 20 ms |
| Right | 2 | 40 ms |

### Implementation

Do NOT use `DispatchQueue.asyncAfter` for stagger. Instead, maintain a short circular buffer (3 entries) of recent audio levels. Each dot reads from a different position in the buffer:
- Dot 0: current level
- Dot 1: level from 1 tick ago (~50-65ms, close enough to 20ms perceptual target at 20Hz update rate)
- Dot 2: level from 2 ticks ago

This is cheaper than scheduling timers and naturally stays in sync with the audio update rate. At 20Hz, the actual stagger is ~50ms per dot rather than exactly 20ms, but the perceptual effect is the same: a ripple, not a unison jump.

Alternative (if higher fidelity needed): buffer at a higher rate internally and interpolate. But start with the simple approach.

### Stagger in silence

During silence, all dots use the same micro-jitter value (no stagger). Stagger during silence would look like a wave animation, which contradicts the "nearly still" requirement.

---

## 6. Transition: Silence to Speech

When `audioLevel` crosses from below 0.02 to above 0.02:

1. No special transition logic. The spring animation handles it.
2. Dot 0 jumps first (no delay), dots 1 and 2 follow via the stagger buffer.
3. Opacity rises from 0.55 to 0.6+ as part of the same spring.

The result: dots pop to life with a quick left-to-right ripple. No fade-in, no ramp-up, no easing into speech mode. Instant response.

---

## 7. Transition: Speech to Silence

When `audioLevel` drops below 0.02:

1. Spring decays dots back to scale 1.0 over ~150-200ms (natural spring settling time at response=0.10, damping=0.75).
2. Opacity settles back to 0.55.
3. Ripple plays in reverse naturally (dot 0 settles first since it got the silent level first, dots 1-2 follow from the stagger buffer).

No hold timer. No "stay active for 200ms after last speech." The dots follow the audio level directly. If the audio pipeline itself has smoothing (alpha=0.3 EMA), that provides enough sustain.

---

## 8. Layout (unchanged)

| Property | Value |
|----------|-------|
| Dot diameter | 5pt (base, at scale 1.0) |
| Dot spacing | 6pt (gap between edges at rest) |
| Dot count | 3 |
| Container padding | 12pt all sides |
| Indicator block width | ~27pt at rest |

---

## 9. What This Spec Removes

| Old Behavior | Status | Reason |
|-------------|--------|--------|
| 2-second breathing pulse in silence | **Removed** | Looked like a screensaver. Gave false sense of activity. Core complaint. |
| Brightness/white shift at high levels | **Removed** | Gimmicky. Reads as UI state change, not volume. |
| Opacity pulsing in silence (0.5 to 0.65) | **Removed** | Contributed to the "lava lamp" feel. Constant 0.55 in silence. |
| Scale 1.0-1.15 breathing in silence | **Removed** | Replaced with imperceptible 2% random jitter. |
| easeInOut animation in silence state | **Removed** | Single spring animation for all states. No animation system switching. |
| 1.8x max scale | **Reduced to 1.6x** | Dots were visually merging at loud volumes. |

---

## 10. Acceptance Criteria

1. **Silence test**: Launch overlay with no mic input. Watch for 30 seconds. Dots should appear static to the naked eye. No visible pulsing, breathing, or oscillation.
2. **Whisper test**: Speak quietly. Dots should bump to ~1.1-1.2x scale. Clearly different from silence.
3. **Normal speech test**: Dots track syllables. Scale visibly jumps on stressed syllables, drops between words. Left-to-right ripple visible.
4. **Loud speech test**: Dots reach ~1.5-1.6x scale. No color change. No merging.
5. **Stop talking test**: Dots return to rest within ~200ms. No lingering animation.
6. **Color test**: Dots remain solid `Color.accentColor` at all volume levels. No white blending.
7. **VU meter feel**: A person watching the dots should be able to roughly tell when the speaker is talking vs. silent, and loud vs. quiet, without hearing the audio. Like watching a muted VU meter.
