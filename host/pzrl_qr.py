"""
Minimal QR encoder -- byte mode, error correction level M, versions 1-6.

Standard library only, so the host keeps its "nothing to pip install" promise.
Scope is deliberately the smallest thing that encodes a LAN URL: capping at
version 6 (106 bytes) means no version-information blocks, which only appear
from version 7.

Correctness is not assumed. tests/test_qr.py compares the module matrix this
produces against the `segno` library for every version and all eight masks; the
library is a development-time oracle and is never imported here.
"""

from __future__ import annotations

# (data codewords per block, blocks) per version, EC level M.
# EC codewords per block is the third entry.
_VERSIONS = {
    1: ([(16, 1)], 10),
    2: ([(28, 1)], 16),
    3: ([(44, 1)], 26),
    4: ([(32, 2)], 18),
    5: ([(43, 2)], 24),
    6: ([(27, 4)], 16),
}

_ALIGNMENT = {
    1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34],
}

_EC_LEVEL_BITS = 0b00  # level M


# ------------------------------------------------------------ GF(256) / RS

_EXP = [0] * 512
_LOG = [0] * 256


def _init_tables() -> None:
    x = 1
    for i in range(255):
        _EXP[i] = x
        _LOG[x] = i
        x <<= 1
        if x & 0x100:
            x ^= 0x11D  # QR's primitive polynomial
    for i in range(255, 512):
        _EXP[i] = _EXP[i - 255]


_init_tables()


def _gf_mul(a: int, b: int) -> int:
    if a == 0 or b == 0:
        return 0
    return _EXP[_LOG[a] + _LOG[b]]


def _generator_poly(degree: int) -> list[int]:
    poly = [1]
    for i in range(degree):
        nxt = [0] * (len(poly) + 1)
        for j, coeff in enumerate(poly):
            nxt[j] ^= coeff
            nxt[j + 1] ^= _gf_mul(coeff, _EXP[i])
        poly = nxt
    return poly


def _ec_codewords(data: list[int], count: int) -> list[int]:
    gen = _generator_poly(count)
    remainder = list(data) + [0] * count
    for i in range(len(data)):
        factor = remainder[i]
        if factor == 0:
            continue
        for j, coeff in enumerate(gen):
            remainder[i + j] ^= _gf_mul(coeff, factor)
    return remainder[len(data):]


# ------------------------------------------------------------- data stream


def _capacity(version: int) -> int:
    groups, ec = _VERSIONS[version]
    total = sum(count * blocks for count, blocks in groups)
    return (total * 8 - 12) // 8  # 4-bit mode + 8-bit length


def _choose_version(length: int) -> int:
    for version in sorted(_VERSIONS):
        if length <= _capacity(version):
            return version
    raise ValueError(f"{length} bytes exceeds version 6 byte-mode capacity")


def _encode_data(payload: bytes, version: int) -> list[int]:
    groups, _ec = _VERSIONS[version]
    total_data = sum(count * blocks for count, blocks in groups)

    bits: list[int] = []

    def put(value: int, width: int) -> None:
        for shift in range(width - 1, -1, -1):
            bits.append((value >> shift) & 1)

    put(0b0100, 4)             # byte mode
    put(len(payload), 8)       # count indicator is 8 bits for versions 1-9
    for byte in payload:
        put(byte, 8)

    # Terminator, then pad to a byte boundary.
    for _ in range(min(4, total_data * 8 - len(bits))):
        bits.append(0)
    while len(bits) % 8:
        bits.append(0)

    codewords = [int("".join(str(b) for b in bits[i:i + 8]), 2)
                 for i in range(0, len(bits), 8)]
    pad = (0xEC, 0x11)
    index = 0
    while len(codewords) < total_data:
        codewords.append(pad[index % 2])
        index += 1
    return codewords


def _interleave(codewords: list[int], version: int) -> list[int]:
    groups, ec_count = _VERSIONS[version]

    blocks: list[list[int]] = []
    offset = 0
    for size, count in groups:
        for _ in range(count):
            blocks.append(codewords[offset:offset + size])
            offset += size

    ec_blocks = [_ec_codewords(block, ec_count) for block in blocks]

    out: list[int] = []
    for i in range(max(len(b) for b in blocks)):
        for block in blocks:
            if i < len(block):
                out.append(block[i])
    for i in range(ec_count):
        for block in ec_blocks:
            out.append(block[i])
    return out


