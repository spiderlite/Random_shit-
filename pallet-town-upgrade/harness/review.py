#!/usr/bin/env python3
"""Review a recording made with `gba --record DIR`.

Every stored frame is one where at least one pixel changed, so walking the
stored frames in order shows everything that appeared on screen.

  review.py summary DIR                    runs, totals, scene cuts, idle stretches
  review.py events  DIR [--min-px N]       list stored frames, optionally only big changes
  review.py sheet   DIR -o OUT.png [...]   contact sheets of stored frames (paged)
  review.py at      DIR FRAME              which stored image was on screen at a game frame
  review.py diff    DIR SEQ_A SEQ_B -o OUT.png
                                           A, B and the changed pixels highlighted
  review.py video   DIR -o OUT.mp4 [--scale N]
                                           rebuild real-time video (each image held
                                           for as many frames as it stayed on screen)
"""
import argparse
import csv
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFont

GBA_FPS = 59.7275
SCREEN_PX = 240 * 160


def load(dir_):
    def table(name):
        path = os.path.join(dir_, name)
        if not os.path.exists(path):
            return []
        with open(path, newline="") as f:
            return list(csv.DictReader(f, delimiter="\t"))

    rows = table("index.tsv")
    for r in rows:
        for k in ("seq", "frame", "changed_px", "x0", "y0", "x1", "y1", "run"):
            r[k] = int(r[k])
    runs = table("runs.tsv")
    for r in runs:
        for k in ("run", "first_frame", "last_frame", "frames_emulated", "frames_stored"):
            r[k] = int(r[k])
    last_frame = {r["run"]: r["last_frame"] for r in runs}
    # How many game frames each stored image stayed on screen.
    for i, r in enumerate(rows):
        nxt = rows[i + 1] if i + 1 < len(rows) else None
        if nxt and nxt["run"] == r["run"]:
            r["hold"] = nxt["frame"] - r["frame"]
        else:
            r["hold"] = max(1, last_frame.get(r["run"], r["frame"]) - r["frame"] + 1)
    return rows, runs, table("inputs.tsv")


def frame_path(dir_, seq):
    return os.path.join(dir_, "frames", "%08d.png" % seq)


def select(rows, args):
    out = rows
    if args.seq:
        a, b = parse_range(args.seq)
        out = [r for r in out if a <= r["seq"] <= b]
    if args.frames:
        a, b = parse_range(args.frames)
        out = [r for r in out if a <= r["frame"] <= b]
    if args.run is not None:
        out = [r for r in out if r["run"] == args.run]
    if args.min_px:
        out = [r for r in out if r["changed_px"] >= args.min_px]
    return out


def parse_range(s):
    if "-" in s:
        a, b = s.split("-", 1)
        return int(a or 0), int(b) if b else 1 << 62
    return int(s), int(s)


