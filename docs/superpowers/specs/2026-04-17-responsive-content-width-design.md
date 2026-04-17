# Responsive Content Width — Design

**Date:** 2026-04-17
**Status:** Approved, implemented on `feature/responsive-content-width`
**Parent spec:** `2026-04-06-lightmd-design.md`

## Context

Until v1.5.13 the rendered Markdown body sat at a fixed `max-width: 720px`
centered in the viewport. Widening the window showed more whitespace, not
more text — users who wanted more text per line had no option but to shrink
the font size, which hurts readability. The user asked for a responsive
behavior that also preserves the iA-Writer-inspired typographic discipline
of the app.

## Goals

- Window resize should visibly change the number of characters per line.
- Keep a typographic ceiling (Bringhurst / Butterick: 45–75 chars ideal,
  degradation past ~85). Unrestricted fluidity would break the reading
  experience on ultrawide monitors.
- Give power-users an escape hatch for tables and wide code blocks.
- Add no new Swift observation layer — reuse the existing CSS hot-swap path.

## Design

### CSS strategy

Replace the fixed `--content-width: 720px` with a `min()` expression that
grows with the viewport but caps at a typographic ceiling:

```css
:root { --content-width: min(75ch, 92vw); }   /* default (Wide) */
#content {
    max-width: var(--content-width);
    margin: 0 auto;
    padding: 48px clamp(16px, 4vw, 48px);
}
```

- `ch` (font-0 glyph width) couples the measure to the reading typeface —
  changing font-family or size naturally re-sizes the column.
- `92vw` keeps a thin gutter on narrow windows so text never hits the edge.
- `clamp(16px, 4vw, 48px)` lets the horizontal padding breathe slightly
  with the window without getting absurd at the extremes.

### Presets

A new `contentWidth` user preference with four options:

| Preset        | `--content-width`     | Measure (at 16px body)    |
| ------------- | --------------------- | ------------------------- |
| Comfortable   | `min(65ch, 92vw)`     | iA-Writer-ish, classic   |
| **Wide**      | `min(75ch, 92vw)`     | new default              |
| Extra Wide    | `min(90ch, 92vw)`     | tables / code-heavy      |
| Unlimited     | `92vw`                 | Notion-style escape hatch |

Wide is the default because it matches the user's directional preference
("I want more text on wider windows") while staying at the upper end of
Butterick's recommended 45–90ch band.

### Update (2026-04-17, follow-up): fix / dynamic axis

After shipping the four-preset set, the user pointed out that the fluid
`Unlimited` behavior — where the margins themselves grow as a proportion
of the window — was the part that made widening the window feel right.
The `fix` presets hit their ch ceiling and then stop changing; the fluid
preset kept responding. They asked for a second fluid preset with a
slightly wider margin, and for a naming scheme that makes the two modes
visible in the picker itself.

Final preset matrix:

| Preset                    | `--content-width`   | Mode    | Note                              |
| ------------------------- | ------------------- | ------- | --------------------------------- |
| Comfortable (fix, 65ch)   | `min(65ch, 92vw)`   | fix     | iA-Writer-ish                     |
| Wide (fix, 75ch)          | `min(75ch, 92vw)`   | fix     | default                           |
| Extra Wide (fix, 90ch)    | `min(90ch, 92vw)`   | fix     | tables / code-heavy in fixed mode |
| Wide (dynamic, 85vw)      | `85vw`              | dynamic | fluid, ~7.5% margin each side    |
| Extra Wide (dynamic, 95vw)| `95vw`              | dynamic | fluid, ~2.5% margin — was `unlimited`, widened slightly to emphasize the mode difference |

The `unlimited` raw value from v1.5.16 preferences.json is remapped to
`.extraWideDynamic` in `UserPreferences.init(from:)`. Next save
overwrites the legacy string with the new case name.

### Plumbing

- `UserPreferences` gets a `contentWidth: ContentWidthPreset` field.
- `UserPreferences.init(from:)` is now custom and tolerant — older
  preferences.json files without `contentWidth` decode cleanly and fall
  back to `.wide` instead of resetting every other field.
- `ThemeManager.fontOverrideCSS` emits `--content-width` alongside
  `--font-body` and `--font-size`. This reuses the existing
  `<style id="font-override">` hot-swap path: width changes apply
  instantly without a full WKWebView reload, and scroll position is
  preserved.
- `PreferencesView` gets a "Layout / Content Width" section with a Picker.
- `ContentView` gets an `onChange(of: preferences.contentWidth)`
  that calls `refreshCSSOnly()`.
- `WKWebView` re-evaluates `92vw` and `min()` natively on window resize,
  so there is no new Swift-side resize observer.

## What was deliberately left out (YAGNI)

- View menu / keyboard shortcut for cycling presets — font-size already
  owns `Cmd±`, and a Preferences toggle is sufficient for a 4-state setting.
- Per-file width override — global setting is enough.
- A freeform numeric slider — the four presets span the useful range
  without giving the user a way to pick a typographically bad value.
- A Swift-side resize observer — pure CSS covers the responsive case.

## Verification

Manual test (covered in implementation plan file):

1. Build and launch; confirm default Wide preset looks like ~75ch and
   matches the Wide column of the table above.
2. Resize the window from ~600px to ~1600px; confirm the measure grows
   smoothly until `75ch`, then the column stays fixed and margins grow.
3. Switch presets in Preferences; confirm instant update with scroll
   position preserved.
4. Cycle through all three built-in themes — behavior should be identical.
5. Quit and relaunch; confirm chosen preset persists.
6. Export to PDF; page layout should be unchanged (print CSS overrides
   `max-width: 100% !important` and is untouched by this change).
