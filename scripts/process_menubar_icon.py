#!/usr/bin/env python3
"""Turn the menu-bar art (white cleat on a dark background) into a clean,
tightly-cropped white glyph with transparency, for use as an NSStatusItem
template image.

Keeps near-white pixels, drops dark pixels, anti-aliases the edge via an
alpha ramp on luminance, then crops to the glyph's bounding box.

Usage: python3 scripts/process_menubar_icon.py <src.png> <dst.png>
"""
import sys
from PIL import Image

# Luminance ramp: <= LO becomes fully transparent (the dark background),
# >= HI becomes fully opaque white (the cleat); between is a soft edge.
LO = 110.0
HI = 200.0
MARGIN_FRAC = 0.06   # padding around the cropped glyph, as a fraction of its longer side
MAX_HEIGHT = 72      # output height in px (menu bar renders ~16-18pt; @2x stays crisp)
DEBUG = "--debug" in sys.argv


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src, dst = args[0], args[1]
    im = Image.open(src).convert("RGB")
    w, h = im.size
    src_px = im.load()

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out_px = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = src_px[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum <= LO:
                continue  # stays (0,0,0,0)
            if lum >= HI:
                out_px[x, y] = (255, 255, 255, 255)
            else:
                a = int(round((lum - LO) / (HI - LO) * 255.0))
                out_px[x, y] = (255, 255, 255, a)

    if DEBUG:
        out.save("/tmp/port_keyed_full.png")

    bbox = out.getbbox()  # honest now: transparent pixels are (0,0,0,0)
    if bbox is None:
        raise SystemExit("No near-white pixels found — check thresholds.")
    if DEBUG:
        print("keyed bbox:", bbox, "->", bbox[2] - bbox[0], "x", bbox[3] - bbox[1])
    im = out.crop(bbox)
    if DEBUG:
        im.save("/tmp/port_cropped.png")
        print("cropped size:", im.size)

    cw, ch = im.size
    pad = int(round(max(cw, ch) * MARGIN_FRAC))
    canvas = Image.new("RGBA", (cw + 2 * pad, ch + 2 * pad), (0, 0, 0, 0))
    canvas.paste(im, (pad, pad))
    im = canvas

    if im.height > MAX_HEIGHT:
        scale = MAX_HEIGHT / im.height
        im = im.resize((max(1, round(im.width * scale)), MAX_HEIGHT), Image.LANCZOS)

    im.save(dst)
    print(f"wrote {dst} ({im.width}x{im.height})")


if __name__ == "__main__":
    main()