def cmd_summary(args):
    rows, runs, inputs = load(args.dir)
    print("runs:")
    for r in runs:
        print("  run %d  frames %d-%d  emulated %d  stored %d  script: %s"
              % (r["run"], r["first_frame"], r["last_frame"], r["frames_emulated"], r["frames_stored"], r["script"]))
    emulated = sum(r["frames_emulated"] for r in runs)
    print("total: %d frames emulated (%.1fs of game time), %d stored with changes"
          % (emulated, emulated / GBA_FPS, len(rows)))
    cuts = [r for r in rows if r["changed_px"] >= SCREEN_PX // 2]
    print("\nscene-sized changes (>= half the screen): %d" % len(cuts))
    for r in cuts[: args.limit]:
        print("  seq %d  frame %d  %d px" % (r["seq"], r["frame"], r["changed_px"]))
    if len(cuts) > args.limit:
        print("  ... %d more (raise --limit)" % (len(cuts) - args.limit))
    idle = [r for r in rows if r["hold"] >= args.idle]
    print("\nstill for >= %d frames: %d" % (args.idle, len(idle)))
    for r in idle[: args.limit]:
        print("  seq %d  frame %d  unchanged for %d frames (%.1fs)" % (r["seq"], r["frame"], r["hold"], r["hold"] / GBA_FPS))
    if len(idle) > args.limit:
        print("  ... %d more (raise --limit)" % (len(idle) - args.limit))
    presses = [i for i in inputs if i["keys"] != "-"]
    print("\nkey presses: %d" % len(presses))
    for i in presses[: args.limit]:
        print("  run %s  frame %s  %s" % (i["run"], i["frame"], i["keys"]))


def cmd_events(args):
    rows, _, _ = load(args.dir)
    print("seq\tframe\thold\tkeys\tchanged_px\tbbox")
    for r in select(rows, args):
        print("%d\t%d\t%d\t%s\t%d\t%d,%d-%d,%d"
              % (r["seq"], r["frame"], r["hold"], r["keys"], r["changed_px"], r["x0"], r["y0"], r["x1"], r["y1"]))


def cmd_sheet(args):
    rows, _, _ = load(args.dir)
    rows = select(rows, args)
    if not rows:
        sys.exit("no frames match")
    per_page = args.cols * args.rows
    font = ImageFont.load_default()
    tw, th = 240 * args.scale, 160 * args.scale
    label_h = 12
    pad = 2
    pages = [rows[i:i + per_page] for i in range(0, len(rows), per_page)]
    if args.max_pages:
        pages = pages[: args.max_pages]
    base, ext = os.path.splitext(args.output)
    for p, page in enumerate(pages):
        sheet = Image.new("RGB", (args.cols * (tw + pad) + pad, args.rows * (th + label_h + pad) + pad), (40, 40, 40))
        draw = ImageDraw.Draw(sheet)
        for i, r in enumerate(page):
            x = pad + (i % args.cols) * (tw + pad)
            y = pad + (i // args.cols) * (th + label_h + pad)
            img = Image.open(frame_path(args.dir, r["seq"])).convert("RGB")
            if args.scale != 1:
                img = img.resize((tw, th), Image.NEAREST)
            sheet.paste(img, (x, y))
            if args.boxes and r["changed_px"] < SCREEN_PX:
                s = args.scale
                draw.rectangle([x + r["x0"] * s, y + r["y0"] * s, x + (r["x1"] + 1) * s - 1, y + (r["y1"] + 1) * s - 1],
                               outline=(255, 0, 255))
            label = "#%d f%d x%d %s %dpx" % (r["seq"], r["frame"], r["hold"], r["keys"], r["changed_px"])
            draw.text((x + 1, y + th + 1), label, fill=(230, 230, 230), font=font)
        out = args.output if len(pages) == 1 else "%s_%03d%s" % (base, p + 1, ext)
        sheet.save(out)
        print("%s  seq %d-%d  frames %d-%d" % (out, page[0]["seq"], page[-1]["seq"], page[0]["frame"], page[-1]["frame"]))
    total = (len(rows) + per_page - 1) // per_page
    if len(pages) < total:
        print("(%d of %d pages written; raise --max-pages)" % (len(pages), total))


def cmd_at(args):
    rows, _, _ = load(args.dir)
    best = None
    for r in rows:
        if r["frame"] <= args.frame:
            best = r
    if not best:
        sys.exit("nothing recorded at or before frame %d" % args.frame)
    print("seq %d (shown from frame %d for %d frames): %s"
          % (best["seq"], best["frame"], best["hold"], frame_path(args.dir, best["seq"])))


def cmd_diff(args):
    a = Image.open(frame_path(args.dir, args.a)).convert("RGB")
    b = Image.open(frame_path(args.dir, args.b)).convert("RGB")
    mask = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v else 0)
    highlight = Image.composite(Image.new("RGB", b.size, (255, 0, 255)), b.point(lambda v: v // 3), mask)
    count = mask.size[0] * mask.size[1] - mask.histogram()[0]
    s = args.scale
    out = Image.new("RGB", (3 * 240 * s + 4 * 2, 160 * s + 16), (40, 40, 40))
    draw = ImageDraw.Draw(out)
    for i, (img, label) in enumerate([(a, "seq %d" % args.a), (b, "seq %d" % args.b), (highlight, "%d px differ" % count)]):
        x = 2 + i * (240 * s + 2)
        out.paste(img.resize((240 * s, 160 * s), Image.NEAREST), (x, 2))
        draw.text((x + 1, 160 * s + 3), label, fill=(230, 230, 230), font=ImageFont.load_default())
    out.save(args.output)
    print("%s  (%d pixels differ)" % (args.output, count))


def cmd_video(args):
    rows, _, _ = load(args.dir)
    rows = select(rows, args)
    if not rows:
        sys.exit("no frames match")
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        for r in rows:
            f.write("file '%s'\nduration %.6f\n" % (os.path.abspath(frame_path(args.dir, r["seq"])), r["hold"] / GBA_FPS))
        f.write("file '%s'\n" % os.path.abspath(frame_path(args.dir, rows[-1]["seq"])))
        listing = f.name
    vf = "scale=%d:%d:flags=neighbor,format=yuv420p" % (240 * args.scale, 160 * args.scale)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing,
                    "-vf", vf, "-r", "60", "-c:v", "libx264", "-crf", "18", args.output], check=True)
    os.unlink(listing)
    secs = sum(r["hold"] for r in rows) / GBA_FPS
    print("%s  (%d stored frames, %.1fs)" % (args.output, len(rows), secs))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def filters(p):
        p.add_argument("--seq", help="stored-frame range, e.g. 100-200")
        p.add_argument("--frames", help="game-frame range, e.g. 1500-1700")
        p.add_argument("--run", type=int, help="only frames from this invocation")
        p.add_argument("--min-px", type=int, default=0, help="only frames where at least N pixels changed")

    p = sub.add_parser("summary")
    p.add_argument("dir")
    p.add_argument("--idle", type=int, default=60, help="report stretches with no change this long (frames)")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(fn=cmd_summary)

    p = sub.add_parser("events")
    p.add_argument("dir")
    filters(p)
    p.set_defaults(fn=cmd_events)

    p = sub.add_parser("sheet")
    p.add_argument("dir")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--cols", type=int, default=4)
    p.add_argument("--rows", type=int, default=4)
    p.add_argument("--scale", type=int, default=1)
    p.add_argument("--boxes", action="store_true", help="outline the changed region on each tile")
    p.add_argument("--max-pages", type=int, default=0)
    filters(p)
    p.set_defaults(fn=cmd_sheet)

    p = sub.add_parser("at")
    p.add_argument("dir")
    p.add_argument("frame", type=int)
    p.set_defaults(fn=cmd_at)

    p = sub.add_parser("diff")
    p.add_argument("dir")
    p.add_argument("a", type=int)
    p.add_argument("b", type=int)
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--scale", type=int, default=2)
    p.set_defaults(fn=cmd_diff)

    p = sub.add_parser("video")
    p.add_argument("dir")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--scale", type=int, default=3)
    filters(p)
    p.set_defaults(fn=cmd_video)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
