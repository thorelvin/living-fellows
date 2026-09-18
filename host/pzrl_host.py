"""
PZ Radio Link -- local host.

Standard library only. There is nothing to pip install and no virtualenv to
create: `python pzrl_host.py` is the whole thing.

The mod cannot open a socket -- Kahlua has no socket library -- so this process
is the web server, and it talks to the mod through small framed files under
<userdir>/Zomboid/Lua/PZRL. The game stays authoritative for every radio state;
nothing here simulates power, battery, channel or reception.

MVP scope: binds to 127.0.0.1 only. No pairing, no credentials, no LAN exposure.
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import secrets
import socket
import socketserver
import sys
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit

import pzrl_icon
import pzrl_qr

PROTOCOL = 1
MAGIC = "PZRL1"
FOOTER = "PZRLEND"
MAX_PAYLOAD_BYTES = 16384

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
    lines = text.split("\n")
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


class Mailbox:
    """Reads the mod's A/B state slots; writes the single command document."""

    def __init__(self, lua_dir: Path) -> None:
        self.dir = lua_dir / "PZRL"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.command_path = self.dir / "cmd.txt"
        self.state_paths = [self.dir / "state_a.txt", self.dir / "state_b.txt"]
        self._seq = int(time.time())
        self._lock = threading.Lock()
        self._last_good: dict[str, str] | None = None
        self._last_good_seq = -1
        self._last_change = 0.0

    def read_state(self) -> tuple[dict[str, str] | None, float]:
        """Highest validating slot wins. A torn slot is ignored, never fatal."""
        best: tuple[dict[str, str], int] | None = None
        for path in self.state_paths:
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            parsed = parse(text)
            if parsed is None:
                continue
            if best is None or parsed[1] > best[1]:
                best = parsed
        if best is not None and best[1] != self._last_good_seq:
            self._last_good, self._last_good_seq = best[0], best[1]
            self._last_change = time.monotonic()
        age = time.monotonic() - self._last_change if self._last_good else 999.0
        return self._last_good, age

    def send_command(self, pairs: list[tuple[str, object]]) -> int:
        with self._lock:
            self._seq += 1
            text = frame(self._seq, pairs)
            # The host can do what the mod cannot: replace the file atomically.
            temp = self.command_path.with_suffix(".tmp")
            temp.write_text(text, encoding="utf-8")
            os.replace(temp, self.command_path)
            return self._seq


# --------------------------------------------------------------- state model


def key_path() -> Path:
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    return Path(base) / "PZRadioLink" / "hostkey.txt"


def load_or_create_key(rotate: bool = False) -> str:
    """The pairing key persists across host restarts.

    A key regenerated on every launch would make a home-screen shortcut useless:
    the saved URL carries the key, so the shortcut would break the next time the
    host started. The key lives in the user's local app data, readable only by
    this Windows account. Rotate it with --new-key.
    """
    path = key_path()
    if not rotate:
        try:
            existing = path.read_text(encoding="utf-8").strip()
            if len(existing) == 16 and all(c in "0123456789abcdef" for c in existing):
                return existing
        except OSError:
            pass
    key = secrets.token_hex(8)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(key, encoding="utf-8")
    except OSError:
        pass  # a key that cannot be saved still works for this session
    return key


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

    radio = None
    if "ch" in fields:
        presets = []
        for chunk in (fields.get("presets") or "").split("|"):
            name, sep, freq = chunk.rpartition(":")
            if sep and freq.isdigit():
                presets.append({"name": name, "freq": int(freq)})
        radio = {
            "name": fields.get("name") or "Radio",
            # A placed radio stays linked when the player walks away, but cannot
            # be operated from a distance.
            "kind": fields.get("kind", "item"),
            "in_reach": fields.get("reach", "1") == "1",
            "mains": fields.get("mains") == "1",
            "on": fields.get("on") == "1",
            "channel": integer("ch"),
            "channel_min": integer("chmin"),
            "channel_max": integer("chmax"),
            "channel_step": integer("chstep") or 200,
            "volume": num("vol"),
            "battery": num("batt"),
            "battery_powered": fields.get("battery") == "1",
            "presets": presets,
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
        "stale": stale,
        "age": round(age, 2),
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
    server_version = "PZRadioLink/0.1"
    mailbox: Mailbox
    token: str = ""

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
        origin = self.headers.get("Origin")
        if origin is None:
            return True
        host = self.headers.get("Host", "")
        return origin in (f"http://{host}", f"https://{host}")

    # Once the host is reachable from the LAN, every other device on the network
    # can reach this port too. The token from the QR gates the control surface.
    # It is a bearer token over plaintext HTTP: it stops a neighbouring device
    # from driving the radio, and does nothing against someone reading the wire.
    def _authorized(self) -> bool:
        if not self.token:
            return True
        supplied = self.headers.get("X-PZRL-Token", "")
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
            manifest = {
                "name": "PZ Radio Link",
                "short_name": "Radio",
                "start_url": f"/?t={self.token}" if self.token else "/",
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
            self._json(200, build_view(fields, age))
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
        if length <= 0 or length > 4096:
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

        command = payload.get("command")
        if command not in ALLOWED_COMMANDS:
            self._json(400, {"error": "unknown_command"})
            return

        fields, _age = self.mailbox.read_state()
        if fields is None:
            self._json(409, {"error": "no_game"})
            return

        command_id = uuid.uuid4().hex[:12]
        pairs: list[tuple[str, object]] = [
            ("proto", PROTOCOL),
            ("id", command_id),
            ("epoch", fields.get("epoch", "")),
            ("binding", fields.get("binding", "")),
            ("cmd", command),
        ]

        value = payload.get("value")
        if command == "set_power":
            if not isinstance(value, bool):
                self._json(400, {"error": "bad_value"})
                return
            pairs.append(("value", "1" if value else "0"))
        elif command == "set_channel":
            if not isinstance(value, int) or isinstance(value, bool):
                self._json(400, {"error": "bad_value"})
                return
            pairs.append(("value", value))
        elif command == "set_volume":
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                self._json(400, {"error": "bad_value"})
                return
            if not (0.0 <= float(value) <= 1.0):
                self._json(400, {"error": "bad_value"})
                return
            pairs.append(("value", f"{float(value):.3f}"))
        elif command == "select_preset":
            index = payload.get("index")
            if not isinstance(index, int) or isinstance(index, bool) or index < 1:
                self._json(400, {"error": "bad_value"})
                return
            pairs.append(("index", index))

        seq = self.mailbox.send_command(pairs)
        self._json(200, {"command_id": command_id, "sequence": seq})


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
        bind, shown, Handler.token = "127.0.0.1", "127.0.0.1", ""
    elif lan_ip:
        bind, shown = "0.0.0.0", lan_ip
        Handler.token = load_or_create_key(rotate=args.new_key)
    else:
        print("[PZRL] no LAN address found; falling back to loopback only")
        bind, shown, Handler.token = "127.0.0.1", "127.0.0.1", ""

    url = f"http://{shown}:{args.port}/"
    if Handler.token:
        url += f"?t={Handler.token}"

    Handler.mailbox = Mailbox(args.lua_dir)
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
