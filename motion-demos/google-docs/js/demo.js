// Google Docs motion demo: scene logic.
//
// render(t) is a pure function of time. Every position, opacity and string is
// derived from t, so playback, scrubbing and frame export all show the same frame.
// Timings and reasons are in STORYBOARD.md.

import { CURVE, bezier, clamp01, progress, ease, typedCount, fade, lineReveal } from './engine.js';

export const DURATION = 30;

const $ = (id) => document.getElementById(id);

// The Docs window on the 1920x1080 stage (1280x720 at 100% zoom, centred).
const WIN = { x: 320, y: 180, w: 1280, h: 720, r: 14 };
// The hook card that morphs into the window.
const CARD = { x: 860, y: 500, w: 200, h: 200, r: 40 };
// The Docs brand icon is 800x1100 on its own canvas.
const LOGO_RATIO = 800 / 1100;

// Anchor mark: centre x, centre y, height on the stage.
const ANCHOR_HOOK = { cx: 960, cy: 600, h: 120 };
const ANCHOR_HEADER = { cx: WIN.x + 20 + 14.5, cy: WIN.y + 12 + 20, h: 40 };
const ANCHOR_OUTRO = { cx: 960, cy: 390, h: 240 };

const MORPH = { start: 2.6, end: 3.4 };
const CUT_AT = 25.2; // match cut: the app is gone, the anchor carries on

const OVERSHOOT = bezier(CURVE.overshoot); // the one hero overshoot, used by the morph

const TYPE = {
  heading: { text: 'Summary', t0: 3.9, ms: 50 },
  goal: { text: 'Goal: ship the new onboarding flow to every new user by November.', t0: 4.5, ms: 30 },
  risk: { text: 'Risk: November is tight for the mobile build.', t0: 6.7, ms: 35 },
};

// Captions sit above the window, one per feature scene.
const CAPTIONS = [
  { text: 'Write it together.', start: 4.0, end: 8.3 },
  { text: 'Format in one click.', start: 8.4, end: 12.0 },
  { text: 'Comment on the exact words.', start: 13.6, end: 19.4 },
  { text: 'Share it with one link.', start: 19.7, end: 23.5 },
];

// Clicks, in seconds. Each click draws a ring and drives the state change.
const CLICKS = { bold: 10.95, comment: 16.1, share: 21.25, copy: 23.0 };

// Rest tops of the overlays inside the window. Keep in sync with docs.css.
const COMMENT_TOP = 282;
const SHARE_TOP = 150;

// DOM handles, looked up once.
let stage, app, win, hook, hookLines, anchor, caption, outroLine, outroNote;
let pointer, ring, scrim, dialog, toast, shareBtn, commentCard;
let h1Text, h1Caret, gLabel, gSpace, gSentence, gCaret, riskText, priyaCaret;
let btnBold, boldHalo, btnComment, copyLink, outroWords = [];
let currentCap = null;
let capWords = [];

// Live layout reads, in window coordinates (1 px = 1 window px).
function stageScale() {
  return stage.getBoundingClientRect().width / 1920;
}

function rectIn(node) {
  const s = stageScale();
  const a = app.getBoundingClientRect();
  const r = node.getBoundingClientRect();
  return { x: (r.left - a.left) / s, y: (r.top - a.top) / s, w: r.width / s, h: r.height / s };
}

const centerOf = (node) => {
  const r = rectIn(node);
  return { x: r.x + r.w / 2, y: r.y + r.h / 2 };
};
const startOf = (node) => {
  const r = rectIn(node);
  return { x: r.x, y: r.y + r.h / 2 };
};
const endOf = (node) => {
  const r = rectIn(node);
  return { x: r.x + r.w, y: r.y + r.h / 2 };
};

