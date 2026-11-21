---
name: "Backup Merge"
description: "Calm, warm, offline-first mobile design system for merging JW Library backups and exporting personal study notes."
---

## Overview

Backup Merge is an offline-first mobile companion for JW Library users who study across multiple devices. The interface feels calm, warm, tactile, and non-technical — like a quiet study desk rather than a developer utility. Generous whitespace, soft warm neutrals, rounded cards (16px–24px), and a single deep forest green accent (`#376754`) create a trustworthy, unhurried experience. Both light and dark themes are supported with warm-tinted neutrals (never stark white or pure `#000000`).

## Colors

The palette anchors on a single deep green (`#376754`) paired with warm stone neutrals (`#F9FAF6` surface in light mode, `#111412` in dark mode). Status hues (`success`, `warning`, `error`) are reserved strictly for process feedback, conflict notices, and destructive actions.

```yaml
colors:
  brand-green: "#376754"
  success: "#2E6F4E"
  on-success: "#FFFFFF"
  success-container: "#D3EFE0"
  on-success-container: "#0E3B25"
  warning: "#8C5A1B"
  on-warning: "#FFFFFF"
  warning-container: "#F7E5CC"
  on-warning-container: "#472A06"
  light:
    primary: "#376754"
    on-primary: "#FFFFFF"
    primary-container: "#D3E7DC"
    on-primary-container: "#112E22"
    secondary: "#506259"
    on-secondary: "#FFFFFF"
    secondary-container: "#E1F6EA"
    on-secondary-container: "#1E332A"
    tertiary: "#693837"
    on-tertiary: "#FFFFFF"
    tertiary-container: "#FFEDEB"
    on-tertiary-container: "#350F0F"
    error: "#BA1A1A"
    on-error: "#FFFFFF"
    error-container: "#FFDAD6"
    on-error-container: "#410002"
    background: "#F7F7F3"
    on-background: "#191C1B"
    surface: "#F7F7F3"
    surface-dim: "#E2E3DE"
    surface-bright: "#FCFDF9"
    surface-container-lowest: "#FFFFFF"
    surface-container-low: "#F1F2ED"
    surface-container: "#EBECE7"
    surface-container-high: "#E4E6E0"
    surface-container-highest: "#DDDFD9"
    on-surface: "#191C1B"
    surface-variant: "#DCE5DE"
    on-surface-variant: "#454D48"
    outline: "#717974"
    outline-variant: "#C8D0CA"
    inverse-surface: "#2E312F"
    inverse-on-surface: "#F0F1EE"
    inverse-primary: "#9FD1BA"
  dark:
    primary: "#9FD1BA"
    on-primary: "#003828"
    primary-container: "#1E4F3D"
    on-primary-container: "#C8FCE3"
    secondary: "#B7CBC0"
    on-secondary: "#22342C"
    secondary-container: "#384B42"
    on-secondary-container: "#E1F6EA"
    tertiary: "#FBB5B2"
    on-tertiary: "#4F2322"
    tertiary-container: "#6A3937"
    on-tertiary-container: "#FFEDEB"
    error: "#FFB4AB"
    on-error: "#690005"
    error-container: "#93000A"
    on-error-container: "#FFDAD6"
    background: "#121513"
    on-background: "#E4E6E2"
    surface: "#121513"
    surface-dim: "#0E110F"
    surface-bright: "#343835"
    surface-container-lowest: "#0C0F0D"
    surface-container-low: "#191D1A"
    surface-container: "#1F2421"
    surface-container-high: "#292E2B"
    surface-container-highest: "#333835"
    on-surface: "#E4E6E2"
    surface-variant: "#3B443F"
    on-surface-variant: "#BFC8C2"
    outline: "#8A938D"
    outline-variant: "#3D4640"
    inverse-surface: "#E4E6E2"
    inverse-on-surface: "#2E312F"
    inverse-primary: "#376754"
```

## Typography

**Manrope** is used for all interface headings, body text, and controls, offering warm geometric clarity and full Cyrillic legibility. **Playfair Display** is used exclusively for the book-like PDF preview (Screen 8) to give exported Bible-study notes an editorial, printed feel. **Spline Sans Mono** is used for file names, version badges, and numeric metadata.

```yaml
typography:
  display-lg:
    fontFamily: "Manrope"
    fontSize: 32px
    fontWeight: 700
    lineHeight: 38px
    letterSpacing: -0.5px
  display-lg-mobile:
    fontFamily: "Manrope"
    fontSize: 28px
    fontWeight: 700
    lineHeight: 34px
    letterSpacing: -0.4px
  headline-lg:
    fontFamily: "Manrope"
    fontSize: 24px
    fontWeight: 700
    lineHeight: 30px
    letterSpacing: -0.3px
  headline-md:
    fontFamily: "Manrope"
    fontSize: 20px
    fontWeight: 600
    lineHeight: 26px
    letterSpacing: -0.2px
  title-lg:
    fontFamily: "Manrope"
    fontSize: 18px
    fontWeight: 600
    lineHeight: 24px
    letterSpacing: 0px
  title-md:
    fontFamily: "Manrope"
    fontSize: 16px
    fontWeight: 600
    lineHeight: 22px
    letterSpacing: 0px
  body-lg:
    fontFamily: "Manrope"
    fontSize: 16px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0px
  body-md:
    fontFamily: "Manrope"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
    letterSpacing: 0.1px
  body-sm:
    fontFamily: "Manrope"
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
    letterSpacing: 0.2px
  label-lg:
    fontFamily: "Manrope"
    fontSize: 15px
    fontWeight: 600
    lineHeight: 20px
    letterSpacing: 0.1px
  label-md:
    fontFamily: "Manrope"
    fontSize: 13px
    fontWeight: 600
    lineHeight: 18px
    letterSpacing: 0.2px
  label-sm:
    fontFamily: "Manrope"
    fontSize: 11px
    fontWeight: 600
    lineHeight: 14px
    letterSpacing: 0.3px
  editorial-title:
    fontFamily: "Playfair Display"
    fontSize: 22px
    fontWeight: 700
    lineHeight: 28px
    letterSpacing: -0.2px
  editorial-body:
    fontFamily: "Playfair Display"
    fontSize: 14px
    fontWeight: 400
    lineHeight: 21px
    letterSpacing: 0px
  mono-sm:
    fontFamily: "Spline Sans Mono"
    fontSize: 12px
    fontWeight: 500
    lineHeight: 16px
    letterSpacing: 0px
```

