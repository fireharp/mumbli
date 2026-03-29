# Mumbli Listening Overlay -- Design Spec

> Reference apps: macOS Siri indicator, Raycast command palette, Spotlight search bar, ChatGPT desktop overlay

---

## 1. Size

| Property | Current | Proposed |
|----------|---------|----------|
| Width | 80px (hard-coded frame) | **52px** (intrinsic, dots + horizontal padding) |
| Height | 48px (hard-coded frame) | **52px** (intrinsic, with vertical padding) |

With the "Listening" text label removed, the overlay is now a compact square-ish pill containing only the 3 animated dots. The indicator block is ~27pt wide; 12px padding on each side gives ~51px intrinsic width, rounded to 52px. The 52x52 capsule reads as a small floating dot indicator -- minimal, unobtrusive, and comparable to a macOS status-bar icon in footprint.

---

## 2. Position

**Center-bottom of the active screen**, inset 40px from the bottom edge (above the Dock).

- Horizontally centered on the screen that owns the frontmost window.
- Bottom-center was explicitly chosen by the user over center-top. The fixed position lets the user build muscle-memory for where to look, and bottom placement keeps the overlay near the user's hands/keyboard rather than requiring an upward eye shift.

---

## 3. Background

Use a **single `NSVisualEffectView` with `.hudWindow` material and `.behindWindow` blending** (same material as today, which is correct). Remove the extra inner gradient and glow-ring layers -- they add visual noise at this size without contributing clarity.

| Layer | Purpose |
|-------|---------|
| `NSVisualEffectView` (.hudWindow) | Native vibrancy blur that adapts to light/dark automatically |
| 1px inner stroke | `Color.primary.opacity(0.08)` -- subtle edge definition against busy backgrounds |

No additional gradient fills. The HUD material already provides depth through the system blur.

---

## 4. Listening Indicator (Mic-Reactive)

Replace the 5-bar waveform with **3 evenly-spaced dots** that **react to real-time microphone input levels**. Each dot is **5pt base diameter**, spaced **6pt** apart, giving an indicator block of roughly 27x5pt at rest.

The indicator should feel alive -- like it is actually hearing the user's voice. Think Siri's orb pulsing with speech, or ChatGPT voice mode's ring expanding when you talk.

### Audio Input Pipeline

The overlay needs a normalized audio level value (0.0 to 1.0) updated at ~15-20 Hz (every 50-65ms). This should come from the same `AVCaptureDevice` audio session used for dictation:
- Read the average power level from the audio input meter.
- Convert dB to a 0.0-1.0 linear scale (clamp below a noise floor threshold of ~-50dB to avoid reacting to ambient noise).
- Apply light smoothing (exponential moving average, alpha ~0.3) so the dots don't jitter on every sample but still feel responsive.

### Dot Behavior by Audio State

**Silence / ambient noise (level < 0.05):**
- Dots hold at base size (5pt diameter) with a slow, gentle "breathing" pulse -- scale oscillates between `1.0` and `1.15` over 2s, `easeInOut`. This signals "I'm listening, waiting for you to speak."
- Opacity: `0.5` base, pulsing to `0.65`.
- All 3 dots breathe in unison (no stagger during silence).

**Active speech (level >= 0.05):**
- Dots scale proportionally to the audio level. Map `audioLevel` (0.05 to 1.0) to a scale range of `1.0` to `1.8`.
- Each dot reacts with a slight stagger: dot 0 responds immediately, dot 1 delayed by ~30ms, dot 2 by ~60ms. This creates a left-to-right ripple effect that suggests sound traveling, making it feel organic rather than mechanical.
- Opacity rises from `0.6` to `1.0` proportionally with level.
- Use `spring(response: 0.15, dampingFraction: 0.7)` for the scale animation so dots snap up quickly on speech onset but ease back down naturally -- this is the "alive" feeling.

**Loud speech / emphasis (level > 0.7):**
- Same as active speech, but the dots also shift color slightly toward a brighter tint: `Color.accentColor` blends toward `.white` by `(level - 0.7) * 0.3`. This gives a subtle "glow" on emphasis without being flashy.

