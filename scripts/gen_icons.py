#!/usr/bin/env python3
"""Generate placeholder app icons (PNG/ICO/ICNS) for MyDiary.

Pure stdlib, no external deps. Design: warm amber rounded square with a
white heart — the journal / "your data belongs to you" motif.
"""
import struct
import zlib
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "src-tauri", "icons")
os.makedirs(OUT, exist_ok=True)

# Amber (matches --primary hsl(24 70% 54%)) -> rgb(230, 137, 56)
AMBER = (230, 137, 56)
AMBER_DARK = (206, 116, 42)
WHITE = (255, 255, 255)


def make_image(size: int):
    # RGBA buffer
    buf = bytearray(size * size * 4)
    cx = size / 2.0
    cy = size / 2.0
    r = size * 0.22  # corner radius
    scale = size * 0.40

    def heart(px, py):
        nx = (px - cx) / scale
        ny = (cy - py) / scale
        v = (nx * nx + ny * ny - 1.0) ** 3 - nx * nx * ny * ny * ny
        return v <= 0

    for y in range(size):
        for x in range(size):
            # rounded-rect mask
            inside = True
            if x < r and y < r:
                inside = (r - x) ** 2 + (r - y) ** 2 <= r * r
            elif x > size - r and y < r:
                inside = (x - (size - r)) ** 2 + (r - y) ** 2 <= r * r
            elif x < r and y > size - r:
                inside = (r - x) ** 2 + (y - (size - r)) ** 2 <= r * r
            elif x > size - r and y > size - r:
                inside = (x - (size - r)) ** 2 + (y - (size - r)) ** 2 <= r * r

            idx = (y * size + x) * 4
            if not inside:
                buf[idx + 3] = 0  # transparent
                continue

            # subtle vertical gradient
            t = y / size
            bg = tuple(
                int(AMBER[i] + (AMBER_DARK[i] - AMBER[i]) * t) for i in range(3)
            )
            if heart(x, y):
                col = WHITE
            else:
                col = bg
            buf[idx] = col[0]
            buf[idx + 1] = col[1]
            buf[idx + 2] = col[2]
            buf[idx + 3] = 255
    return bytes(buf)


def write_png(path, size, rgba):
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(size):
        raw.append(0)  # filter type 0
        raw.extend(rgba[y * size * 4 : (y + 1) * size * 4])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def write_ico(path, sizes):
    entries = []
    data = b""
    for s in sizes:
        img = make_image(s)
        png = _png_bytes(s, img)
        data += png
        entries.append((s, s, len(png)))
    out = b""
    out += struct.pack("<HHH", 0, 1, len(entries))
    offset = 6 + len(entries) * 16
    for (w, h, ln) in entries:
        bpp = 32
        out += struct.pack("<BBBBHHII", w if w < 256 else 0, h if h < 256 else 0, 0, 0, 1, bpp, ln, offset)
        offset += ln
    out += data
    with open(path, "wb") as f:
        f.write(out)


def _png_bytes(size, rgba):
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw.extend(rgba[y * size * 4 : (y + 1) * size * 4])
    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def write_icns(path, sizes):
    body = b""
    # ic07 = 128px PNG, ic08 = 256px PNG
    for s in sizes:
        img = make_image(s)
        png = _png_bytes(s, img)
        typ = b"ic08" if s >= 256 else b"ic07"
        body += typ + struct.pack(">I", len(png)) + png
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    write_png(os.path.join(OUT, "32x32.png"), 32, make_image(32))
    write_png(os.path.join(OUT, "128x128.png"), 128, make_image(128))
    write_png(os.path.join(OUT, "128x128@2x.png"), 256, make_image(256))
    write_ico(os.path.join(OUT, "icon.ico"), [16, 32, 48, 256])
    write_icns(os.path.join(OUT, "icon.icns"), [128, 256])
    print("icons generated:", os.listdir(OUT))
