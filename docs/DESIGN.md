# Design notes: avoiding the "AI look", and the UX rules Haul follows

Haul's first version was designed quickly, and an audit showed it had picked up many habits of AI-generated interfaces. This file records:

- the research behind the redesign,
- what was wrong and what changed,
- how each fix is checked, so the problems stay fixed.

## 1. What makes an interface look AI-generated

Language models produce the *most likely* interface, and the most likely interface is the one the web has seen most often. Writers who have catalogued these "AI slop" tells keep finding the same ones ([ux-skill wiki][slop], [Impeccable anti-patterns][imp], [Noqta][noqta], [prg.sh][purple]):

| Area | Tell | Why it happens / why it hurts |
| --- | --- | --- |
| Colour | Indigo/purple accent, purple-to-blue gradients | A popular CSS framework's default indigo saturated tutorials, so models treat it as "a nice modern button". |
| Type | Inter (or Roboto) everywhere, heavy 700 headings | It's the statistically safe choice, so every product ends up looking the same. |
| Shape | The same large radius on every card, button, input and image | Radius stops carrying meaning. |
| Layout | Everything in cards, cards inside cards, everything centred | Containers replace hierarchy. |
| Decoration | Icon in a tinted rounded square above headings; pulsing "live" dots; glow shadows | Ornament that says nothing about state. |
| Labels | UPPERCASE labels with wide letter-spacing everywhere | Harder to read, and a template look. |
| Motion | Floating or breathing elements, bouncy (overshoot) easing, staggered fade-ins | Motion that doesn't answer "what changed?" is noise. |
| Copy | Em dashes, cute microcopy ("Ready when you are", "Warming up the engine…"), puns, round stats ("1,800+") | Reads as filler, and specific words carry more meaning. |
| Interaction | Actions that appear only on hover; missing focus styles | Invisible to keyboard, touch and screen-reader users. |
| Craft gaps | Low-contrast grey text, grey on coloured backgrounds, small tap targets, no reduced-motion support | Accessibility failures that generators rarely check. |

## 2. The principles applied instead

- **Hierarchy from size, weight and shade, not containers or colour.** Design in grayscale first and use colour sparingly ([Refactoring UI notes][rui]).
- **Visibility of system status.** Under 1 s needs only a spinner; long waits need a determinate indicator with context; very long ones run in the background ([NN/g][nng-vis], [NN/g progress][nng-prog]). Haul's progress model was already strong here and is kept.
- **WCAG 2.2 AA.** Text 4.5:1, large text and UI parts 3:1, a visible focus indicator, and targets of at least 24 px ([summary][wcag]).
- **Touch targets.** 48×48 dp on Android, 44×44 pt on iOS, with about 8 dp between targets ([Google][android-tt], [OpenReplay][tap]).
- **Thumb reach.** The main action sits at the bottom of the phone screen.
- **Every state designed.** Empty, loading, error, disabled and zero-data each say what is going on and what to do next.

## 3. Audit of Haul, and what changed

| # | Found | Fix |
| --- | --- | --- |
| 1 | Accent `#4B45E0`, essentially the default indigo | Hi-vis orange (`#B53F0B` light / `#FF8A4C` dark), chosen to mean something for an app called Haul. Danger moved to raspberry (`#B3123E`) so errors can't be confused with the accent. |
| 2 | Inter everywhere, 700-weight headings | **IBM Plex Sans** with tabular figures, 1.2 modular scale, headings at 600. **Plex Mono** only for text that is code: pairing codes, addresses, file paths, raw yt-dlp errors. |
| 3 | Tertiary text at 2.5:1 (light) and 3.8:1 (dark); danger at 4.3:1 | Every text pair is now ≥ 4.8:1 (table below), enforced by `textContrastGuideline` in tests. |
| 4 | Radius 12–24 on everything; pill-shaped composer | Semantic radii: 6 for chips and tags, 8 for controls, rows and thumbnails, 12 for cards, 16 for sheets. |
| 5 | Floating empty-state icon, breathing logo, bouncy check marks, staggered list and section entrances | Removed. What remains marks a change of state: rows fold in and out, progress glides, statuses cross-fade. No overshoot curves. |
| 6 | No reduced-motion support | `MediaQuery.disableAnimations` (Android "Remove animations", iOS "Reduce motion") sets every duration to zero, and the composer's shake is skipped. |
| 7 | Accent-coloured glow on the focused composer | Focus is a solid 2 px accent border. |
| 8 | Remove and "Show in folder" appeared only on hover | Always-visible **More** menu on every desktop row; on phones, **long-press** opens the same menu as a bottom sheet. Swipe-to-remove remains as a shortcut. |
| 9 | Nothing was keyboard-focusable; no focus ring | `Pressable` is built on `FocusableActionDetector`: Tab reaches every control, focus shows a 2 px ring, Enter or Space activates. Tested. |
| 10 | Icon buttons 36 px on phones; composer field 44 px; quality chip 34 px | 48 dp minimum on touch platforms, enforced by `androidTapTargetGuideline` and `iOSTapTargetGuideline`. |
| 11 | Buttons had fixed heights | Minimum heights, so 200% system text fits. Tested for overflow. |
| 12 | Screen readers heard each row as fragments | One label per row (title and status), progress as a value, decorative thumbnails excluded. `labeledTapTargetGuideline` passes. |
| 13 | Failed rows showed red text only | An error icon appears alongside the red, so colour is never the only signal. |
| 14 | Empty state: icon tile and cute copy, with no action | Says what goes here and offers **Paste and download**. Android shows the three share steps as a plain list. |
| 15 | Idle header showed a decorative dot and "Ready when you are" | Shows where files are saved ("Saving to ~/Downloads/Haul"). |
| 16 | Main button labelled "Paste" when it actually pastes *and starts* | "Paste and download". An empty or link-less clipboard explains itself in a toast (announced to screen readers) instead of only shaking. |
| 17 | Uppercase, letter-spaced section labels; nested box-in-a-card in Phone access | Sentence-case labels; Phone access uses plain rows inside its card. |
| 18 | Grey raw error text on the tinted error box | Ink-coloured, set in mono because it's tool output. |
| 19 | Copy: em dashes, puns ("Start hauling"), vague phrasing ("Finishing up…", "Plays everywhere") | Plain, specific copy: "Merging video and audio", "Most compatible format", "Skipped because you downloaded it before", "Continue". |
| 20 | Indigo app icons, splash and web theme colour; purple-gradient demo thumbnails | All regenerated in the new palette; demo art uses natural tones. |

