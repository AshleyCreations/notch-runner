#!/usr/bin/env python3
"""
Generates the app icon and the menu-bar template icon from Bit's sprite.

Bit is defined as a pixel grid in game/index.html, and the grid below is the
same one. Keeping the icons generated rather than hand-drawn means the app
icon cannot quietly drift away from the character you actually play.

    python3 tools/make-icons.py

Writes into app/NotchRunner/Resources/Assets.xcassets.
"""

import os
import struct
import sys
import zlib

# --- Bit, exactly as game/index.html draws him -----------------------------
# A = antenna tip, X = body, E = eye, . = empty
BIT = [
    "....A.....",
    "....X.....",
    "..XXXXXX..",
    ".XXXXXXXX.",
    ".XEEXXEEX.",
    ".XEEXXEEX.",
    ".XXXXXXXX.",
    "..XXXXXX..",
    "..X....X..",
    "..X....X..",
]
COLS, ROWS = 10, len(BIT)

BODY = (0xF5, 0xB8, 0x41)       # --accent, Bit's amber
ANTENNA = (0xFF, 0xD8, 0x8A)    # --accent-2
BACKDROP = (0x0B, 0x0B, 0x0D)   # the island's near-black
GLOW = [(0xF5, 0xB8, 0x41), (0xFF, 0x9A, 0x6B), (0xB4, 0x8C, 0xF2),
        (0x6F, 0xA8, 0xFF), (0x7F, 0xC4, 0xB8)]   # the processing gradient

SS = 4                          # supersampling for the rounded corners


