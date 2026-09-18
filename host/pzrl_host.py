"""
PZ Radio Link -- local host.

Standard library only. There is nothing to pip install and no virtualenv to
create: `python pzrl_host.py` is the whole thing.

The mod cannot open a socket -- Kahlua has no socket library -- so this process
is the web server, and it talks to the mod through small framed files under
<userdir>/Zomboid/Lua/PZRL. The game stays authoritative for every radio state;
nothing here simulates power, battery, channel or reception.

Binds the LAN interface by default so a phone can reach it, with `--localhost`
for loopback only. Access is gated by a pairing key delivered through the QR
code the launcher prints.

Trust boundary: this is plain HTTP on a local network. Python documents
http.server as providing only basic security checks, and the key is a bearer
token, not encryption. It keeps another device on your LAN from driving the
radio; it is not a reason to expose this to the internet.
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import re
import secrets
import socket
import socketserver
import sys
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pzrl_broker
import pzrl_icon
import pzrl_qr

# Protocol 2. The framing magic changed with it because protocol 1 dispatch did
# not enforce the version field, so a v1 mod handed a v2 command would act on
# it. A mixed install now fails to parse instead of half-working.
PROTOCOL = 2
MAGIC = "PZRL2"
FOOTER = "PZRLEND"
MAX_PAYLOAD_BYTES = 16384
# Lua numbers are doubles; stay inside exact-integer range on both sides.
MAX_SAFE_INT = 2 ** 53 - 1
MAX_BODY_BYTES = 4096

WEB_ROOT = Path(__file__).resolve().parent / "web"


# --------------------------------------------------------------------- codec


def checksum(payload: str) -> int:
    """djb2 mod 2**32 over UTF-8 bytes. Must match PZRL_Codec.checksum exactly."""
    h = 5381
    for byte in payload.encode("utf-8"):
        h = (h * 33 + byte) % 4294967296
    return h


# '|' is permitted because the preset list uses it to separate entries. It cannot
# collide with the pair separator ';' or the key separator '='. Preset *names*
# have '|' stripped where they are built, so a name can never split an entry.
_SAFE = set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.:-+| "
)


def sanitize(value: object, max_bytes: int = 64) -> str:
    text = "" if value is None else str(value)
    text = "".join(ch for ch in text if ch in _SAFE)
    return text[:max_bytes]


def encode_payload(pairs: list[tuple[str, object]]) -> str:
    return ";".join(f"{key}={sanitize(value)}" for key, value in pairs)


def decode_payload(payload: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for chunk in payload.split(";"):
        if not chunk:
            continue
        key, sep, value = chunk.partition("=")
        if sep and key:
            fields[key] = value
    return fields


def frame(seq: int, pairs: list[tuple[str, object]]) -> str:
    payload = encode_payload(pairs)
    encoded = payload.encode("utf-8")
    if len(encoded) > MAX_PAYLOAD_BYTES:
        raise ValueError("payload too large")
    header = f"{MAGIC} seq={seq} len={len(encoded)} crc={checksum(payload)}"
    return f"{header}\n{payload}\n{FOOTER}\n"


def parse(text: str) -> tuple[dict[str, str], int] | None:
    """Returns (fields, seq) only for a completely valid document."""
    # Tolerate either line ending: Lua's readLine() strips both, so the two
    # sides must agree on that rather than only on \n.
    lines = [line.rstrip("\r") for line in text.split("\n")]
    if len(lines) < 3:
        return None
    header, payload, footer = lines[0], lines[1], lines[2]
    if footer != FOOTER:
        return None
    if not header.startswith(MAGIC + " "):
        return None
    try:
        parts = dict(
            piece.split("=", 1) for piece in header[len(MAGIC) + 1:].split(" ")
        )
        seq = int(parts["seq"])
        length = int(parts["len"])
        crc = int(parts["crc"])
    except (ValueError, KeyError):
        return None
    if len(payload.encode("utf-8")) != length:
        return None
    if checksum(payload) != crc:
        return None
    return decode_payload(payload), seq


# ------------------------------------------------------------------- mailbox


MAX_STATE_BYTES = 64 * 1024


class MailboxBusy(Exception):
    """Another host already owns this mailbox directory."""


class Mailbox:
    """Reads the mod's A/B state slots; writes the single command document."""

    def __init__(self, lua_dir: Path, take_lock: bool = True) -> None:
        self.dir = lua_dir / "PZRL"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.command_path = self.dir / "cmd.txt"
        self.state_paths = [self.dir / "state_a.txt", self.dir / "state_b.txt"]
        self._lock = threading.Lock()
        self._last_good: dict[str, str] | None = None
        self._last_identity: tuple[str, int] | None = None
        self._last_change = 0.0
        self._seen_heartbeat = False
        self._lock_handle = None
        if take_lock:
            self._acquire_directory_lock()
        # BF-05: the command sequence must start above anything the mod may
        # still treat as consumed. Seeding from the clock meant a restart after
        # a burst could emit *lower* numbers, which the mod silently drops.
        self._seq = self._recover_sequence()

    # ------------------------------------------------------ directory lock

    def _acquire_directory_lock(self) -> None:
        """Binding the HTTP port is not enough: two hosts on different ports
        would happily write the same cmd.txt. The lock is held open for the
        process lifetime, so the OS releases it even on a hard exit."""
        path = self.dir / "host.lock"
        try:
            handle = open(path, "a+b")
        except OSError:
            return  # cannot lock; better to run than to refuse over this
        try:
            import msvcrt

            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        except ImportError:
            try:
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except (ImportError, OSError):
                handle.close()
                raise MailboxBusy(str(path))
        except OSError:
            handle.close()
            raise MailboxBusy(str(path))
        self._lock_handle = handle

    def _recover_sequence(self) -> int:
        """Start above the highest command sequence still on disk."""
        try:
            text = self.command_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            return 0
        parsed = parse(text)
        return parsed[1] if parsed else 0

    # ------------------------------------------------------------- reading

    def _read_bounded(self, path: Path) -> str | None:
        """Bound the read before allocating the whole file: a corrupt or
        hostile state file must not be loaded in full first."""
        try:
            with open(path, "rb") as handle:
                blob = handle.read(MAX_STATE_BYTES + 1)
        except OSError:
            return None
        if len(blob) > MAX_STATE_BYTES:
            return None
        try:
            # Binary reads skip the newline translation read_text() performs, so
            # normalize here: a CRLF-written document would otherwise leave a
            # stray \r on every line and never match the footer.
            return blob.decode("utf-8").replace("\r\n", "\n")
        except UnicodeDecodeError:
            return None

    def read_state(self) -> tuple[dict[str, str] | None, float]:
        """Highest validating slot wins. A torn slot is ignored, never fatal.

        BF-05: identity is (epoch, sequence), not a bare sequence. A new game
        session restarts its sequence, so sequence alone made a fresh document
        look like a repeat of an old one.
        """
        best: tuple[dict[str, str], int] | None = None
        for path in self.state_paths:
            text = self._read_bounded(path)
            if text is None:
                continue
            parsed = parse(text)
            if parsed is None:
                continue
            if best is None or parsed[1] > best[1]:
                best = parsed

        if best is not None:
            identity = (best[0].get("epoch", ""), best[1])
            if identity != self._last_identity:
                # Only an *advancing* document proves a live game. The first
                # read of a file left over from yesterday does not.
                if self._last_identity is not None:
                    self._seen_heartbeat = True
                self._last_good, self._last_identity = best[0], identity
                self._last_change = time.monotonic()

        if self._last_good is None:
            return None, 999.0
        if not self._seen_heartbeat:
            # Present but unproven: treat as stale until it moves.
            return self._last_good, 999.0
        return self._last_good, time.monotonic() - self._last_change

    # ------------------------------------------------------------- writing

    def send_command(self, pairs: list[tuple[str, object]], request_id: str = "") -> int:
        with self._lock:
            self._seq += 1
            text = frame(self._seq, pairs)
            # The host can do what the mod cannot: replace the file atomically.
            temp = self.command_path.with_suffix(".tmp")
            last: OSError | None = None
            for attempt in range(4):
                try:
                    temp.write_text(text, encoding="utf-8")
                    os.replace(temp, self.command_path)
                    return self._seq
                except OSError as error:
                    # Windows sharing violations are transient; retries are
                    # bounded so a locked file cannot hang a request.
                    last = error
                    time.sleep(0.02 * (attempt + 1))
            raise last if last else OSError("command write failed")


