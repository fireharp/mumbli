# Overlay States v2 -- Quick Spec (aligned with waveform bars)

> Updates `overlay-states-spec.md` to match the new 5-bar waveform from `vu-prominent-spec.md`.

---

## 1. Hold Mode (Fn held)

- **Bars**: 5 waveform bars per `vu-prominent-spec.md`
- **Color**: `Color.accentColor` (blue by default)
- **Bar sizing**: 7pt dot spec is superseded -- bars are 3pt wide, 6-24pt tall
- **Border**: 1px, `Color.primary.opacity(0.08)` -- subtle hairline
- **Glow**: accent-color glow when audioLevel > 0.3

No changes needed beyond implementing the new bar layout.

---

## 2. Hands-Free Mode (double-tap Fn)

- **Bars**: same 5 waveform bars, but colored `Color.orange`
- **Border**: 1.5px, `Color.orange.opacity(0.35)` -- steady, NO pulsing
- **REC dot**: 4pt solid red circle, left of the bars, 6pt gap. Opacity 0.8, no animation.
- **Glow**: `Color.orange.opacity(audioLevel * 0.25)` instead of accent color

The orange + red-dot combo is the differentiator. Remove all `borderPulse` animation code.

---

## 3. Processing State (transcribing)

- **Bars shrink** to resting height (6-8pt), then cycle opacity left-to-right
- **Color**: `Color.secondary` (gray) base, `Color.accentColor` highlight
- **Cycle**: each bar highlights for 0.3s, total cycle = 1.5s (5 bars x 0.3s)
- **Transition in**: bars spring to rest height over 0.2s, color fades to gray, then cycling starts
- **Transition out**: freeze + standard dismiss (fade 0 + slide down 4px, 0.2s)
- **REC dot**: fades out during transition if coming from hands-free
- **Border**: reverts to hold-mode style

No spinner needed -- the sequential bar highlight IS the spinner, and it reuses existing layout.

---

## 4. Corner Masking

Unchanged from original spec. Apply `cornerRadius: 14` + `masksToBounds: true` on:
- `wrapper` NSView layer
- `hostingView` layer
- `VisualEffectBlur` NSView in `makeNSView`

All three layers must clip. Test against colorful wallpaper in both light/dark mode.