## Layout & Spacing

Mobile-first single-column layout (`390px` viewport) with generous `20px`–`24px` page margins and `12px`–`16px` vertical gaps between cards. Primary actions sit in a clean bottom dock or at the base of the main flow so the thumb reaches them effortlessly.

```yaml
spacing:
  gutter-xs: 4px
  gutter-sm: 8px
  gutter-md: 12px
  gutter-lg: 16px
  gutter-xl: 24px
  section: 32px
  page-margin: 20px
```

## Elevation & Depth

Hierarchy is built primarily through tonal surface stepping (`surface` → `surface-container-low` → `surface-container-lowest`) paired with ultra-soft, diffused ambient shadows and subtle hairlines where tactile boundaries help:

- **Default Card Shadow:** `0 4px 20px rgba(25, 28, 27, 0.04)` (Flutter: `BoxShadow(color: Color(0x0A191C1B), blurRadius: 20, offset: Offset(0, 4))`).
- **Hero / Active Card Shadow:** `0 6px 24px rgba(25, 28, 27, 0.05)` (Flutter: `blurRadius: 24, offset: Offset(0, 6)`).
- **Drawer / Modal Shadow:** `0 12px 36px rgba(25, 28, 27, 0.12)`.
- **Borders:** `1px` (`1.0dp`) `outline-variant` at 40% opacity on resting cards; `2px` (`2.0dp`) `primary` on selected cards; `2px` dashed `outline-variant` on drop zones.
- **Icon Sizes:** `24px` (`24dp`) for top-bar navigation & action icons; `20px` for list/row leading icons and badges; `18px` for inline button icons; `15px–16px` for chip/lock badge icons; `30px` inside `56px` containers on Home hero cards.

## Typography & Licensing

All bundled fonts are licensed under the **SIL Open Font License 1.1** (`Manrope`, `Playfair Display`, `Spline Sans Mono`) so they can be packaged offline in `assets/fonts/`. Icons use **Material Symbols Rounded** (Apache License 2.0).

## Shapes

Generous, friendly corner radii define the tactile feel: `16px` (`lg`) for standard list cards and inputs, `20px`–`24px` (`xl`) for primary hero action cards and sheets, and `9999px` (`full`) for pills, chips, and primary buttons.

```yaml
rounded:
  sm: 8px
  DEFAULT: 12px
  md: 16px
  lg: 20px
  xl: 24px
  full: 9999px
```

## Motion & Micro-interaction

Motion is gentle, unhurried, and strictly functional. Button presses and toggle switches respond within `120ms`, while drawers and step transitions glide smoothly over `240ms`.

```yaml
motion:
  state-change:
    duration: 120ms
    delay: 0ms
    timingFunction: ease-out
  surface-enter:
    duration: 240ms
    delay: 0ms
    timingFunction: cubic-bezier(0.2, 0, 0, 1)
  surface-exit:
    duration: 180ms
    delay: 0ms
    timingFunction: cubic-bezier(0.3, 0, 1, 1)
```

## Voice & Content Strategy

- **Tone of voice:** Calm, reassuring, clear, and non-technical. Always in Russian with exact domain terminology (`бэкап`, `заметки`, `выделения`, `закладки`, `теги`, `основной бэкап`, `отчёт`).
- **Capitalisation:** Sentence case everywhere (`Объединить бэкапы`, `Самая свежая версия`).
- **Action labels:** Clear verb-first or outcome-focused labels; one primary button per screen.
- **Privacy reassurance:** Reinforce local processing with the subtle lock badge `Обработка только на вашем устройстве` where files or data are handled.
- **Numbers & dates:** Space-separated thousands (`4 001`, `51 582`, `1 200`), Russian long dates (`20 ноября 2026`), and `tabular-nums` on all counts and timestamps.

## Components

Component implementations live as individual HTML sticker sheet files in
`components/`. Each file contains the canonical, styled HTML components with
`<!-- COMPONENT: name -->` comment markers. Read each file before use.

- **Button** → `@components/button.html`: `button-primary`, `button-icon`, `button-with-icon`
- **Card** → `@components/card.html`: `card-elevated`, `card-action`, `card-interactive`, `card-interactive-2`
- **Chip** → `@components/chip.html`: `chip-action`, `chip-input`, `chip-with-icon`
- **Toggle** → `@components/toggle.html`: `toggle-standard`, `toggle-label`, `toggle-description`
- **Typography** → `@components/typography.html`: `typography-display`, `typography-body`, `typography-label`
