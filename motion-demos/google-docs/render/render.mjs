#!/usr/bin/env node
// Frame-accurate export for the Docs demo.
//
//   node render/render.mjs --stills 0.5,3,9.2 --out ../scratchpad/stills
//   node render/render.mjs --mp4 out/google-docs-motion-demo.mp4 --fps 60
//
// The page exposes window.__demo.seek(t). Each frame is seeked to exactly
// i / fps, screenshotted at 1920x1080 and piped to ffmpeg. Nothing runs on the
// wall clock, so the output does not depend on how fast the machine is.
//
// Needs: Playwright with a Chromium build, and ffmpeg on PATH. Set CHROMIUM_PATH
// if Chromium is not at the default location.

import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch {
    const fallback = '/opt/node22/lib/node_modules/playwright/index.mjs';
    if (existsSync(fallback)) return import(fallback);
    throw new Error('Playwright not found. Run `npm i -D playwright` in motion-demos/google-docs.');
  }
}

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};
const stillsArg = opt('--stills', null);
const mp4Out = opt('--mp4', null);
const outDir = opt('--out', join(root, 'out', 'stills'));
const fps = Number(opt('--fps', '60'));
const duration = Number(opt('--duration', '30'));
const crf = opt('--crf', '16');

if (!stillsArg && !mp4Out) {
  console.error('Pass --stills t1,t2,... or --mp4 <file>.');
  process.exit(1);
}

// Static server so the page can load SVG masks and fonts over http.
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  try {
    const path = join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!path.startsWith(root)) throw new Error('outside root');
    const info = await stat(path);
    const file = info.isDirectory() ? join(path, 'index.html') : path;
    res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' });
    res.end(await readFile(file));
  } catch {
    res.writeHead(404);
    res.end('not found');
  }
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const port = server.address().port;

const { chromium } = await loadPlaywright();
const executablePath = process.env.CHROMIUM_PATH || (existsSync('/opt/pw-browsers/chromium') ? '/opt/pw-browsers/chromium' : undefined);
const browser = await chromium.launch({ executablePath, args: ['--font-render-hinting=none', '--disable-lcd-text'] });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
page.on('pageerror', (e) => console.error('page error:', e.message));
page.on('response', (r) => { if (r.status() >= 400) console.error('HTTP', r.status(), r.url()); });

await page.goto(`http://127.0.0.1:${port}/index.html?capture=1`);
await page.waitForFunction(() => document.body.dataset.ready === '1', null, { timeout: 30000 });

const seek = (t) => page.evaluate((x) => window.__demo.seek(x), t);

try {
  if (stillsArg) {
    await mkdir(outDir, { recursive: true });
    for (const raw of stillsArg.split(',')) {
      const t = Number(raw);
      await seek(t);
      const png = await page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: 1920, height: 1080 } });
      const file = join(outDir, `still-${t.toFixed(2).padStart(5, '0')}.png`);
      await writeFile(file, png);
      console.log('wrote', file);
    }
  }

  if (mp4Out) {
    const total = Math.round(duration * fps);
    await mkdir(dirname(resolve(mp4Out)), { recursive: true });
    const ff = spawn('ffmpeg', [
      '-y', '-loglevel', 'error',
      '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'png', '-i', '-',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', crf, '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart', '-r', String(fps),
      resolve(mp4Out),
    ], { stdio: ['pipe', 'inherit', 'inherit'] });

    const exited = new Promise((ok, fail) => ff.on('exit', (code) => (code === 0 ? ok() : fail(new Error(`ffmpeg exit ${code}`)))));
    for (let i = 0; i < total; i++) {
      const t = i / fps;
      await seek(t);
      const png = await page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: 1920, height: 1080 } });
      if (!ff.stdin.write(png)) await new Promise((ok) => ff.stdin.once('drain', ok));
      if (i % (fps * 2) === 0) console.log(`frame ${i + 1}/${total} t=${t.toFixed(2)}s`);
    }
    ff.stdin.end();
    await exited;
    console.log('wrote', resolve(mp4Out), `(${total} frames @ ${fps} fps)`);
  }
} finally {
  await browser.close();
  server.close();
}