### Contrast, measured (WCAG ratio against bg / surface / input)

| Theme | Colour | bg | surface | sunken |
| --- | --- | --- | --- | --- |
| Light | `ink` #1A1917 | 16.0 | 16.8 | 14.7 |
| Light | `ink2` #5C5A55 | 6.3 | 6.6 | 5.8 |
| Light | `ink3` #65635D | 5.5 | 5.8 | 5.0 |
| Light | `accent` #B53F0B | 5.2 | 5.5 | 4.8 |
| Light | `danger` #B3123E | 6.2 | 6.5 | 5.7 |
| Dark | `ink` #EFEDE8 | 16.1 | 15.0 | 13.4 |
| Dark | `ink2` #ADABA4 | 8.2 | 7.6 | 6.8 |
| Dark | `ink3` #93918A | 6.0 | 5.6 | 5.0 |
| Dark | `accent` #FF8A4C | 8.1 | 7.5 | 6.7 |
| Dark | `danger` #FF6B8B | 7.0 | 6.5 | 5.8 |

Button text: white on light accent 5.7:1; dark ink on dark accent 8.1:1.

## 4. How it stays fixed

`test/accessibility_test.dart` runs on every CI build:

- Android 48 dp and iOS 44 pt tap targets, and labelled targets, on a populated phone screen
- WCAG text contrast, in light and dark
- 200% text size with no overflow
- reduced motion collapses animation
- keyboard only: Tab reaches Settings and Enter opens it

## 5. Checklist for future changes

- [ ] One accent, used for the primary action, progress and selection only.
- [ ] No new font families. Mono only for text that is code.
- [ ] Radius from `Radii`, by role.
- [ ] Motion only to show a change of state, never looping or bouncing, and respecting `Motion.reduced`.
- [ ] Every action reachable without hover; touch targets of 48 dp or more.
- [ ] New text passes 4.5:1 (the contrast test will tell you).
- [ ] Copy says what happens, in plain words. No em dashes, puns or round numbers.
- [ ] Empty, loading and error states each offer the next step.

[slop]: https://github.com/Laith0003/ux-skill/wiki/How-to-detect-AI-slop-in-your-design
[imp]: https://mintlify.wiki/pbakaus/impeccable/concepts/anti-patterns
[noqta]: https://noqta.tn/en/blog/ai-design-slop-overused-ui-patterns-fix-2026
[purple]: https://prg.sh/ramblings/Why-Your-AI-Keeps-Building-the-Same-Purple-Gradient-Website
[rui]: https://alexanderweichart.de/5_Archive/3_Resources/Library/Refactoring-UI/Refactoring-UI-design-principles
[nng-vis]: https://nngroup.com/articles/visibility-system-status
[nng-prog]: https://nngroup.com/articles/progress-indicators
[wcag]: https://getwcag.com/blog/wcag-2-2-checklist
[android-tt]: https://support.google.com/accessibility/android/answer/7101858
[tap]: https://blog.openreplay.com/improving-tap-targets-mobile-ux/