// Pointer paths. Each entry: [time, {x, y}] in window coordinates, measured live.
const POINTERS = [
  {
    from: 9.0,
    to: 11.5,
    clicks: [CLICKS.bold],
    keys: () => [
      [9.0, { x: 1000, y: 600 }],
      [9.55, startOf(gLabel)],
      [10.0, endOf(gLabel), 'linear'],
      [10.45, centerOf(btnBold)],
      [11.5, centerOf(btnBold)],
    ],
  },
  {
    from: 14.5,
    to: 16.5,
    clicks: [CLICKS.comment],
    keys: () => [
      [14.5, startOf(gSentence)],
      [15.1, endOf(gSentence), 'linear'],
      [15.7, centerOf(btnComment)],
      [16.5, centerOf(btnComment)],
    ],
  },
  {
    from: 20.4,
    to: 23.4,
    clicks: [CLICKS.share, CLICKS.copy],
    keys: () => [
      [20.4, { x: 1000, y: 600 }],
      [21.2, centerOf(shareBtn)],
      [21.7, centerOf(shareBtn)],
      [22.45, centerOf(copyLink)],
      [23.4, centerOf(copyLink)],
    ],
  },
];

function pointerPos(keys, t) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [t0, p0] = keys[i];
    const [t1, p1, curve = 'inOut'] = keys[i + 1];
    if (t < t1) {
      const e = ease(curve, (t - t0) / (t1 - t0));
      return { x: p0.x + (p1.x - p0.x) * e, y: p0.y + (p1.y - p0.y) * e };
    }
  }
  return keys[keys.length - 1][1];
}

// Pointer tip sits at (5, 3) of a 24-unit icon, scaled to 28px.
const TIP = { x: 5.8, y: 3.5 };

function renderPointers(t) {
  let active = null;
  for (const p of POINTERS) {
    if (t >= p.from && t < p.to + 0.3) active = p;
  }
  if (!active) {
    pointer.style.opacity = 0;
    ring.style.opacity = 0;
  } else {
    const keys = active.keys();
    const pos = pointerPos(keys, t);
    const alpha = clamp01((t - active.from) / 0.25) * (1 - clamp01((t - active.to) / 0.3));
    let press = 1;
    for (const c of active.clicks) {
      if (t >= c && t < c + 0.14) press = 1 - 0.1 * Math.sin((Math.PI * (t - c)) / 0.14);
    }
    const sx = WIN.x + pos.x;
    const sy = WIN.y + pos.y;
    pointer.style.opacity = alpha;
    pointer.style.left = `${sx - TIP.x}px`;
    pointer.style.top = `${sy - TIP.y}px`;
    pointer.style.transformOrigin = `${TIP.x}px ${TIP.y}px`;
    pointer.style.transform = `scale(${press})`;
  }

  // Click ring: one per click, drawn where the pointer was at the click time.
  let ringShown = false;
  for (const p of POINTERS) {
    for (const c of p.clicks) {
      if (t >= c && t < c + 0.5 && !ringShown) {
        const e = ease('out', (t - c) / 0.5);
        const pos = pointerPos(p.keys(), c);
        ring.style.left = `${WIN.x + pos.x}px`;
        ring.style.top = `${WIN.y + pos.y}px`;
        ring.style.opacity = (1 - e) * 0.9;
        ring.style.transform = `scale(${0.5 + 0.9 * e})`;
        ringShown = true;
      }
    }
  }
  if (!ringShown) ring.style.opacity = 0;
}

function renderHook(t) {
  hook.style.opacity = t >= 2.6 ? 1 - ease('in', (t - 2.6) / 0.25) : 1;
  const starts = [0.2, 0.95];
  hookLines.forEach((node, i) => {
    const r = lineReveal(t, starts[i], 0.5, 14);
    node.style.opacity = r.opacity;
    node.style.transform = `translateY(${r.y}px)`;
  });
}

function lerpRect(a, b, e) {
  return {
    x: a.x + (b.x - a.x) * e,
    y: a.y + (b.y - a.y) * e,
    w: a.w + (b.w - a.w) * e,
    h: a.h + (b.h - a.h) * e,
    r: a.r + (b.r - a.r) * e,
  };
}

function lerpAnchor(a, b, e) {
  return { cx: a.cx + (b.cx - a.cx) * e, cy: a.cy + (b.cy - a.cy) * e, h: a.h + (b.h - a.h) * e };
}

