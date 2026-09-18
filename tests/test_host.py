"""End-to-end test of the host against a real mailbox directory on disk.

Runs the actual HTTP server over a temporary Zomboid/Lua directory and plays the
part of the mod: writes framed state documents into the A/B slots, then checks
what the page would see and what the mod would receive.

    python tests/test_host.py
"""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "host"))

import pzrl_host as H  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        FAILURES.append(name)
        print(f"  FAIL {name} {detail}")


def state_pairs(**over) -> list[tuple[str, object]]:
    base = {
        "proto": "1", "epoch": "g999", "binding": "b1", "rev": 4,
        "status": "linked", "paused": "0", "name": "HamRadio", "on": "1",
        "ch": 93400, "chmin": 88000, "chmax": 108000, "chstep": 200,
        "vol": "0.350", "batt": "0.720", "battery": "1",
        "presets": "WKTV:88500|Noise Maker:91200",
    }
    base.update(over)
    return list(base.items())


class FakeMod:
    """Writes state the way PZRL_Mailbox does: alternating slots, never
    truncating the slot that currently holds the newest good document."""

    def __init__(self, root: Path) -> None:
        self.dir = root / "PZRL"
        self.dir.mkdir(parents=True, exist_ok=True)
        self.slot = 0
        self.seq = 0

    def publish(self, **over) -> None:
        self.seq += 1
        path = self.dir / ("state_a.txt" if self.slot == 0 else "state_b.txt")
        path.write_text(H.frame(self.seq, state_pairs(**over)), encoding="utf-8")
        self.slot ^= 1

    def tear(self) -> None:
        """Simulate a torn write: the slot about to be written is truncated
        mid-document, exactly as getFileWriter(name, true, false) leaves it."""
        path = self.dir / ("state_a.txt" if self.slot == 0 else "state_b.txt")
        full = H.frame(self.seq + 99, state_pairs(ch=99999))
        path.write_text(full[: len(full) // 2], encoding="utf-8")

    def read_command(self) -> dict[str, str] | None:
        try:
            text = (self.dir / "cmd.txt").read_text(encoding="utf-8")
        except OSError:
            return None
        parsed = H.parse(text)
        return parsed[0] if parsed else None


TOKEN = "0123456789abcdef"


def get(url: str, token: str | None = TOKEN):
    headers = {"X-PZRL-Token": token} if token is not None else {}
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def post(url: str, payload: dict, token: str | None = TOKEN):
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["X-PZRL-Token"] = token
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="pzrl-test-"))
    mod = FakeMod(root)

    H.Handler.mailbox = H.Mailbox(root)
    H.Handler.token = TOKEN
    server = H.Server(("127.0.0.1", 0), H.Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    print("no game yet")
    code, view = get(f"{base}/api/state")
    check("state served", code == 200)
    check("reports no game", view["status"] == "no_game" and not view["connected"])
    code, body = post(f"{base}/api/command", {"command": "set_power", "value": True})
    check("command refused with no game", code == 409, str(body))

    print("linked radio")
    mod.publish()
    code, view = get(f"{base}/api/state")
    check("connected", view["connected"] is True)
    check("channel", view["radio"]["channel"] == 93400)
    check("volume", abs(view["radio"]["volume"] - 0.35) < 1e-6)
    check("power flag", view["radio"]["on"] is True)
    check("presets parsed", len(view["radio"]["presets"]) == 2)
    check("preset name", view["radio"]["presets"][1]["name"] == "Noise Maker")
    check("step exposed", view["radio"]["channel_step"] == 200)

    print("command round trip")
    code, body = post(f"{base}/api/command", {"command": "set_channel", "value": 93600})
    check("accepted", code == 200, str(body))
    fields = mod.read_command()
    check("mod sees command", fields is not None)
    check("carries value", fields and fields["value"] == "93600")
    check("carries epoch", fields and fields["epoch"] == "g999")
    check("carries binding", fields and fields["binding"] == "b1")
    check("has command id", fields and fields["id"] == body["command_id"])

    print("torn write")
    before = get(f"{base}/api/state")[1]["radio"]["channel"]
    mod.tear()
    code, view = get(f"{base}/api/state")
    check("keeps last good channel", view["radio"]["channel"] == before,
          f"got {view['radio']['channel']}")
    check("does not adopt torn value", view["radio"]["channel"] != 99999)

    print("recovery after a torn slot")
    mod.publish(ch=94000)
    code, view = get(f"{base}/api/state")
    check("new value adopted", view["radio"]["channel"] == 94000)

    print("input validation")
    for name, payload in [
        ("unknown command", {"command": "delete_save"}),
        ("channel as string", {"command": "set_channel", "value": "93600"}),
        ("channel as bool", {"command": "set_channel", "value": True}),
        ("channel as float", {"command": "set_channel", "value": 93600.5}),
        ("volume above range", {"command": "set_volume", "value": 1.4}),
        ("volume as bool", {"command": "set_volume", "value": True}),
        ("power as int", {"command": "set_power", "value": 1}),
        ("preset index zero", {"command": "select_preset", "index": 0}),
        ("preset index missing", {"command": "select_preset"}),
    ]:
        code, body = post(f"{base}/api/command", payload)
        check(f"rejects {name}", code == 400, f"got {code} {body}")

    print("staleness")
    stale_age = H.build_view(H.parse(H.frame(1, state_pairs()))[0], 9.0)
    check("stale marks disconnected", stale_age["connected"] is False)
    check("stale keeps last radio values", stale_age["radio"]["channel"] == 93400)

    print("results surface")
    mod.publish(r1="abc123:rejected:device_off")
    code, view = get(f"{base}/api/state")
    check("result parsed", view["results"][0]["status"] == "rejected")
    check("reason parsed", view["results"][0]["reason"] == "device_off")

    print("placed (world) radios")
    mod.publish(kind="world", reach="0", mains="1", battery="0", batt="0.000",
                name="HAM radio")
    code, view = get(f"{base}/api/state")
    radio = view["radio"]
    check("kind reported", radio["kind"] == "world")
    check("out of reach reported", radio["in_reach"] is False)
    check("mains power reported", radio["mains"] is True)
    check("still linked while out of reach", view["status"] == "linked")
    mod.publish(kind="world", reach="1", mains="1", battery="0", batt="0.000")
    code, view = get(f"{base}/api/state")
    check("back in reach", view["radio"]["in_reach"] is True)
    # A mod that never sends the field (carried radio) must not read as unreachable.
    mod.publish()
    code, view = get(f"{base}/api/state")
    check("carried radio defaults to item", view["radio"]["kind"] == "item")
    check("carried radio defaults in reach", view["radio"]["in_reach"] is True)

    print("pairing token")
    code, body = get(f"{base}/api/state", token=None)
    check("state needs the token", code == 401, str(code))
    code, body = get(f"{base}/api/state", token="wrong-token-entirely")
    check("wrong token refused", code == 401, str(code))
    code, body = post(f"{base}/api/command",
                      {"command": "set_power", "value": False}, token=None)
    check("command needs the token", code == 401, str(code))
    code, body = post(f"{base}/api/command",
                      {"command": "set_power", "value": False}, token=TOKEN[:-1] + "0")
    check("near-miss token refused", code == 401, str(code))
    with urllib.request.urlopen(f"{base}/", timeout=5) as response:
        check("page itself needs no token", response.status == 200)

    # The QR encodes "/?t=<token>", so the raw request path is never bare "/".
    # Routing on the unparsed path made every scan 404.
    for suffix in (f"/?t={TOKEN}", "/?t=anything&x=1", "/index.html?t=x"):
        try:
            with urllib.request.urlopen(base + suffix, timeout=5) as response:
                body = response.read()
            check(f"pairing URL {suffix} serves the page",
                  response.status == 200 and b"<html" in body.lower())
        except urllib.error.HTTPError as error:
            check(f"pairing URL {suffix} serves the page", False, f"HTTP {error.code}")
    code, _ = get(f"{base}/api/state?cachebust=1")
    check("api path tolerates a query string", code == 200, str(code))

    print("home-screen install assets")
    with urllib.request.urlopen(f"{base}/manifest.webmanifest", timeout=5) as response:
        manifest = json.loads(response.read())
    check("manifest served", manifest["name"] == "PZ Radio Link")
    check("manifest is standalone", manifest["display"] == "standalone")
    check("start_url carries the key", manifest["start_url"] == f"/?t={TOKEN}",
          manifest["start_url"])
    for path, expected in (("/icon-192.png", 192), ("/icon-512.png", 512),
                           ("/apple-touch-icon.png", 180)):
        with urllib.request.urlopen(base + path, timeout=5) as response:
            blob = response.read()
        import struct as _struct
        width, height = _struct.unpack(">II", blob[16:24])
        check(f"{path} is a {expected}px PNG",
              blob[:8] == b"\x89PNG\r\n\x1a\n" and width == height == expected,
              f"{width}x{height}")

    print("origin check")
    request = urllib.request.Request(
        f"{base}/api/command",
        data=json.dumps({"command": "set_power", "value": False}).encode(),
        headers={"Content-Type": "application/json", "Origin": "http://evil.example",
                 "X-PZRL-Token": TOKEN},
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=5)
        check("cross-origin refused", False, "request succeeded")
    except urllib.error.HTTPError as error:
        check("cross-origin refused", error.code == 403, str(error.code))

    server.shutdown()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED: {', '.join(FAILURES)}")
        return 1
    print("ALL HOST CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
