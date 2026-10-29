#!/usr/bin/env python3
"""Bakes the Android launcher icon out of assets/icon/icon.png.

The icon is a few hexes of the map with a city in the middle: Bandholm on
its hills, mountains and a forest below, in the game's eight sepias (a shot of
seed 7 at turn 80, the labels left off). It is kept at the game's own pixels,
96px square, and every size here is a whole-number scale of it (a 96px picture
resampled to fit a box comes out as a smear), centred, scaled up past the
edges and cropped rather than left short of them.

Two sets are written into a love-android checkout's res/ directory:

- drawable-*dpi/love.png, the square legacy icon (48dp), which is what the
  manifest's @drawable/love names and what launchers before Android 8 use;
- drawable-*dpi/love_bg.png and love_fg.png plus drawable-anydpi-v26/love.xml,
  the adaptive icon (108dp), which every launcher since then prefers. The
  map is the background, full bleed, so the launcher's mask only crops its
  edges and the city stays in the middle; the foreground is left clear.

Standard library only (zlib), so the workflow needs nothing installed.

    python3 android/icon.py <love-android>/app/src/main/res
"""

import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(ROOT, "assets", "icon", "icon.png")

# (density, legacy px, adaptive layer px)
DENSITIES = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]


def read_png(path):
    """An 8-bit RGBA or RGB, non-interlaced PNG -> (w, h, [[(r, g, b, a)]])."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("icon.py: %s is not a PNG" % path)
    pos, idat, head = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            head = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = head
    if depth != 8 or ctype not in (2, 6) or interlace:
        sys.exit("icon.py: %s must be 8-bit RGB(A), not interlaced" % path)
    bpp = 4 if ctype == 6 else 3
    raw, stride = zlib.decompress(idat), w * bpp
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(h):
        kind, line = raw[pos], bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append([tuple(line[x * bpp:x * bpp + bpp]) + ((255,) if bpp == 3 else ()) for x in range(w)])
        prev = line
    return w, h, rows


def png(path, size, pixels):
    """pixels(x, y) -> (r, g, b, a). Writes an 8-bit RGBA PNG."""
    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter: none
        for x in range(size):
            raw.extend(pixels(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))


def picture():
    w, h, rows = read_png(ICON)
    if w != h:
        sys.exit("icon.py: the icon must be square")
    return w, rows


def cover(side, size):
    """Smallest whole scale that leaves no edge of the square uncovered."""
    return -(-size // side)


def icon(size, side, rows):
    """The picture filling a size x size square, centred and cropped."""
    scale = cover(side, size)
    off = (size - side * scale) // 2

    def pixel(x, y):
        return rows[(y - off) // scale][(x - off) // scale]

    return pixel


def clear(x, y):
    return (0, 0, 0, 0)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    res = sys.argv[1]
    side, rows = picture()

    for density, size, layer in DENSITIES:
        folder = os.path.join(res, "drawable-" + density)
        png(os.path.join(folder, "love.png"), size, icon(size, side, rows))
        png(os.path.join(folder, "love_bg.png"), layer, icon(layer, side, rows))
        png(os.path.join(folder, "love_fg.png"), layer, clear)

    adaptive = os.path.join(res, "drawable-anydpi-v26")
    os.makedirs(adaptive, exist_ok=True)
    with open(os.path.join(adaptive, "love.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/love_bg" />\n'
            '    <foreground android:drawable="@drawable/love_fg" />\n'
            '</adaptive-icon>\n'
        )


if __name__ == "__main__":
    main()
