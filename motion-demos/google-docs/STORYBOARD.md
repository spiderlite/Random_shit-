# Google Docs motion demo: storyboard

30 seconds, 16:9, 1920x1080, 60 fps, no audio. Built against the SaaS and product launch motion rulebook (Draft 1). Section references below point at that guide.

The piece has one message: **Docs is where a team writes together, in real time.** Each scene carries one claim and one feature. Nothing is a feature tour.

## Palette and anchor

| Role | Value | Use |
|---|---|---|
| Plain field (ground) | `#F0F4F9` | Hook and outro only. One ground per piece (guide 03, 08) |
| Ink | `#1F1F1F` | Headlines and captions |
| Brand blue | `#1A73E8` | Anchor mark, primary button, the one accent per beat |
| Collaborator orange | `#E37400` | Priya's cursor and comment (a second voice, not an accent) |
| Docs UI | sampled from reference (see `assets/`) | Everything inside the app window |

**Anchor mark.** The Google Docs brand icon is the one recurring object (guide 08 rule 2). It is the hook's focal object, the logo in the app header, and the outro's focal object. It is a single DOM element that moves between states, so the viewer tracks one thing across all three.

**Transition set.** Three types only (guide 06 and 08 cite "the answer is three"): morph (hook to app window), overlay (comment panel and share dialog, always rising from the bottom edge), and match cut (app to outro, with the anchor mark as the carried element).

## Scene timeline

| # | Time (s) | Scene | Message (one claim) | Focal object | Transition in |
|---|---|---|---|---|---|
| 1 | 0.00 to 3.40 | Hook | "Every great doc starts blank." | Anchor mark on the field | Open (no UI on screen, guide 02 rule 3) |
| 2 | 3.40 to 9.00 | Highlight | "Write it together." | Document typing with a second cursor | Morph: card expands to full window |
| 3 | 9.00 to 14.20 | Showcase: format | "Format in one click." | Bold button and the selected word | Hard cut inside the app (same frame) |
| 4 | 14.20 to 20.20 | Showcase: comment | "Comment on the exact words." | Commented sentence and its card | Overlay: card rises from bottom |
| 5 | 20.20 to 25.20 | Showcase: share | "Share it in one click." | Share dialog | Overlay: dialog rises from bottom |
| 6 | 25.20 to 30.00 | Outro | "Write together." | Anchor mark, centred | Match cut: anchor carries across |

Skeleton check against guide 09 rule 1 (hook 0 to 3, highlight 3 to 8, showcase 8 to 20, outro 20 to 30): the piece follows that skeleton within about half a second at each boundary.

## Per-scene checklist (guide section 14, part B)

Answered for every scene, in order.

**Scene 1, Hook (0.00 to 3.40)**
1. Communicates: the blank start of every document.
2. Looks first at: the anchor mark, alone on the plain field.
3. Enters first: the mark (0.00 s), then the two headline lines.
4. Moves: the mark and the two lines. Nothing else.
5. Stays still: the mark holds while each line is read. Lines reveal one at a time (guide 05 rule 1).
6. Attention path: mark, then headline below it.
7. Carried from previous: nothing (the first scene).
8. Transition out: morph. The mark's card expands in place into the app window.
9. Product shown: no. The guide says open with one claim and no product UI (02 rule 3).
10. Every moving element has a purpose: the mark is the anchor, the lines are the claim.
11. Designed, not decorated: test passes. Remove the mark and the claim still reads, but the morph into the app needs something to carry, so the mark stays.

**Scene 2, Highlight (3.40 to 9.00)**
1. Communicates: several people write in one document.
2. Looks first at: the typing title and body text, centred in the window.
3. Enters first: the window (morph ends at 3.40), then title typing, then body typing, then the second cursor.
4. Moves: the caret, the typed text and Priya's cursor. The caption (left gutter) reveals per word.
5. Stays still: the page holds still; only text changes (guide 10 rule 2).
6. Attention path: caption (left), typing (centre), second cursor label (right of the caret).
7. Carried from previous: the anchor mark shrinks into the app header logo.
8. Transition out: hard cut inside the app, no transition needed (same frame).
9. Product shown: yes, the real Docs layout.
10. Every moving element has a purpose: typing shows live editing, the second cursor shows real-time.
11. Designed, not decorated: test passes.

**Scene 3, Showcase: format (9.00 to 14.20)**
1. Communicates: formatting is one click in the toolbar you already know.
2. Looks first at: the selected word "Goal:".
3. Enters first: the selection wipe, then the pointer.
4. Moves: the pointer (ease-in-out), then the click ring, then the bold weight.
5. Stays still: everything else in the page.
6. Attention path: selection, toolbar Bold, bolded word.
7. Carried from previous: the page and the header stay put.
8. Transition out: hard cut to the comment selection.
9. Product shown: yes, the real Bold button position.
10. Every moving element has a purpose: pointer and click ring show where the action lands (guide 07 rule 2).
11. Designed, not decorated: test passes.

