// Timing primitives for the Docs demo.
//
// Every visual state is a pure function of time t (seconds). Nothing here reads
// the wall clock or runs CSS transitions, so the same t always gives the same
// frame. That is what lets render/render.mjs step through the piece and export
// it without judder.

// Cubic-bezier easing curves, as [x1, y1, x2, y2].
export const CURVE = {
  out: [0.2, 0, 0, 1], // arrivals: quick start, settles into place
  in: [0.3, 0, 0.8, 0.15], // exits: shorter than arrivals, leaves the frame
  inOut: [0.4, 0, 0.2, 1], // pointer travel between two controls
  linear: [0, 0, 1, 1], // drags: the pointer and the selection wipe share one curve
  overshoot: [0.34, 1.56, 0.64, 1], // the one hero overshoot (the morph)
};

// Returns y for a given x on a cubic-bezier. Newton's method first, bisection as
// the fallback, the same approach browsers use for CSS timing functions.
export function bezier([x1, y1, x2, y2]) {
  const cx = 3 * x1;
  const bx = 3 * (x2 - x1) - cx;
  const ax = 1 - cx - bx;
  const cy = 3 * y1;
  const by = 3 * (y2 - y1) - cy;
  const ay = 1 - cy - by;
  const sampleX = (s) => ((ax * s + bx) * s + cx) * s;
  const sampleY = (s) => ((ay * s + by) * s + cy) * s;
  const slopeX = (s) => 3 * ax * s * s + 2 * bx * s + cx;

  return (x) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    let s = x;
    for (let i = 0; i < 8; i++) {
      const err = sampleX(s) - x;
      if (Math.abs(err) < 1e-6) break;
      const d = slopeX(s);
      if (Math.abs(d) < 1e-6) break;
      s -= err / d;
    }
    let lo = 0;
    let hi = 1;
    s = Math.min(Math.max(s, 0), 1);
    for (let i = 0; i < 20 && Math.abs(sampleX(s) - x) > 1e-6; i++) {
      if (sampleX(s) < x) lo = s;
      else hi = s;
      s = (lo + hi) / 2;
    }
    return sampleY(s);
  };
}

const easers = Object.fromEntries(Object.entries(CURVE).map(([k, v]) => [k, bezier(v)]));

export const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

// Linear progress through [start, start + dur], clamped to 0..1.
export const progress = (t, start, dur) => clamp01((t - start) / dur);

// Eased 0..1 for progress p, using a named curve.
export const ease = (curve, p) => easers[curve](clamp01(p));

// Opacity-style fade over [start, start + dur]. Arrivals use 'out', exits 'in'.
export function fade(t, start, dur, curve = 'out') {
  return easers[curve](progress(t, start, dur));
}

// Number of characters typed by time t, at msPerChar milliseconds each.
export function typedCount(t, start, msPerChar, length) {
  if (t < start) return 0;
  return Math.min(length, Math.floor((t - start) / (msPerChar / 1000)));
}

// Fade-and-rise for one line of a headline: opacity and vertical offset.
export function lineReveal(t, start, dur = 0.5, rise = 14) {
  const p = easers.out(progress(t, start, dur));
  return { opacity: p, y: (1 - p) * rise };
}