# --------------------------------------------------------------- state model


def key_path() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "PZRadioLink" / "hostkey.txt"


KEY_CHARS = 32  # 128 bits of randomness, hex-encoded


def load_or_create_key(rotate: bool = False) -> tuple[str, str]:
    """The pairing key persists across host restarts.

    A key regenerated on every launch would make a home-screen shortcut useless:
    the saved URL carries the key, so the shortcut would break the next time the
    host started. The key lives in the user's local app data, readable only by
    this Windows account. Rotate it with --new-key.

    Keys shorter than KEY_CHARS are from a build whose web manifest published
    the key in `start_url`, so any device that could reach the host could read
    it without scanning the QR. Those are retired on sight rather than carried
    forward. Returns (key, reason) where reason is "kept", "rotated",
    "migrated" or "unsaved".
    """
    path = key_path()
    previous = None
    try:
        previous = path.read_text(encoding="utf-8").strip()
    except OSError:
        pass

    if not rotate and previous and len(previous) == KEY_CHARS \
            and all(c in "0123456789abcdef" for c in previous):
        return previous, "kept"

    reason = "rotated" if rotate else ("migrated" if previous else "kept")
    key = secrets.token_hex(KEY_CHARS // 2)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(".tmp")
        temp.write_text(key, encoding="utf-8")
        os.replace(temp, path)
    except OSError:
        # A key that cannot be saved still works for this session; say so rather
        # than implying pairing will survive a restart.
        return key, "unsaved"
    return key, reason


def default_lua_dir() -> Path:
    override = os.environ.get("PZRL_LUA_DIR")
    if override:
        return Path(override)
    return Path(os.path.expanduser("~")) / "Zomboid" / "Lua"


def build_view(fields: dict[str, str] | None, age: float) -> dict:
    """Shapes the mailbox fields into what the page renders. No invention: a
    field the mod did not send is absent, not defaulted to something plausible."""
    if fields is None:
        return {
            "connected": False,
            "status": "no_game",
            "stale": True,
            "radio": None,
            "results": [],
        }

    def num(key):
        try:
            return float(fields[key])
        except (KeyError, ValueError):
            return None

    def integer(key):
        value = num(key)
        return int(value) if value is not None else None

    # BF-08: a corrupt or unexpected document becomes an explicit invalid
    # state, never an exception or plausible zero-valued telemetry.
    if fields.get("proto") and fields["proto"] != str(PROTOCOL):
        return {
            "connected": False,
            "status": "protocol_mismatch",
            "stale": True,
            "radio": None,
            "results": [],
            "detail": f"mod speaks protocol {fields['proto']}, host speaks {PROTOCOL}",
        }

    radio = None
    if "ch" in fields:
        presets = []
        for chunk in (fields.get("presets") or "").split("|"):
            name, sep, freq = chunk.rpartition(":")
            if sep and freq.isdigit():
                presets.append({"name": name, "freq": int(freq)})
        # BF-10: the mod omits the range entirely when it could not be read,
        # rather than exporting 0..0 as if the band were authoritatively empty.
        lo, hi = integer("chmin"), integer("chmax")
        tunable = lo is not None and hi is not None and hi > lo
        radio = {
            "name": fields.get("name") or "Radio",
            # A placed radio stays linked when the player walks away, but cannot
            # be operated from a distance.
            "kind": fields.get("kind", "item"),
            "in_reach": fields.get("reach", "1") == "1",
            # battery | mains | unpowered | unknown. `battery` is a charge level
            # only in the first case; the others must not show a percentage.
            "power_source": fields.get("power_src", "unknown"),
            "on": fields.get("on") == "1",
            "channel": integer("ch"),
            "channel_min": lo,
            "channel_max": hi,
            "channel_step": integer("chstep") or 200,
            "tunable": tunable,
            "volume": num("vol"),
            "battery": num("batt"),
            "presets": presets,
            "preset_revision": integer("prev") or 0,
        }

    results = []
    for index in range(1, 9):
        raw = fields.get(f"r{index}")
        if not raw:
            continue
        parts = raw.split(":")
        if len(parts) >= 2:
            results.append(
                {"id": parts[0], "status": parts[1], "reason": ":".join(parts[2:])}
            )

    # The mod republishes at ~2 Hz; three missed cycles means the game thread is
    # gone, paused at the menu, or the mod is not loaded.
    stale = age > 3.0
    return {
        "connected": not stale,
        "status": fields.get("status", "unknown"),
        "paused": fields.get("paused") == "1",
        "epoch": fields.get("epoch", ""),
        "binding": fields.get("binding", ""),
        "revision": integer("rev") or 0,
        "watermark": integer("watermark"),
        "active": fields.get("active", ""),
        "stale": stale,
        "age": round(age, 2),
        "protocol": PROTOCOL,
        "radio": radio,
        "results": results,
    }


# ---------------------------------------------------------------------- http

ALLOWED_COMMANDS = {"set_power", "set_channel", "set_volume", "select_preset", "unlink"}

_ICON_SIZES = {
    "/icon-192.png": 192,
    "/icon-512.png": 512,
    "/apple-touch-icon.png": 180,
}
_icon_cache: dict[int, bytes] = {}


def icon_bytes(size: int) -> bytes:
    if size not in _icon_cache:
        _icon_cache[size] = pzrl_icon.render(size)
    return _icon_cache[size]


def detect_lan_ip() -> str | None:
    """The address of the interface that would carry outbound traffic.

    Connecting a UDP socket sends nothing; it just makes the OS pick a route,
    which is a far better answer than gethostbyname() on a machine with VPN or
    virtual adapters.
    """
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("192.0.2.1", 9))  # TEST-NET-1: routable, never answers
        address = probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()
    return None if address.startswith("127.") else address


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "PZRadioLink/0.3"
    mailbox: Mailbox
    broker: "pzrl_broker.Broker"
    token: str = ""
    allowed_hosts: set[str] = {"127.0.0.1", "localhost", "::1"}

    def log_message(self, fmt, *args):  # quieter than the default one-line-per-hit
        pass

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: dict) -> None:
        self._send(code, json.dumps(payload).encode("utf-8"), "application/json")

    # Even on loopback, a page on any other origin can POST here. Requiring a
    # same-origin Host and rejecting cross-site Origins keeps a random browser
    # tab from driving the radio.
    def _origin_ok(self) -> bool:
        """BF-08: validate Host against what this server actually serves, then
        Origin against that. Comparing Origin to a caller-supplied Host merely
        checks the caller is self-consistent, which any attacker trivially is.
        """
        host = self.headers.get("Host", "")
        hostname = host.rsplit(":", 1)[0].strip("[]") if host else ""
        if hostname and hostname not in self.allowed_hosts:
            return False
        origin = self.headers.get("Origin")
        if origin is None:
            return True  # not a browser cross-site request
        parsed = urlsplit(origin)
        if parsed.scheme not in ("http", "https"):
            return False
        origin_host = (parsed.hostname or "").strip("[]")
        return bool(origin_host) and origin_host in self.allowed_hosts

    # Once the host is reachable from the LAN, every other device on the network
    # can reach this port too. The token from the QR gates the control surface.
    # It is a bearer token over plaintext HTTP: it stops a neighbouring device
    # from driving the radio, and does nothing against someone reading the wire.
    def _authorized(self) -> bool:
        if not self.token:
            return True
        supplied = self.headers.get("X-PZRL-Token", "")
        # BF-08: compare_digest raises on non-ASCII, so a malformed header must
        # fail validation before it reaches the comparison, not inside it.
        if not isinstance(supplied, str) or len(supplied) != len(self.token):
            return False
        try:
            supplied.encode("ascii")
        except (UnicodeEncodeError, AttributeError):
            return False
        return secrets.compare_digest(supplied, self.token)

    # The pairing URL carries ?t=<token>, so the raw path is "/?t=..." and never
    # equals "/". Route on the path component only.
    def _route(self) -> str:
        return urlsplit(self.path).path or "/"

    def do_GET(self) -> None:
        route = self._route()
        if route in ("/", "/index.html"):
            try:
                body = (WEB_ROOT / "index.html").read_bytes()
            except OSError:
                self._send(500, b"index.html missing", "text/plain")
                return
            self._send(200, body, "text/html; charset=utf-8")
            return

        # Added to the home screen, the page runs without browser chrome. iOS
        # needs the apple-* meta tags in the document; Android needs this.
        if route == "/manifest.webmanifest":
            # The manifest is public, so it must never carry the pairing key.
            # An earlier build put it in start_url, which handed the credential
            # to any device that could reach the port. A home-screen launch
            # re-uses the key the page already stored, and offers re-pairing
            # when it has none.
            manifest = {
                "name": "PZ Radio Link",
                "short_name": "Radio",
                "start_url": "/",
                "scope": "/",
                "display": "standalone",
                "orientation": "portrait",
                "background_color": "#14161a",
                "theme_color": "#23262c",
                "icons": [
                    {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
                    {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"},
                ],
            }
            self._send(200, json.dumps(manifest).encode(),
                       "application/manifest+json")
            return

        if route in _ICON_SIZES:
            self._send(200, icon_bytes(_ICON_SIZES[route]), "image/png")
            return

        # Browsers request this unprompted; without it every page load logs a 404.
        if route == "/favicon.ico":
            self._send(200, icon_bytes(32), "image/png")
            return

        if route == "/api/state":
            if not self._authorized():
                self._json(401, {"error": "unauthorized"})
                return
            fields, age = self.mailbox.read_state()
            view = build_view(fields, age)
            # BF-02: outcomes are folded into receipts here rather than in the
            # browser, so a phone that slept through a result does not prevent
            # the host from learning the command finished.
            self.broker.apply_results(view.get("results", []), view.get("watermark"))
            self.broker.expire_stale()
            view["active_request"] = self.broker.active
            self._json(200, view)
            return

        # BF-02: a browser that lost its POST response recovers the outcome
        # here instead of resending and causing a second game action.
        if route == "/api/result":
            if not self._authorized():
                self._json(401, {"error": "unauthorized"})
                return
            wanted = parse_qs(urlsplit(self.path).query).get("request_id", [""])[0]
            if wanted:
                receipt = self.broker.receipt(wanted)
                if receipt is None:
                    # An expired record is NOT proof the command never ran.
                    self._json(404, {"error": "unknown_request",
                                     "note": "outside the retention window"})
                    return
                self._json(200, receipt)
                return
            self._json(200, {"receipts": self.broker.receipts(),
                             "active": self.broker.active})
            return

        self._send(404, b"not found", "text/plain")

    def do_POST(self) -> None:
        if self._route() != "/api/command":
            self._send(404, b"not found", "text/plain")
            return
        if not self._origin_ok():
            self._json(403, {"error": "bad_origin"})
            return
        if not self._authorized():
            self._json(401, {"error": "unauthorized"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._json(400, {"error": "bad_length"})
            return
        if length <= 0 or length > MAX_BODY_BYTES:
            self._json(400, {"error": "bad_length"})
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            self._json(400, {"error": "bad_json"})
            return
        if not isinstance(payload, dict):
            self._json(400, {"error": "bad_json"})
            return

        # BF-08: check the type BEFORE the set lookup. `[] in ALLOWED_COMMANDS`
        # on an unhashable value raises, turning a malformed body into a 500.
        command = payload.get("command")
        if not isinstance(command, str) or command not in ALLOWED_COMMANDS:
            self._json(400, {"error": "unknown_command"})
            return

        request_id = payload.get("request_id")
        if not isinstance(request_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,64}", request_id):
            self._json(400, {"error": "bad_request_id"})
            return

        fields, age = self.mailbox.read_state()
        if fields is None:
            self._json(409, {"error": "no_game"})
            return
        # BF-05: the POST path read the age and ignored it.
        if age > 3.0:
            self._json(409, {"error": "stale_state"})
            return
        if fields.get("proto") != str(PROTOCOL):
            self._json(409, {"error": "protocol_mismatch"})
            return
        if fields.get("status") != "linked":
            self._json(409, {"error": fields.get("status") or "not_linked"})
            return
        if fields.get("paused") == "1":
            self._json(409, {"error": "paused"})
            return

        # BF-04: the browser states which radio it was looking at. The host
        # compares rather than substituting whatever is current, so a request
        # composed against radio A can never be applied to radio B.
        expected = payload.get("expected")
        if not isinstance(expected, dict):
            self._json(400, {"error": "missing_expected"})
            return
        for key in ("epoch", "binding"):
            if not isinstance(expected.get(key), str):
                self._json(400, {"error": "missing_expected"})
                return
            if expected[key] != fields.get(key, ""):
                self._json(409, {"error": f"stale_{key}",
                                 "epoch": fields.get("epoch", ""),
                                 "binding": fields.get("binding", "")})
                return

        try:
            extra = self._command_fields(command, payload, fields)
        except ValueError as error:
            self._json(400, {"error": str(error)})
            return

        payload_key = json.dumps([command, extra], sort_keys=True)

        def envelope(deadline_ms: int) -> list[tuple[str, object]]:
            return [
                ("proto", PROTOCOL),
                ("id", request_id),
                ("epoch", expected["epoch"]),
                ("binding", expected["binding"]),
                ("deadline", deadline_ms),
                ("cmd", command),
            ] + extra

        try:
            receipt = self.broker.admit(request_id, payload_key, envelope)
        except pzrl_broker.Busy as busy:
            self._json(409, {"error": "busy", "active": busy.active_id})
            return
        except pzrl_broker.Conflict:
            self._json(409, {"error": "request_id_reused"})
            return

        self._json(202, {
            "request_id": receipt["request_id"],
            "status": receipt["status"],
            "reason": receipt.get("reason", ""),
            "sequence": receipt.get("sequence"),
        })

    @staticmethod
    def _command_fields(command: str, payload: dict,
                        state: dict[str, str]) -> list[tuple[str, object]]:
        """Per-command validation. Raises ValueError with a stable code."""

        def finite_number(value):
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError("bad_value")
            number = float(value)
            if number != number or number in (float("inf"), float("-inf")):
                raise ValueError("bad_value")
            return number

        def bounded_int(value):
            if isinstance(value, bool) or not isinstance(value, int):
                raise ValueError("bad_value")
            if abs(value) > MAX_SAFE_INT:
                raise ValueError("bad_value")
            return value

        value = payload.get("value")
        if command == "set_power":
            if not isinstance(value, bool):
                raise ValueError("bad_value")
            return [("value", "1" if value else "0")]

        if command == "set_channel":
            channel = bounded_int(value)
            return [("value", channel)]

        if command == "set_volume":
            volume = finite_number(value)
            if not (0.0 <= volume <= 1.0):
                raise ValueError("bad_value")
            return [("value", f"{volume:.3f}")]

        if command == "select_preset":
            index = bounded_int(payload.get("index"))
            if index < 1:
                raise ValueError("bad_value")
            # BF-04: name the list this click was made against, so a reordered
            # or edited preset list refuses instead of tuning slot N blindly.
            revision = bounded_int(payload.get("preset_revision", 0))
            frequency = bounded_int(payload.get("frequency", 0))
            return [("index", index), ("prev", revision), ("freq", frequency)]

        return []


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    parser = argparse.ArgumentParser(description="PZ Radio Link local host")
    parser.add_argument("--port", type=int, default=8777)
    parser.add_argument(
        "--lua-dir",
        type=Path,
        default=default_lua_dir(),
        help="Zomboid Lua directory (default: ~/Zomboid/Lua)",
    )
    parser.add_argument(
        "--localhost",
        action="store_true",
        help="bind 127.0.0.1 only; no phone access and no token",
    )
    parser.add_argument(
        "--qr-invert",
        action="store_true",
        help="invert the QR for terminals with a light background",
    )
    parser.add_argument(
        "--new-key",
        action="store_true",
        help="generate a fresh pairing key, invalidating paired devices",
    )
    args = parser.parse_args()

    if not args.lua_dir.parent.exists():
        print(f"[PZRL] Zomboid directory not found: {args.lua_dir.parent}")
        print("[PZRL] pass --lua-dir if your user data lives elsewhere")
        return 1

    # The block characters need a UTF-8 capable stdout; the Windows console
    # defaults to a legacy code page.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass

    lan_ip = None if args.localhost else detect_lan_ip()
    if args.localhost:
        bind, shown, Handler.token, key_reason = "127.0.0.1", "127.0.0.1", "", "none"
    elif lan_ip:
        bind, shown = "0.0.0.0", lan_ip
        Handler.token, key_reason = load_or_create_key(rotate=args.new_key)
    else:
        print("[PZRL] no LAN address found; falling back to loopback only")
        bind, shown, Handler.token, key_reason = "127.0.0.1", "127.0.0.1", "", "none"

    url = f"http://{shown}:{args.port}/"
    if Handler.token:
        url += f"?t={Handler.token}"

    try:
        Handler.mailbox = Mailbox(args.lua_dir)
    except MailboxBusy:
        print(f"[PZRL] another host already owns {args.lua_dir / 'PZRL'}")
        print("[PZRL] close the other window; two hosts must not share a mailbox")
        return 1
    Handler.broker = pzrl_broker.Broker(
        Handler.mailbox, key_path().parent / "active-command.json")
    # BF-08: Host headers are checked against what this server actually serves.
    Handler.allowed_hosts = {"127.0.0.1", "localhost", "::1"}
    if shown not in ("127.0.0.1",):
        Handler.allowed_hosts.add(shown)

    try:
        server = Server((bind, args.port), Handler)
    except OSError as error:
        print(f"[PZRL] cannot bind {bind}:{args.port} - {error}")
        print("[PZRL] another host may already be running, or the port is taken")
        return 1

    print()
    if Handler.token:
        try:
            print(pzrl_qr.render(pzrl_qr.encode(url), invert=args.qr_invert))
        except (ValueError, UnicodeEncodeError) as error:
            print(f"[PZRL] could not draw the QR code ({error}); use the URL below")
        print()
        print("  Scan with your phone's camera, on the same Wi-Fi.")
        print("  Then use your browser's Add to Home Screen for a full-screen app.")
    print(f"  {url}")
    print()
    print(f"[PZRL] mailbox  {Handler.mailbox.dir}")
    if Handler.token:
        if key_reason == "migrated":
            print("[PZRL] your previous pairing key was retired: an earlier build")
            print("[PZRL] published it in the web manifest. Re-scan the QR above.")
        elif key_reason == "rotated":
            print("[PZRL] new pairing key generated; previously paired devices must re-scan")
        elif key_reason == "unsaved":
            print(f"[PZRL] WARNING could not write {key_path()}")
            print("[PZRL] this key works now but will NOT survive a restart")
        print(f"[PZRL] pairing key kept in {key_path()} - reset it with --new-key")
        print("[PZRL] Windows may ask to allow this app through the firewall - say yes")
        print("[PZRL] plain HTTP on your LAN: not encrypted, so use a network you trust")
    print("[PZRL] Ctrl+C to stop")
    # A console is line-buffered, but a redirected or piped stdout is not, and
    # the whole banner would then sit unseen in a buffer until shutdown.
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[PZRL] stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