# ------------------------------------------------------------ module matrix


def _new_matrix(size: int):
    return [[None] * size for _ in range(size)]


def _place_finder(matrix, row: int, col: int) -> None:
    for r in range(-1, 8):
        for c in range(-1, 8):
            rr, cc = row + r, col + c
            if not (0 <= rr < len(matrix) and 0 <= cc < len(matrix)):
                continue
            inner = (0 <= r <= 6 and c in (0, 6)) or \
                    (0 <= c <= 6 and r in (0, 6)) or \
                    (2 <= r <= 4 and 2 <= c <= 4)
            matrix[rr][cc] = 1 if inner else 0


def _place_alignment(matrix, version: int) -> None:
    coords = _ALIGNMENT[version]
    size = len(matrix)
    for row in coords:
        for col in coords:
            # Skip the three corners already occupied by finder patterns.
            if (row < 8 and col < 8) or (row < 8 and col > size - 9) \
                    or (row > size - 9 and col < 8):
                continue
            for r in range(-2, 3):
                for c in range(-2, 3):
                    edge = max(abs(r), abs(c))
                    matrix[row + r][col + c] = 1 if edge != 1 else 0


def _place_function_patterns(matrix, version: int) -> None:
    size = len(matrix)
    _place_finder(matrix, 0, 0)
    _place_finder(matrix, 0, size - 7)
    _place_finder(matrix, size - 7, 0)
    _place_alignment(matrix, version)

    for i in range(8, size - 8):
        bit = 1 if i % 2 == 0 else 0
        matrix[6][i] = bit
        matrix[i][6] = bit

    matrix[size - 8][8] = 1  # the always-dark module

    # Reserve the format-information areas so data placement skips them.
    for i in range(9):
        if matrix[8][i] is None:
            matrix[8][i] = 0
        if matrix[i][8] is None:
            matrix[i][8] = 0
    for i in range(8):
        if matrix[8][size - 1 - i] is None:
            matrix[8][size - 1 - i] = 0
        if matrix[size - 1 - i][8] is None:
            matrix[size - 1 - i][8] = 0


def _reserved(version: int):
    """A mask of which cells are function patterns (True) vs data (False)."""
    size = version * 4 + 17
    probe = _new_matrix(size)
    _place_function_patterns(probe, version)
    return [[cell is not None for cell in row] for row in probe]


def _place_data(matrix, reserved, stream: list[int]) -> None:
    size = len(matrix)
    bits = []
    for codeword in stream:
        for shift in range(7, -1, -1):
            bits.append((codeword >> shift) & 1)

    index = 0
    upward = True
    col = size - 1
    while col > 0:
        if col == 6:  # the vertical timing pattern is not a data column
            col -= 1
        rows = range(size - 1, -1, -1) if upward else range(size)
        for row in rows:
            for c in (col, col - 1):
                if reserved[row][c]:
                    continue
                matrix[row][c] = bits[index] if index < len(bits) else 0
                index += 1
        upward = not upward
        col -= 2