**Scene 4, Showcase: comment (14.20 to 20.20)**
1. Communicates: feedback lives on the exact words.
2. Looks first at: the sentence, selected, then its yellow comment highlight.
3. Enters first: the selection wipe, then the pointer, then the comment panel.
4. Moves: pointer, click ring, comment panel rising from the bottom edge (overlay).
5. Stays still: the page and the selected text.
6. Attention path: selected sentence, comment icon, comment card.
7. Carried from previous: the page stays; the card is an overlay on it.
8. Transition out: the panel is dismissed before the share scene, falling faster than it rose (exits are shorter than arrivals, guide 04 rule 2).
9. Product shown: yes, the real comment button and comment card layout.
10. Every moving element has a purpose: the card is the feature.
11. Designed, not decorated: test passes.

**Scene 5, Showcase: share (20.20 to 25.20)**
1. Communicates: sharing is one step.
2. Looks first at: the Share button, then the dialog.
3. Enters first: pointer to Share, then the dialog rising from the bottom.
4. Moves: pointer, click, dialog, "Copy link" click, toast.
5. Stays still: the dialog content while the toast is read.
6. Attention path: Share button, dialog, Copy link button, toast.
7. Carried from previous: the page under the dialog, dimmed.
8. Transition out: the dialog falls, then the match cut.
9. Product shown: yes, the real share dialog layout.
10. Every moving element has a purpose: each step is a click the viewer would make.
11. Designed, not decorated: test passes.

**Scene 6, Outro (25.20 to 30.00)**
1. Communicates: the brand and the one-line claim.
2. Looks first at: the anchor mark, centred and large.
3. Enters first: the mark (match cut from the header logo, 25.20 to 26.20), then "Write together." per word.
4. Moves: the mark (match cut, same motion), then the words.
5. Stays still: from 28.40 on, everything holds until 30.00 (guide 12 rule 4, end on a still frame).
6. Attention path: mark, headline, small disclaimer line.
7. Carried from previous: the anchor mark (match cut).
8. Transition out: none. It is the last scene.
9. Product shown: no, the outro is the claim, not the feature (guide 02 rule 3).
10. Every moving element has a purpose: the mark carries the cut, the words state the claim.
11. Designed, not decorated: test passes.

## Timing rules applied

- Text reading (guide 05 rule 5 and 09 rule 2): 0.375 s per word for the read, with a 0.3 s minimum. The hold starts when the last word lands.
  - "Every great doc" (3 words): read 1.13 s. Held from 0.70 s to 2.60 s. Long enough.
  - "starts blank." (2 words): read 0.75 s. Held from 1.40 s to 2.60 s. Long enough.
  - "Write it together." (3 words): read 1.13 s. Held 0.9 s after the last word lands at 4.6 s, then the cut comes at 6.0 s.
  - "Format in one click." (4 words): read 1.5 s. Held 2.2 s.
  - "Comment on the exact words." (5 words): read 1.9 s. Held 2.5 s.
  - "Share it in one click." (5 words): read 1.9 s. Held 2.5 s.
  - "Write together." (2 words): read 0.75 s. Held 3.4 s to the end (guide 12 rule 4).
- Easing (guide 04 rules 1, 2, 4, 6):
  - Arrivals: `cubic-bezier(0.2, 0, 0, 1)` (ease-out). Duration 420 to 560 ms.
  - Exits: `cubic-bezier(0.3, 0, 0.8, 0.15)` (ease-in), 60% of the arrival time. The guide states the reason is the exit leaves the frame. No source measures this, so it is a test-render choice.
  - Hero move, one per scene: the hook's morph uses `cubic-bezier(0.34, 1.56, 0.64, 1)` with a small overshoot. It is the only overshoot in the piece (guide 04 rule 4).
  - Pointer travel: `cubic-bezier(0.4, 0, 0.2, 1)` (ease-in-out), 520 to 680 ms.
  - Linear: only the caret's blink (guide 04 rule 3, continuous motion).
- Stagger: toolbar groups and dialog rows reveal left to right and top to bottom, the order they are read (guide 04 rule 5).
- Blur: none. The guide keeps blur off by default (guide 04 rule 7).
- Scale: the morph is the only scale change over 1.5x. Other scale changes are under 6% (guide 04 rule 6).
- Follow-through: the comment card's shadow settles a few frames after the card does. The hero (the card) lands cleanly (guide 04 rule 8).
- Camera: no camera move. Still frame throughout (guide 10 rule 2).

## Accessibility

- The demo loops only once. It runs 30 seconds, auto-starts, and stops on its last frame. There is a visible Pause button in the player, and Space toggles playback (guide 09 rule 3 and WCAG 2.2.2).
- Under `prefers-reduced-motion`, the player does not autoplay. It shows the final frame and a Play button. There is no morph or overlay motion in that mode (guide 04 rule 6, parallax and scale triggers).

## Not in this piece (and why)

- Sound. The guide puts sound last and needs a locked picture first (guide 11 rule 1). The picture is locked here, but no music or whoosh is added. The three transitions have no designed whoosh yet.
- Vertical or square crops. The guide says to re-compose for those, not crop, and this piece is one 16:9 composition (guide 03, re-compose rule).
- A presenter inset. The guide's presenter position applies to a talking-head demo. This piece has no presenter.
- Logos or wordmarks beyond the Docs brand icon. The app header uses only the icon and the title field.

## Disclaimer

This is an unofficial recreation for portfolio and study purposes. It is not affiliated with, endorsed by, or sponsored by Google. The Google Docs brand icon and the product name belong to Google. Remove or replace them before publishing as a commercial piece.
