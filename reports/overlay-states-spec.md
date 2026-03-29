# Overlay States -- Design Spec

> Covers 4 overlay changes: hold mode sizing, hands-free differentiation, processing state, and corner transparency fix.
> Builds on existing `overlay-design-spec.md` and `dot-animation-spec.md`.

---

## 1. Hold Mode (Listening) -- Dot Sizing Update

The current code already uses 7pt dots with 8pt spacing. This is the correct target -- the original 5pt spec felt too small and hard to read at the bottom of screen.

| Property | Old Spec | Current Code | Final Target |
|----------|----------|--------------|--------------|
| Dot diameter | 5pt | 7pt | **7pt** (keep) |
| Dot spacing (HStack) | 6pt | 8pt | **8pt** (keep) |
| Container padding | 12pt | 14pt | **14pt** (keep -- proportional to larger dots) |
| Max scale (loud speech) | 1.6x | 1.6x | **1.6x** (keep) |

At 7pt base, loud speech (1.6x) produces ~11.2pt dots. With 8pt spacing between dot edges, center-to-center distance is 15pt. Dots stay clear of each other even at max scale.

**Dot color**: `Color.accentColor` (system accent, typically blue).
**Opacity**: 0.55 at silence, 0.6-1.0 during speech (unchanged).
**Border**: 1px stroke, `Color.primary.opacity(0.08)` -- subtle hairline, barely visible.

No changes needed to hold mode beyond confirming the 7pt size is correct.

---

## 2. Hands-Free Mode (Listening) -- Visual Differentiation

The user must immediately see that hands-free is active without reading text. The current implementation uses orange dots + pulsing orange border. This is the right direction but needs refinement.

### Chosen approach: Orange dots + steady (not pulsing) orange border + "REC" dot

**Why not pulsing border**: The pulsing border animation conflicts with the VU meter philosophy. The dots are the only thing that should animate. A pulsing border draws the eye away from the dots and creates visual noise.

| Property | Hold Mode | Hands-Free Mode |
|----------|-----------|-----------------|
| Dot color | `Color.accentColor` | `Color.orange` |
| Border color | `Color.primary.opacity(0.08)` | `Color.orange.opacity(0.35)` |
| Border width | 1px | 1.5px |
| Border animation | None | **None** (remove pulsing) |
| REC indicator | None | Small 4pt filled red circle, left of dots |

### REC dot detail

- A small solid red circle (`Color.red`), 4pt diameter, positioned to the left of the 3 VU dots with 6pt spacing from the first dot.
- Opacity: constant 0.8. No blinking. No animation. It is a status badge, not a flasher.
- This is the clearest signal that "recording mode is different." Orange dots alone could be mistaken for an accent color preference. The red dot is universally understood as "recording."

### Updated layout (hands-free only)

```
[ (red dot 4pt) --6pt-- (dot) --8pt-- (dot) --8pt-- (dot) ]
```

The pill width grows slightly to accommodate the extra indicator. Padding stays at 14pt.

### What to remove

- Remove `borderPulse` state variable and its `repeatForever` animation.
- Replace with a static orange border at 0.35 opacity.

---

## 3. Processing State -- "Thinking" Indicator

After the user releases Fn (hold mode) or triggers stop (hands-free), the app transcribes and polishes. This takes 1-3 seconds. The overlay must stay visible and show progress.

### Visual: Cycling dots (sequential fade)

The 3 dots cycle through a highlight sequence, left to right, repeating. This is a lightweight "thinking" animation that reuses the existing dot layout.

| Property | Value |
|----------|-------|
| Shape | Same pill, same size, same background blur |
| Dot color | `Color.secondary` (gray) for inactive dots |
| Highlight color | `Color.accentColor` at full opacity |
| Dot size | 7pt (same as listening state, scale 1.0, no VU reactivity) |
| Cycle speed | Each dot highlights for **0.4s**, total cycle = 1.2s |
| Animation | Opacity transition: inactive dot at 0.35 opacity, active dot at 1.0. Use `easeInOut` with 0.3s duration for the opacity change. |
| Border | Same as hold mode: 1px, `Color.primary.opacity(0.08)` |