_MASKS = [
    lambda r, c: (r + c) % 2 == 0,
    lambda r, c: r % 2 == 0,
    lambda r, c: c % 3 == 0,
    lambda r, c: (r + c) % 3 == 0,
    lambda r, c: (r // 2 + c // 3) % 2 == 0,
    lambda r, c: (r * c) % 2 + (r * c) % 3 == 0,
    lambda r, c: ((r * c) % 2 + (r * c) % 3) % 2 == 0,
    lambda r, c: ((r + c) % 2 + (r * c) % 3) % 2 == 0,
]


def _apply_mask(matrix, reserved, mask: int):
    rule = _MASKS[mask]
    out = [row[:] for row in matrix]
    for r in range(len(matrix)):
        for c in range(len(matrix)):
            if not reserved[r][c] and rule(r, c):
                out[r][c] ^= 1
    return out


def _format_bits(mask: int) -> int:
    """15-bit format information: 5 data bits, BCH(15,5) check bits, then the
    spec's fixed XOR mask. Bit 14 is the MSB."""
    value = (_EC_LEVEL_BITS << 3) | mask
    remainder = value << 10
    generator = 0b101_0011_0111
    for shift in range(4, -1, -1):
        if remainder & (1 << (shift + 10)):
            remainder ^= generator << shift
    return ((value << 10) | remainder) ^ 0b101_0100_0001_0010


def _place_format(matrix, mask: int) -> None:
    size = len(matrix)
    fmt = _format_bits(mask)

    def bit(index: int) -> int:
        return (fmt >> index) & 1

    # Copy 1, wrapped around the top-left finder.
    for i in range(6):
        matrix[8][i] = bit(14 - i)
    matrix[8][7] = bit(8)
    matrix[8][8] = bit(7)
    matrix[7][8] = bit(6)
    for i in range(6):
        matrix[5 - i][8] = bit(5 - i)

    # Copy 2. Bits 0-7 run leftwards along row 8 from the right edge; bits 8-14
    # run downwards along column 8 to the bottom edge. Getting these two halves
    # the wrong way round still produces a plausible-looking symbol.
    for i in range(8):
        matrix[8][size - 1 - i] = bit(i)
    for i in range(8, 15):
        matrix[size - 15 + i][8] = bit(i)

    matrix[size - 8][8] = 1  # always dark


def _penalty(matrix) -> int:
    size = len(matrix)
    score = 0

    # Rule 1: runs of five or more identical modules in a row or column.
    for line in list(matrix) + [list(col) for col in zip(*matrix)]:
        run, prev = 1, line[0]
        for cell in line[1:]:
            if cell == prev:
                run += 1
            else:
                if run >= 5:
                    score += 3 + (run - 5)
                run, prev = 1, cell
        if run >= 5:
            score += 3 + (run - 5)

    # Rule 2: 2x2 blocks of one colour.
    for r in range(size - 1):
        for c in range(size - 1):
            if matrix[r][c] == matrix[r][c + 1] == matrix[r + 1][c] == matrix[r + 1][c + 1]:
                score += 3

    # Rule 3: finder-like 1:1:3:1:1 patterns.
    pattern_a = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
    pattern_b = list(reversed(pattern_a))
    for line in list(matrix) + [list(col) for col in zip(*matrix)]:
        for i in range(size - 10):
            window = line[i:i + 11]
            if window == pattern_a or window == pattern_b:
                score += 40

    # Rule 4: deviation from an even split of dark and light.
    dark = sum(sum(row) for row in matrix)
    percent = dark * 100 // (size * size)
    score += 10 * min(abs(percent - 50) // 5, abs(percent - 50 + 4) // 5)
    return score


def encode(data: str, version: int | None = None, mask: int | None = None):
    """Returns the QR module matrix as a list of rows of 0/1 (1 = dark)."""
    payload = data.encode("utf-8")
    if version is None:
        version = _choose_version(len(payload))
    elif len(payload) > _capacity(version):
        raise ValueError("data does not fit the requested version")

    size = version * 4 + 17
    stream = _interleave(_encode_data(payload, version), version)

    reserved = _reserved(version)
    base = _new_matrix(size)
    _place_function_patterns(base, version)
    _place_data(base, reserved, stream)

    candidates = []
    for candidate_mask in ([mask] if mask is not None else range(8)):
        masked = _apply_mask(base, reserved, candidate_mask)
        _place_format(masked, candidate_mask)
        candidates.append((_penalty(masked), candidate_mask, masked))

    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def render(matrix, quiet: int = 4, invert: bool = False) -> str:
    """Renders to text using half-block characters, two module rows per line.

    Polarity assumes a dark terminal background: light modules are drawn as
    bright blocks so the code reads as dark-on-light to a camera. `invert`
    swaps that for a light background.
    """
    size = len(matrix)
    padded = []
    blank = [0] * (size + quiet * 2)
    for _ in range(quiet):
        padded.append(blank[:])
    for row in matrix:
        padded.append([0] * quiet + list(row) + [0] * quiet)
    for _ in range(quiet):
        padded.append(blank[:])

    if len(padded) % 2:
        padded.append(blank[:])

    lines = []
    for r in range(0, len(padded), 2):
        chars = []
        for c in range(len(padded[r])):
            top = padded[r][c]
            bottom = padded[r + 1][c]
            if invert:
                top, bottom = 1 - top, 1 - bottom
            # A dark module must render as background, a light one as ink.
            if not top and not bottom:
                chars.append("█")   # both light
            elif not top and bottom:
                chars.append("▀")   # upper light
            elif top and not bottom:
                chars.append("▄")   # lower light
            else:
                chars.append(" ")        # both dark
        lines.append("".join(chars))
    return "\n".join(lines)