### Dot Colors

Single accent color: **`Color.accentColor`** (system purple by default on macOS) so the overlay respects the user's accent-color preference. The color brightens with audio level as described above.

### Layout

The dots are **centered** within the pill, both horizontally and vertically. With no text label, the dots are the sole content.

---

## 5. Typography

**Removed.** The "Listening" text label has been removed per user decision. The overlay communicates its state entirely through the animated dots. No text is rendered.

---

## 6. Animation

### Appear
1. Overlay starts at `alphaValue = 0` and `y` offset **+8px** below final position (so it slides up from beneath the screen edge).
2. Animate to `alphaValue = 1` and final `y` over **0.3s** with `easeOut` timing.
3. Dots begin in the **silence/breathing** state immediately (do not wait for audio input to start animating -- the breathing pulse signals "ready" from the first frame).

### While Listening (mic-reactive -- see Section 4 for full detail)
- The dots react to real-time audio levels at ~15-20 Hz.
- **Silence**: Slow unison breathing pulse (scale 1.0-1.15, 2s cycle).
- **Speech**: Dots scale up proportionally to volume with a left-to-right ripple stagger. Spring animation (`response: 0.15, dampingFraction: 0.7`) for snappy onset and natural decay.
- **Loud speech**: Dots brighten toward white in addition to scaling.
- Transitions between silence and speech should feel seamless -- the spring animation handles this naturally. No abrupt state switches or crossfades.

### Disappear
1. Fade to `alphaValue = 0` over **0.2s** with `easeIn`.
2. Slight downward drift of **+4px** during fade (slides back down below the screen edge).
3. Dots freeze at their current state during the fade-out (do not snap to rest size -- let the fade mask them).

### Animation Principles
- Entrance/exit: crisp `easeOut`/`easeIn` -- no spring physics for the window itself.
- Dot indicator: spring physics for speech reactivity (this is where the "alive" feeling comes from).
- Never animate faster than the display refresh rate. Target 60fps; the 15-20 Hz audio sampling is the data rate, not the animation rate -- SwiftUI interpolates between samples.

---

## 7. Shadow and Border

| Effect | Value |
|--------|-------|
| Outer shadow | `color: .black.opacity(0.12), radius: 12, y: 4` -- single soft shadow for depth |
| Inner stroke | `1px, Color.primary.opacity(0.08)` -- hairline edge for definition on light backgrounds |

Remove the triple-shadow stack and the purple glow shadow from the current implementation. One clean shadow is enough; multiple overlapping shadows create a muddy halo at small sizes.

---

## 8. Dark Mode vs Light Mode

The design relies entirely on **system-adaptive tokens**, so no manual branching is needed:

| Token | Light | Dark |
|-------|-------|------|
| `.hudWindow` material | Light frosted glass | Dark frosted glass |
| `.primary.opacity(0.85)` | Near-black text | Near-white text |
| `Color.accentColor` | User's chosen accent | Same, auto-adjusted |
| `.black.opacity(0.12)` shadow | Subtle on light bg | Subtle on dark bg |
| `.primary.opacity(0.08)` stroke | Barely visible edge | Barely visible edge |

No additional overrides. The overlay should look native in both modes without any `@Environment(\.colorScheme)` branching.

---

## Summary of Key Changes

1. **Smaller and dots-only**: 52x52 intrinsic pill (was 80x48 fixed frame). "Listening" text removed -- dots are the sole indicator.
2. **Fixed position**: Center-bottom of screen (40px from bottom edge) instead of cursor-tracking.
3. **Simpler background**: Single HUD blur + hairline stroke. Remove gradient fills and glow ring.
4. **Dots not bars**: 3 pulsing dots replace 5 waveform bars for clarity at small size.
5. **Single accent color**: `Color.accentColor` instead of 5 separate hues.
6. **No text**: Label removed. The overlay communicates state through dot animation alone.
7. **Cleaner animation**: Slide-up entrance, slide-down exit. One shadow instead of three.
8. **Fully system-adaptive**: No manual dark/light branching needed.