function renderWindow(t) {
  if (t >= CUT_AT) {
    win.style.display = 'none';
    return;
  }
  win.style.display = '';
  win.style.opacity = t < 0.5 ? fade(t, 0, 0.5, 'out') : 1;
  let r = CARD;
  if (t >= MORPH.end) {
    r = WIN;
  } else if (t >= MORPH.start) {
    const e = OVERSHOOT(progress(t, MORPH.start, MORPH.end - MORPH.start));
    r = lerpRect(CARD, WIN, e);
  }
  win.style.left = `${r.x}px`;
  win.style.top = `${r.y}px`;
  win.style.width = `${r.w}px`;
  win.style.height = `${r.h}px`;
  win.style.borderRadius = `${r.r}px`;
}

function renderAnchor(t) {
  let a;
  if (t < MORPH.start) {
    a = ANCHOR_HOOK;
  } else if (t < MORPH.end) {
    a = lerpAnchor(ANCHOR_HOOK, ANCHOR_HEADER, ease('out', progress(t, MORPH.start, MORPH.end - MORPH.start)));
  } else if (t < CUT_AT) {
    a = ANCHOR_HEADER;
  } else {
    a = lerpAnchor(ANCHOR_HEADER, ANCHOR_OUTRO, ease('out', progress(t, CUT_AT, 0.8)));
  }
  const w = a.h * LOGO_RATIO;
  anchor.style.height = `${a.h}px`;
  anchor.style.left = `${a.cx - w / 2}px`;
  anchor.style.top = `${a.cy - a.h / 2}px`;
  anchor.style.opacity = t < 0.5 ? fade(t, 0, 0.5, 'out') : 1;
}

const setText = (node, s) => {
  if (node.textContent !== s) node.textContent = s;
};
const setVisible = (node, on) => {
  node.style.visibility = on ? 'visible' : 'hidden';
};
const isTyping = (t, spec) => t >= spec.t0 && t < spec.t0 + (spec.text.length * spec.ms) / 1000;