# --- a minimal PNG writer (no PIL on this machine) -------------------------
def write_png(path, w, h, px):
    raw = b"".join(b"\x00" + bytes(px[y * w * 4:(y + 1) * w * 4]) for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def blend(dst, i, rgb, a):
    """Source-over onto a straight-alpha RGBA buffer."""
    if a <= 0:
        return
    da = dst[i + 3] / 255.0
    out_a = a + da * (1 - a)
    for c in range(3):
        src = rgb[c] / 255.0
        d = dst[i + c] / 255.0
        dst[i + c] = int(round(((src * a + d * da * (1 - a)) / out_a) * 255)) if out_a else 0
    dst[i + 3] = int(round(out_a * 255))


def rounded_rect_coverage(x, y, w, h, radius):
    """Antialiased coverage of a rounded rectangle at pixel (x, y)."""
    hits = 0
    for sy in range(SS):
        for sx in range(SS):
            px, py = x + (sx + 0.5) / SS, y + (sy + 0.5) / SS
            cx = min(max(px, radius), w - radius)
            cy = min(max(py, radius), h - radius)
            dx, dy = px - cx, py - cy
            if dx * dx + dy * dy <= radius * radius:
                hits += 1
    return hits / (SS * SS)


def draw_bit(buf, size, origin_x, origin_y, cell, silhouette=False):
    """Bit as crisp blocks: every cell lands on whole pixels, so no blur."""
    for ry, row in enumerate(BIT):
        for rx, ch in enumerate(row):
            if ch == ".":
                continue
            if silhouette:
                # Template images are black plus alpha; the eyes are holes.
                if ch == "E":
                    continue
                rgb, alpha = (0, 0, 0), 1.0
            else:
                if ch == "E":
                    rgb, alpha = (0, 0, 0), 1.0
                elif ch == "A":
                    rgb, alpha = ANTENNA, 1.0
                else:
                    rgb, alpha = BODY, 1.0
            x0 = origin_x + rx * cell
            y0 = origin_y + ry * cell
            for y in range(int(y0), int(y0 + cell)):
                if not (0 <= y < size):
                    continue
                for x in range(int(x0), int(x0 + cell)):
                    if 0 <= x < size:
                        blend(buf, (y * size + x) * 4, rgb, alpha)


def app_icon(size):
    """Dark squircle, Bit centred, and a hint of the processing glow below."""
    buf = bytearray(size * size * 4)
    radius = size * 0.2235          # close to Apple's squircle
    inset = max(1, int(round(size * 0.055)))
    box = size - inset * 2

    for y in range(size):
        for x in range(size):
            cov = rounded_rect_coverage(x - inset, y - inset, box, box, radius)
            if cov > 0:
                blend(buf, (y * size + x) * 4, BACKDROP, cov)

    # The glow band, same idea as the bottom of the island.
    band = size * 0.17
    band_top = inset + box - band
    for y in range(int(band_top), inset + box):
        t = (y - band_top) / band
        for x in range(inset, inset + box):
            cov = rounded_rect_coverage(x - inset, y - inset, box, box, radius)
            if cov <= 0:
                continue
            pos = (x - inset) / box * (len(GLOW) - 1)
            lo = min(int(pos), len(GLOW) - 2)
            f = pos - lo
            rgb = tuple(int(GLOW[lo][c] * (1 - f) + GLOW[lo + 1][c] * f) for c in range(3))
            blend(buf, (y * size + x) * 4, rgb, cov * t * t * 0.5)

    # Rounding rather than truncating keeps Bit at a constant 62% of the icon
    # at every size; int() collapsed him to 31% at 32px and 47% at 64px.
    cell = max(1, round(size * 0.062))        # whole pixels keep Bit crisp
    bw, bh = cell * COLS, cell * ROWS
    draw_bit(buf, size, (size - bw) // 2, int(size * 0.5 - bh / 2), cell)
    return buf


def menu_icon(size):
    """Template image: Bit's silhouette, black plus alpha, eyes punched out."""
    master = size * 8
    cell = master // COLS
    buf = bytearray(master * master * 4)
    draw_bit(buf, master, (master - cell * COLS) // 2,
             (master - cell * ROWS) // 2, cell, silhouette=True)

    # Box-filter down, which antialiases the silhouette for the menu bar.
    out = bytearray(size * size * 4)
    step = master // size
    for y in range(size):
        for x in range(size):
            a = 0
            for sy in range(step):
                for sx in range(step):
                    a += buf[(((y * step + sy) * master) + x * step + sx) * 4 + 3]
            out[(y * size + x) * 4 + 3] = a // (step * step)
    return out


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    assets = os.path.join(root, "app/NotchRunner/Resources/Assets.xcassets")
    appset = os.path.join(assets, "AppIcon.appiconset")
    menuset = os.path.join(assets, "MenuBarIcon.imageset")
    os.makedirs(appset, exist_ok=True)
    os.makedirs(menuset, exist_ok=True)

    app_sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                 (256, 1), (256, 2), (512, 1), (512, 2)]
    images = []
    done = {}
    for pt, scale in app_sizes:
        px = pt * scale
        name = f"icon_{px}.png"
        if px not in done:
            write_png(os.path.join(appset, name), px, px, app_icon(px))
            done[px] = True
            print(f"  app icon {px}x{px}")
        images.append({"size": f"{pt}x{pt}", "idiom": "mac",
                       "filename": name, "scale": f"{scale}x"})
    write_json(os.path.join(appset, "Contents.json"), images)

    menu = []
    for pt, scale in [(18, 1), (18, 2)]:
        px = pt * scale
        name = f"menubar_{px}.png"
        write_png(os.path.join(menuset, name), px, px, menu_icon(px))
        menu.append({"idiom": "universal", "filename": name, "scale": f"{scale}x"})
        print(f"  menu bar {px}x{px}")
    write_json(os.path.join(menuset, "Contents.json"), menu,
               extra={"template-rendering-intent": "template"})


def write_json(path, images, extra=None):
    import json
    props = {"author": "xcode", "version": 1}
    if extra:
        props.update(extra)
    with open(path, "w") as f:
        json.dump({"images": images, "info": props}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main())
