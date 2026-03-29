# Mumbli Settings View -- Design Spec

> Reference apps: macOS System Settings, Raycast settings, Arc Browser settings

---

## Problems with Current Design

- **Grey-on-grey**: Section card fill is `Color.primary.opacity(0.03)` with a `0.06` opacity border -- both are nearly invisible, making cards blend into the window background.
- **No visual hierarchy**: All three sections (Audio Input, Shortcuts, About) look identical. Nothing draws the eye to the primary action (microphone selection).
- **Faint section headers**: Icons and labels use `tertiaryLabelColor` -- the lowest-contrast system label. They disappear.
- **Key caps look disabled**: The Fn key badges use `0.06` fill and `0.1` border, which reads as a disabled/greyed-out control rather than a physical key.
- **Waveform icon is decorative noise**: 16pt at 0.3-0.4 opacity gradient -- too faint to register, too small to convey brand identity. Either make it meaningful or remove it.
- **Window too short**: 320px height clips the About section when content is long. No scroll support.
- **Title is oversized relative to content**: 20pt bold "Settings" dominates a window that only has three small sections.

---

## 1. Window Size

| Property | Current | Proposed |
|----------|---------|----------|
| Width | 420px | **460px** |
| Height | 320px | **400px** (minimum, grow-to-fit with max 520px) |

Use `.frame(minWidth: 460, minHeight: 400, maxHeight: 520)` so the window can accommodate future sections without clipping. Wrap the content area in a `ScrollView` with `.scrollIndicators(.hidden)` as a safety net.

---

## 2. Header

**Remove the waveform icon entirely.** It adds clutter without function. Replace with a cleaner header layout:

| Element | Spec |
|---------|------|
| Title | "Settings" -- `.system(size: 16, weight: .semibold, design: .rounded)`, `.primary` color |
| Subtitle | Remove "Configure your Mumbli experience" -- it's filler text that says nothing useful |
| Top padding | 24px from window top edge |
| Bottom padding | 16px below title, then a `Divider()` with `.opacity(0.15)` |

The title should feel like a toolbar label (macOS System Settings uses ~15pt semibold for its sidebar titles). 16pt semibold is enough to establish context without dominating.

---

## 3. Section Cards

The current cards are invisible. Fix with proper contrast and differentiation:

### Card background
- **Light mode**: `Color(nsColor: .controlBackgroundColor)` -- this is the standard white/near-white card surface that macOS uses for grouped list rows.
- **Dark mode**: Same token auto-adapts to the correct dark card surface.

### Card border
- `Color.primary.opacity(0.08)`, 1px -- subtle but actually visible. Current `0.06` at `0.5px` is subpixel and invisible on non-Retina.

### Card shadow
- `color: .black.opacity(0.04), radius: 2, y: 1` -- the faintest possible depth cue. Enough to lift the card off the background without looking like a floating tile.

### Card padding
- Inner: **16px** all sides (up from 14px -- standard macOS inset).
- Corner radius: **10px** (keep current).

### Card spacing
- **16px** between cards (down from 20px -- tighter grouping reads as a unified form).

---

## 4. Section Headers

Section headers need to be visible but subordinate to card content.

| Property | Current | Proposed |
|----------|---------|----------|
| Icon size | 11pt | **12pt** |
| Icon color | `tertiaryLabelColor` | `secondaryLabelColor` |
| Label size | 11pt uppercased + tracking | **12pt smallCaps**, `.semibold`, `.secondary` color |
| Spacing below | 10px | **8px** |

Switch from `.uppercased()` + letter spacing to `.font(.system(size: 12, weight: .semibold).smallCaps())`. Small caps are more readable than all-caps with tracking at small sizes.

---

## 5. Audio Input Picker

The native `Picker` is fine -- it matches macOS conventions. Improve its context:

- Add a subtle **microphone status indicator** to the left of the picker: a 6px circle that is green (`Color(nsColor: .systemGreen)`) when a device is selected, or yellow with the warning icon (as-is) when no devices are found.
- Give the picker `frame(maxWidth: .infinity)` so it stretches to fill the card width rather than hugging its label.
- The "No audio input devices found" warning is good. Keep it but bump the icon to 11pt and text to 12pt for consistency.