function renderApp(t) {
  app.style.opacity = t < 3.1 ? 0 : fade(t, 3.1, 0.4, 'out');

  // Typing: heading, goal line (split into label, space and sentence), risk line (Priya).
  const hN = typedCount(t, TYPE.heading.t0, TYPE.heading.ms, TYPE.heading.text.length);
  setText(h1Text, TYPE.heading.text.slice(0, hN));
  setVisible(h1Caret, isTyping(t, TYPE.heading));

  const gs = TYPE.goal.text;
  const gN = typedCount(t, TYPE.goal.t0, TYPE.goal.ms, gs.length);
  setText(gLabel, gs.slice(0, Math.min(gN, 5)));
  setText(gSpace, gs.slice(5, Math.min(gN, 6)));
  setText(gSentence, gs.slice(6, Math.max(gN, 6)));
  setVisible(gCaret, isTyping(t, TYPE.goal));

  const rN = typedCount(t, TYPE.risk.t0, TYPE.risk.ms, TYPE.risk.text.length);
  setText(riskText, TYPE.risk.text.slice(0, rN));
  priyaCaret.style.opacity = t < 6.6 ? 0 : fade(t, 6.6, 0.25, 'out');

  // Bold, selection and comment highlight.
  gLabel.classList.toggle('is-bold', t >= CLICKS.bold);
  const labelSel = t < 9.55 ? 0 : t < 10.0 ? (t - 9.55) / 0.45 : t < 11.6 ? 1 : 0;
  gLabel.style.backgroundSize = `${labelSel * 100}% 100%`;

  const commented = t >= CLICKS.comment;
  const sentSel = t < 14.5 ? 0 : t < 15.1 ? (t - 14.5) / 0.6 : commented ? 0 : 1;
  gSentence.classList.toggle('commented', commented);
  gSentence.style.backgroundSize = commented ? '100% 100%' : `${sentSel * 100}% 100%`;

  const boldOn = t >= CLICKS.bold && t < 14.2;
  btnBold.classList.toggle('is-active', boldOn);
  boldHalo.style.opacity = boldOn ? 1 : 0;

  // Comment card: overlay, rises from the bottom edge, leaves faster than it arrived.
  let ccA = 0;
  let ccY = WIN.h - COMMENT_TOP;
  if (t >= 16.2 && t < 19.7) {
    const enter = ease('out', (t - 16.2) / 0.6);
    const exit = t >= 19.4 ? ease('in', (t - 19.4) / 0.3) : 0;
    ccA = enter * (1 - exit);
    ccY = (1 - enter) * (WIN.h - COMMENT_TOP) + exit * 16;
  }
  commentCard.style.opacity = ccA;
  commentCard.style.transform = `translateY(${ccY}px)`;

  // Share: the button presses, the scrim and dialog rise, then fall away.
  shareBtn.style.transform = t >= CLICKS.share && t < CLICKS.share + 0.15 ? 'scale(0.94)' : '';
  const scrimIn = t >= 21.5 ? ease('out', (t - 21.5) / 0.4) : 0;
  const scrimOut = t >= 24.8 ? ease('in', (t - 24.8) / 0.3) : 0;
  scrim.style.opacity = scrimIn * (1 - scrimOut);

  const dIn = t >= 21.5 ? ease('out', (t - 21.5) / 0.5) : 0;
  const dOut = t >= 24.7 ? ease('in', (t - 24.7) / 0.25) : 0;
  dialog.style.opacity = dIn * (1 - dOut);
  dialog.style.transform = `translateY(${(1 - dIn) * (WIN.h - SHARE_TOP) + dOut * 24}px)`;

  const tIn = t >= 23.1 ? ease('out', (t - 23.1) / 0.4) : 0;
  const tOut = t >= 24.9 ? ease('in', (t - 24.9) / 0.3) : 0;
  toast.style.opacity = tIn * (1 - tOut);
  toast.style.transform = `translate(-50%, ${(1 - tIn) * 16 + tOut * 12}px)`;
}

// Captions: one phrase per scene, words reveal one at a time, then a short exit.
function renderCaption(t) {
  const cap = CAPTIONS.find((c) => t >= c.start && t < c.end);
  if (!cap) {
    caption.style.opacity = 0;
    currentCap = null;
    return;
  }
  if (cap !== currentCap) {
    caption.textContent = '';
    capWords = cap.text.split(' ').map((word) => {
      const span = document.createElement('span');
      span.className = 'w';
      span.textContent = word;
      caption.append(span);
      return span;
    });
    currentCap = cap;
  }
  caption.style.opacity = t > cap.end - 0.25 ? 1 - ease('in', (t - (cap.end - 0.25)) / 0.25) : 1;
  capWords.forEach((node, i) => {
    const p = ease('out', (t - (cap.start + i * 0.07)) / 0.35);
    node.style.opacity = p;
    node.style.transform = `translateY(${(1 - p) * 12}px)`;
  });
}

// Outro: the anchor carries the cut. Two words reveal, then a disclaimer.
function renderOutro(t) {
  outroWords.forEach((node, i) => {
    const p = ease('out', (t - (26.2 + i * 0.14)) / 0.5);
    node.style.opacity = p;
    node.style.transform = `translateY(${(1 - p) * 14}px)`;
  });
  outroNote.style.opacity = t >= 27.2 ? ease('out', (t - 27.2) / 0.4) : 0;
}

export function render(t) {
  renderHook(t);
  renderWindow(t);
  renderApp(t);
  renderCaption(t);
  renderPointers(t);
  renderAnchor(t);
  renderOutro(t);
}

// Fit the 1920x1080 stage to the viewport. The renderer's viewport is exactly
// 1920x1080, so the scale is 1 there.
function fit() {
  const s = Math.min(window.innerWidth / 1920, window.innerHeight / 1080);
  stage.style.transform = `scale(${s})`;
  stage.style.left = `${(window.innerWidth - 1920 * s) / 2}px`;
  stage.style.top = `${(window.innerHeight - 1080 * s) / 2}px`;
}

