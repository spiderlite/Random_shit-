# Google Docs motion demo

A 30-second motion demo of Google Docs: a blank start, live co-editing, formatting, comments, sharing, and an outro. The Docs UI is rebuilt as HTML, CSS and JavaScript at 100% zoom, and the motion follows the SaaS and product launch rulebook in `STORYBOARD.md`.

This is an unofficial portfolio piece. It is not affiliated with, endorsed by, or sponsored by Google. The Google Docs icon and the product name belong to Google.

## View it

The page loads SVG masks and fonts, so serve it over HTTP. Opening `index.html` from disk will not load the icons.

```sh
npm run serve          # python3 -m http.server 8000, then open http://localhost:8000
```

| Key | Action |
|---|---|
| Space | Play or pause |
| R | Restart |
| ← / → | Step back or forward half a second |

With `prefers-reduced-motion` set, the page opens on the final frame and does not autoplay. The Pause button and the timeline slider are there for anyone who needs to stop the motion.

## Export the video

Export is frame-exact. The renderer seeks to each frame time (`window.__demo.seek(t)`), screenshots the 1920×1080 stage, and pipes the frames to ffmpeg. Nothing depends on the wall clock.

Requirements: Node 18+, Playwright with a Chromium build, and `ffmpeg` on PATH. Set `CHROMIUM_PATH` if Chromium is not at the default location.

```sh
npm install            # Playwright
npm run render         # out/google-docs-motion-demo.mp4 (60 fps, H.264)
npm run stills         # spot-check frames in out/stills/
```

## Layout

```
index.html          the stage: window, captions, pointer, anchor mark, outro, player
styles/fonts.css    Google Sans (400, 500)
styles/docs.css     the Docs window, drawn at 100% zoom in a 1280×720 viewport
styles/demo.css     the stage, captions, pointer, outro, player
js/engine.js        easing and time primitives. Every frame is a pure function of t
js/demo.js          scenes and timings. render(t) sets the whole frame
render/render.mjs   frame-accurate export (Playwright + ffmpeg)
assets/icons/       Material Symbols, outlined 24px (Apache-2.0)
assets/brand/       the Google Docs brand icon, from Wikimedia Commons
assets/fonts/       Google Sans (SIL Open Font License)
STORYBOARD.md       the scene list, timings, and per-scene checklist
```

## How the Docs UI was matched

- **Reference.** A real Docs capture (Wikimedia Commons, "Google Docs (new) screenshot") is a 1280×720 window scaled to 552 px. Its measurements were converted back to 1280×720 pixels. Colours were sampled from the image, and the window's layout was checked against it side by side.
- **Metrics.** The page is 816 px wide with 96 px margins. The body is Arial 11 pt (14.67 px). The toolbar pill is 1245 px wide. Icon centres are the measured positions.
- **Known gaps.** The reference is a small image, so exact pixel values are approximate to a pixel or two. The Docs toolbar's collapsed "Editing" label and the "Saved to Drive" text are omitted, because they do not show at the reference's 1280 px width.

## Credits and licences

- Material Symbols icons: Apache-2.0, from `google/material-design-icons`.
- Google Sans: SIL Open Font License, from Google Fonts.
- Google Docs brand icon: from Wikimedia Commons. Check its licence and the trademark position before you publish it commercially.