### Animation sequence (repeating)

```
Frame 0.0s:  [*] [ ] [ ]    (* = highlighted, accentColor at 1.0)
Frame 0.4s:  [ ] [*] [ ]
Frame 0.8s:  [ ] [ ] [*]
Frame 1.2s:  [*] [ ] [ ]    (loop)
```

### Transition from listening to processing

1. VU dots freeze at current scale.
2. Over 0.2s, all dots simultaneously:
   - Scale back to 1.0 (spring, same params as VU).
   - Color transitions to `Color.secondary` at 0.35 opacity.
3. Cycling animation begins immediately after the transition completes.
4. If in hands-free mode, the red REC dot fades out over 0.2s during this transition.
5. Border reverts to hold-mode style (thin, neutral) regardless of which mode triggered processing.

### Transition from processing to dismiss

When transcription + polishing completes:
1. Cycling animation stops (dots freeze at current state).
2. Standard dismiss animation plays: fade to 0 + slide down 4px over 0.2s.

No "success" animation (checkmark, green flash, etc.). The text appearing in the target field is the success signal. The overlay just quietly exits.

---

## 4. Corner Transparency Fix

### The problem

The pill has visible opaque corners. The `VisualEffectBlur` (NSVisualEffectView) renders as a rectangle, and although `clipShape(RoundedRectangle(cornerRadius: 14))` is applied to the ZStack, the NSHostingView's own layer and the wrapper NSView can leak opaque pixels at the corners.

### The fix: Mask the NSVisualEffectView directly

The SwiftUI `.clipShape()` modifier handles the SwiftUI layer, but the underlying AppKit view needs its own corner mask. Two things must happen:

**A. In SwiftUI (already partly done):**
- Keep `.clipShape(RoundedRectangle(cornerRadius: 14))` on the background ZStack. This is correct.

**B. In OverlayController (AppKit side):**
- On the `wrapper` NSView, apply a `CALayer` mask with 14pt corner radius:
  ```
  wrapper.layer?.cornerRadius = 14
  wrapper.layer?.masksToBounds = true
  ```
- On the `hostingView` layer, same treatment:
  ```
  hostingView.layer?.cornerRadius = 14
  hostingView.layer?.masksToBounds = true
  ```

**C. Ensure the VisualEffectBlur NSViewRepresentable also clips:**
- In `makeNSView`, add:
  ```
  view.layer?.cornerRadius = 14
  view.layer?.masksToBounds = true
  ```
- Or, apply `.cornerRadius(14)` within the `VisualEffectBlur` SwiftUI usage. But the AppKit layer-level clip is more reliable.

### Visual target

The pill should have perfectly smooth 14pt rounded corners with no visible rectangular artifacts. The blur should bleed to the rounded edge and stop cleanly. Test against both light and dark backgrounds, and against a colorful desktop wallpaper where corner artifacts are most visible.

### Do NOT change to a solid background

The blur effect (`.hudWindow` material) is correct and matches macOS system UI conventions (Spotlight, Siri, etc.). Do not replace it with a solid color fill. The fix is purely about masking/clipping, not about changing the background approach.

---

## Summary for Implementation

| State | Key Visual | Color | Animation |
|-------|-----------|-------|-----------|
| Hold listening | 3 VU dots | `accentColor` | VU meter reactivity |
| Hands-free listening | 3 VU dots + red REC dot | `orange` dots, `orange` border | VU meter reactivity, NO pulsing border |
| Processing | 3 cycling dots | `secondary` (gray) / `accentColor` highlight | Sequential 0.4s highlight cycle |
| Dismiss | Freeze + fade | -- | 0.2s fade + 4px slide down |
| Corner fix | Proper layer masking | -- | -- |