async function init() {
  stage = $('stage');
  app = $('app');
  win = $('window');
  hook = $('hook');
  hookLines = [...hook.querySelectorAll('.hook-line')];
  anchor = $('anchor');
  caption = $('caption');
  outroLine = $('outro-line');
  outroNote = $('outro-note');
  pointer = $('pointer');
  ring = $('click-ring');
  scrim = $('scrim');
  dialog = $('share-dialog');
  toast = $('toast');
  shareBtn = $('share-btn');
  commentCard = $('comment-card');
  h1Text = $('h1-text');
  h1Caret = $('h1-caret');
  gLabel = $('g-label');
  gSpace = $('g-space');
  gSentence = $('g-sentence');
  gCaret = $('g-caret');
  riskText = $('risk-text');
  priyaCaret = $('priya-caret');
  btnBold = $('btn-bold');
  boldHalo = $('bold-halo');
  btnComment = $('btn-comment');
  copyLink = $('copy-link');

  // Outro words, one span each
  outroLine.innerHTML = '<span class="w">Write</span><span class="w">together.</span>';
  outroWords = [...outroLine.querySelectorAll('.w')];

  // Icons: each mask points at its SVG. Absolute URLs, because a mask URL in a
  // stylesheet resolves against that stylesheet's folder, not the page.
  document.querySelectorAll('[data-icon]').forEach((node) => {
    const href = new URL(`assets/icons/${node.dataset.icon}.svg`, document.baseURI).href;
    node.style.setProperty('--icon', `url("${href}")`);
  });

  fit();
  window.addEventListener('resize', fit);

  await document.fonts.ready;
  await anchor.querySelector('img').decode().catch(() => {});

  document.body.dataset.ready = '1';
}

// Player (browser only). The export never touches these.
function setupPlayer() {
  const playBtn = $('play');
  const scrub = $('scrub');
  const clock = $('clock');
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let t = reduced ? DURATION : 0;
  let playing = !reduced;
  let last = performance.now();

  const label = () => {
    if (playing) return 'Pause';
    return t >= DURATION ? 'Replay' : 'Play';
  };
  const show = () => {
    render(t);
    scrub.value = String(t);
    clock.textContent = `${t.toFixed(2)} / ${DURATION.toFixed(2)} s`;
    playBtn.textContent = label();
  };
  const seek = (next) => {
    t = Math.max(0, Math.min(DURATION, next));
    show();
  };
  const togglePlay = () => {
    if (!playing && t >= DURATION) t = 0;
    playing = !playing;
    last = performance.now();
    show();
  };

  playBtn.addEventListener('click', togglePlay);
  scrub.addEventListener('input', () => {
    playing = false;
    seek(Number(scrub.value));
  });
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Space') {
      e.preventDefault();
      togglePlay();
    } else if (e.key === 'r' || e.key === 'R') {
      t = 0;
      playing = true;
      last = performance.now();
      show();
    } else if (e.key === 'ArrowRight') {
      playing = false;
      seek(t + 0.5);
    } else if (e.key === 'ArrowLeft') {
      playing = false;
      seek(t - 0.5);
    }
  });

  const tick = (now) => {
    if (playing) {
      // Clamp the step: rAF stops in a hidden tab, and the first frame back
      // would otherwise jump the piece by the whole absence.
      t += Math.min((now - last) / 1000, 0.1);
      if (t >= DURATION) {
        t = DURATION;
        playing = false;
      }
      show();
    }
    last = now;
    requestAnimationFrame(tick);
  };
  show();
  requestAnimationFrame(tick);
}

await init();

// The renderer seeks to exact times through this hook.
window.__demo = {
  duration: DURATION,
  seek(t) {
    render(Math.max(0, Math.min(DURATION, t)));
  },
};

if (!document.body.classList.contains('capture') && !/[?&]capture\b/.test(location.search)) {
  setupPlayer();
} else {
  document.body.classList.add('capture');
  render(0);
}