---

## 6. Shortcuts -- Keyboard Key Caps

This is the biggest visual problem. The current key caps look like disabled form fields. They need to look like **physical keyboard keys**.

### Key cap spec

| Property | Value |
|----------|-------|
| Font | `.system(size: 11, weight: .semibold, design: .rounded)` (up from 10pt) |
| Horizontal padding | 10px (up from 7px) |
| Vertical padding | 5px (up from 4px) |
| Corner radius | 6px (up from 5px) |
| Background fill | Light mode: `Color(nsColor: .controlColor)` -- standard macOS control surface |
| Top highlight | 1px inset at top edge: `Color.white.opacity(0.6)` -- simulates light hitting the top of a physical key |
| Border | `Color.primary.opacity(0.15)`, 1px -- firm edge definition |
| Bottom shadow | `color: .black.opacity(0.12), radius: 0, x: 0, y: 1` -- the "key sits above the keyboard" effect |
| Outer shadow | `color: .black.opacity(0.06), radius: 1, x: 0, y: 1` -- soft ambient depth |

The combination of a lighter face, a top highlight, a firm border, and a bottom drop-shadow creates the classic "keyboard key" look used by macOS itself in the Keyboard Shortcuts preference pane.

### Shortcut row label
- Bump from 12pt to **13pt** `.regular` for better readability.
- Keep `.primary` color (no change needed).

### Double-tap indicator
- For "Fn Fn" (hands-free mode), add a small "x2" badge or a subtle separator dot between the two Fn caps to make it clearer this means "double-tap" rather than "press two keys simultaneously."

---

## 7. About Section

- Version label: bump to **13pt** to match shortcut row labels.
- Version badge: keep the monospaced semibold style but increase padding to `horizontal: 10, vertical: 4` and use `Color(nsColor: .controlBackgroundColor)` fill with `Color.primary.opacity(0.1)` border -- same visual language as key caps but flatter.
- Add a row below version: **"Made with [heart] in [location]"** or a link to the project site (optional, low priority).

---

## 8. Overall Spacing and Layout

```
Window (460 x 400-520)
+-- 24px top padding
|   "Settings" (16pt semibold)
+-- 16px
+-- Divider (0.15 opacity)
+-- 16px
|   [Audio Input card]
+-- 16px
|   [Shortcuts card]
+-- 16px
|   [About card]
+-- 24px bottom padding (flexible spacer)
```

Horizontal padding: **28px** each side (keep current -- it works well at 460px width).

---

## 9. Dark Mode

All proposed tokens are system-adaptive:

| Token | Light | Dark |
|-------|-------|------|
| `controlBackgroundColor` (card fill) | White | Dark grey (#2A2A2A) |
| `controlColor` (key cap fill) | Light grey (#F0F0F0) | Medium grey (#3A3A3A) |
| `secondaryLabelColor` (section headers) | Medium grey | Light grey |
| `.primary` | Near-black | Near-white |
| Shadows | Visible on light bg | Nearly invisible on dark bg (correct behavior) |

No `@Environment(\.colorScheme)` branching should be needed.

---

## Summary of Key Changes

1. **Taller window**: 460x400 minimum, scrollable, no content clipping.
2. **Quieter header**: 16pt semibold title, no subtitle, no decorative icon, divider below.
3. **Visible cards**: Real background color (`controlBackgroundColor`), 1px border at `0.08`, hairline shadow.
4. **Readable section headers**: 12pt small caps in `secondaryLabelColor` instead of tertiary.
5. **Realistic key caps**: Proper keyboard-key styling with highlight, border, and drop shadow.
6. **Consistent typography**: 13pt for all row labels, 12pt for section headers, 16pt for window title.
7. **Better spacing**: 16px card gaps, 16px inner padding, 24px window margins.
8. **Fully system-adaptive**: No manual dark/light mode handling.
