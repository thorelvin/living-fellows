"""
App icon generation, standard library only.

A home-screen shortcut with no icon looks broken, and Android wants a real PNG
rather than an SVG, so this writes one directly: zlib for the pixel data and a
hand-rolled chunk writer. It is a few dozen lines and saves a dependency.

The artwork is a dark rounded panel with a green LCD bar and an amber tuning
dot -- the faceplate, reduced until it still reads at 48 pixels.
"""

from __future__ import annotations

import struct
import zlib

_BG = (0x23, 0x26, 0x2C)
_EDGE = (0x2F, 0x33, 0x3B)
_LCD = (0x10, 0x26, 0x1F)
_LCD_INK = (0x6F, 0xE3, 0xA8)
_ACCENT = (0xC8, 0x80, 0x3A)


def _chunk(kind: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))


def _encode(size: int, rows: list[list[tuple[int, int, int]]]) -> bytes:
    raw = b"".join(b"\x00" + b"".join(bytes(px) for px in row) for row in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(raw, 9))
            + _chunk(b"IEND", b""))


def render(size: int) -> bytes:
    u = size / 64.0                      # design on a 64-unit grid, then scale
    radius = 10 * u
    rows: list[list[tuple[int, int, int]]] = []

    lcd = (6 * u, 12 * u, 58 * u, 34 * u)
    bar_y = (20 * u, 26 * u)
    dot_centre = (32 * u, 46 * u)
    dot_r = 6 * u

    for y in range(size):
        row: list[tuple[int, int, int]] = []
        for x in range(size):
            # Rounded-square mask: outside the corner arcs stays transparent-ish
            # (we have no alpha channel, so it simply takes the edge colour).
            cx = min(max(x, radius), size - radius)
            cy = min(max(y, radius), size - radius)
            if (x - cx) ** 2 + (y - cy) ** 2 > radius ** 2:
                row.append(_EDGE)
                continue

            if lcd[0] <= x < lcd[2] and lcd[1] <= y < lcd[3]:
                # A short bright bar stands in for the frequency readout.
                if bar_y[0] <= y < bar_y[1] and 11 * u <= x < 40 * u:
                    row.append(_LCD_INK)
                else:
                    row.append(_LCD)
                continue

            if (x - dot_centre[0]) ** 2 + (y - dot_centre[1]) ** 2 <= dot_r ** 2:
                row.append(_ACCENT)
                continue

            row.append(_BG)
        rows.append(row)

    return _encode(size, rows)
