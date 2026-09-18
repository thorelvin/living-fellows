"""Verifies pzrl_qr against the `segno` library and by decoding its own output.

segno is a DEVELOPMENT-TIME ORACLE ONLY. The shipped host never imports it, and
this test exits 2 (inconclusive, not passing) when it is absent:

    python -m venv /tmp/qrvenv && /tmp/qrvenv/Scripts/pip install segno
    /tmp/qrvenv/Scripts/python tests/test_qr.py

Three gates, because no single one is sufficient:

  1. Full-capacity exact match. For payloads that exactly fill a version, no pad
     codewords exist, so our matrix must equal segno's module for module. This
     is the gold standard: it validates data encoding, Reed-Solomon, block
     interleaving, module placement, alignment and timing patterns, all eight
     masks, and the format information.

  2. Function modules for padded payloads. segno pads differently from us -- it
     emits a 0x00 codeword where the spec's alternating 0xEC/0x11 filler starts
     (we follow Nayuki's reference here) -- so data modules legitimately differ.
     Function patterns and format info must still match exactly.

  3. Round trip. Our own matrices are decoded back through an independent path
     (un-mask, read, de-interleave, verify Reed-Solomon syndromes, parse the
     byte-mode header) and must yield the original string. Padding lives in
     unused filler, so a padding difference cannot hide a real defect here.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "host"))

import pzrl_qr as Q  # noqa: E402

try:
    import segno
except ImportError:
    print("segno not installed - cannot verify against a reference.")
    print("INCONCLUSIVE (not a pass).")
    sys.exit(2)

URLS = [
    "http://192.168.1.42:8777/",
    "http://127.0.0.1:8777/?t=0123456789abcdef",
    "http://10.0.0.7:8777/?t=deadbeefcafe1234",
    "A",
    "http://192.168.100.200:65535/?t=ffffffffffffffff",
    # BF-01 lengthened the pairing key to 128 bits. The encoder tops out at
    # version 6, so the security fix must not quietly become a pairing failure.
    "http://192.168.100.200:65535/?t=" + "f" * 32,
    "http://255.255.255.255:65535/?t=" + "0" * 32,
    "x" * 100,
]

failures: list[str] = []
checks = 0


def fail(message: str) -> None:
    failures.append(message)
    print(f"  FAIL {message}")


# --------------------------------------------------------------- decoder


def decode(matrix, version: int) -> bytes:
    """Independent read-back: un-mask, extract, de-interleave, RS-check, parse."""
    size = len(matrix)
    reserved = Q._reserved(version)

    # Recover the mask from the format information rather than being told it.
    fmt = 0
    for i in range(8):
        fmt |= matrix[8][size - 1 - i] << i
    for i in range(8, 15):
        fmt |= matrix[Q_size_row(size, i)][8] << i
    unmasked_fmt = fmt ^ 0b101_0100_0001_0010
    mask = (unmasked_fmt >> 10) & 0b111

    plain = [row[:] for row in matrix]
    for r in range(size):
        for c in range(size):
            if not reserved[r][c] and Q._MASKS[mask](r, c):
                plain[r][c] ^= 1

    bits: list[int] = []
    upward = True
    col = size - 1
    while col > 0:
        if col == 6:
            col -= 1
        rows = range(size - 1, -1, -1) if upward else range(size)
        for row in rows:
            for c in (col, col - 1):
                if not reserved[row][c]:
                    bits.append(plain[row][c])
        upward = not upward
        col -= 2

    stream = [int("".join(map(str, bits[i:i + 8])), 2)
              for i in range(0, len(bits) // 8 * 8, 8)]

    groups, ec_count = Q._VERSIONS[version]
    sizes = [size_ for size_, count in groups for _ in range(count)]
    total_data = sum(sizes)

    # Undo the interleave.
    blocks: list[list[int]] = [[] for _ in sizes]
    index = 0
    for i in range(max(sizes)):
        for b, block_size in enumerate(sizes):
            if i < block_size:
                blocks[b].append(stream[index])
                index += 1
    ec_blocks: list[list[int]] = [[] for _ in sizes]
    for i in range(ec_count):
        for b in range(len(sizes)):
            ec_blocks[b].append(stream[total_data + i * len(sizes) + b])

    # A non-zero syndrome means the symbol would not decode in a scanner.
    for block, ec in zip(blocks, ec_blocks):
        full = block + ec
        for power in range(ec_count):
            syndrome = 0
            for coeff in full:
                syndrome = Q._gf_mul(syndrome, Q._EXP[power]) ^ coeff
            if syndrome != 0:
                raise ValueError("Reed-Solomon syndrome non-zero")

    data = [cw for block in blocks for cw in block]
    flat: list[int] = []
    for cw in data:
        for shift in range(7, -1, -1):
            flat.append((cw >> shift) & 1)

    mode = int("".join(map(str, flat[0:4])), 2)
    if mode != 0b0100:
        raise ValueError(f"unexpected mode {mode:04b}")
    count = int("".join(map(str, flat[4:12])), 2)
    out = bytearray()
    for i in range(count):
        chunk = flat[12 + i * 8: 20 + i * 8]
        out.append(int("".join(map(str, chunk)), 2))
    return bytes(out)


def Q_size_row(size: int, i: int) -> int:
    return size - 15 + i


# ------------------------------------------- 1. full-capacity exact match

print("full-capacity exact match vs segno")
for version in sorted(Q._VERSIONS):
    payload = "x" * Q._capacity(version)
    for mask in range(8):
        mine = Q.encode(payload, version=version, mask=mask)
        theirs = [list(r) for r in segno.make(
            payload, error="m", version=version, mask=mask,
            mode="byte", boost_error=False).matrix]
        checks += 1
        if mine != theirs:
            fail(f"v{version} mask{mask} full-capacity matrix differs")
print(f"  {checks} matrices compared")

# -------------------------------------- 2. function modules, padded input

print("function patterns and format info vs segno (padded payloads)")
for data in URLS:
    length = len(data.encode())
    for version in sorted(Q._VERSIONS):
        if length > Q._capacity(version):
            continue
        reserved = Q._reserved(version)
        for mask in range(8):
            mine = Q.encode(data, version=version, mask=mask)
            theirs = [list(r) for r in segno.make(
                data, error="m", version=version, mask=mask,
                mode="byte", boost_error=False).matrix]
            checks += 1
            bad = [(r, c) for r in range(len(mine)) for c in range(len(mine))
                   if reserved[r][c] and mine[r][c] != theirs[r][c]]
            if bad:
                fail(f"v{version} mask{mask} function modules differ at {bad[:6]}")

# ------------------------------------------------------- 3. round trip

print("round-trip decode of our own output")
for data in URLS:
    length = len(data.encode())
    for version in sorted(Q._VERSIONS):
        if length > Q._capacity(version):
            continue
        for mask in range(8):
            mine = Q.encode(data, version=version, mask=mask)
            checks += 1
            try:
                got = decode(mine, version)
            except ValueError as error:
                fail(f"v{version} mask{mask} {data[:24]!r}: {error}")
                continue
            if got != data.encode():
                fail(f"v{version} mask{mask} decoded {got[:24]!r} != {data[:24]!r}")

# Automatic selection must pick a version that holds the data and still decode.
for data in URLS:
    mine = Q.encode(data)
    version = (len(mine) - 17) // 4
    checks += 1
    if decode(mine, version) != data.encode():
        fail(f"auto-selected v{version} does not round trip for {data[:24]!r}")

# ------------------------------------------------ 4. renderer round trip

print("render -> text -> matrix round trip")
_GLYPHS = {"█": (0, 0), "▀": (0, 1), "▄": (1, 0), " ": (1, 1)}

for data in URLS[:4]:
    for invert in (False, True):
        matrix = Q.encode(data)
        quiet = 4
        text = Q.render(matrix, quiet=quiet, invert=invert)
        rows: list[list[int]] = []
        for line in text.split("\n"):
            top, bottom = [], []
            for char in line:
                if char not in _GLYPHS:
                    fail(f"renderer emitted unexpected glyph {char!r}")
                    break
                t, b = _GLYPHS[char]
                if invert:
                    t, b = 1 - t, 1 - b
                top.append(t)
                bottom.append(b)
            rows.append(top)
            rows.append(bottom)
        # Strip the quiet zone (and the padding row when the height is odd).
        inner = [row[quiet:len(row) - quiet] for row in rows[quiet:quiet + len(matrix)]]
        checks += 1
        if inner != matrix:
            fail(f"render round trip differs for {data[:24]!r} invert={invert}")

print()
print(f"{checks} checks")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("QR ENCODER VERIFIED")
