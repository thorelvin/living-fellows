"""End-to-end test of the host against a real mailbox directory on disk.

Runs the actual HTTP server over a temporary Zomboid/Lua directory and plays the
part of the mod: writes framed state documents into the A/B slots, then checks
what the page would see and what the mod would receive.

    python tests/test_host.py
"""

from __future__ import annotations

import json
import sys
import os
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "host"))

import pzrl_host as H  # noqa: E402
import pzrl_broker as broker_mod  # noqa: E402

FAILURES: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {name}")
    else:
        FAILURES.append(name)
        print(f"  FAIL {name} {detail}")


def state_pairs(**over) -> list[tuple[str, object]]:
    base = {
        "proto": str(H.PROTOCOL), "epoch": "g999", "binding": "b1", "rev": 4,
        "status": "linked", "paused": "0", "watermark": "0", "active": "",
        "name": "HamRadio", "on": "1",
        "ch": 93400, "chmin": 88000, "chmax": 108000, "chstep": 200,
        "vol": "0.350", "batt": "0.720", "power_src": "battery",
        "prev": "12345", "presets": "WKTV:88500|Noise Maker:91200",
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


_request_counter = [0]


def post(url: str, payload: dict, token: str | None = TOKEN, *,
         request_id: str | None = None, expected: dict | None = None,
         raw: bool = False):
    """Fills in the v2 envelope unless a test is exercising its absence."""
    if not raw:
        payload = dict(payload)
        if request_id is None:
            _request_counter[0] += 1
            request_id = f"req{_request_counter[0]:016d}"
        payload.setdefault("request_id", request_id)
        payload.setdefault("expected", expected if expected is not None
                           else {"epoch": "g999", "binding": "b1"})
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

    H.Handler.mailbox = H.Mailbox(root, take_lock=False)
    H.Handler.broker = broker_mod.Broker(H.Handler.mailbox, root / "active.json")
    H.Handler.token = TOKEN
    H.Handler.allowed_hosts = {"127.0.0.1", "localhost", "::1"}
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

    print("historical files are not a running game (BF-05)")
    mod.publish()
    code, view = get(f"{base}/api/state")
    check("one unmoving document is not 'connected'", view["connected"] is False,
          "a file on disk must not imply a live game")
    code, body = post(f"{base}/api/command", {"command": "set_power", "value": True})
    check("command refused on unproven state", code == 409, str(body))

    print("linked radio")
    mod.publish()  # an advancing heartbeat proves the game is actually running
    code, view = get(f"{base}/api/state")
    check("connected once the heartbeat advances", view["connected"] is True)
    check("channel", view["radio"]["channel"] == 93400)
    check("volume", abs(view["radio"]["volume"] - 0.35) < 1e-6)
    check("power flag", view["radio"]["on"] is True)
    check("presets parsed", len(view["radio"]["presets"]) == 2)
    check("preset name", view["radio"]["presets"][1]["name"] == "Noise Maker")
    check("step exposed", view["radio"]["channel_step"] == 200)

    print("command round trip")
    code, body = post(f"{base}/api/command", {"command": "set_channel", "value": 93600},
                      request_id="roundtrip0000001")
    check("accepted as async", code == 202, str(body))
    fields = mod.read_command()
    check("mod sees command", fields is not None)
    check("carries value", fields and fields["value"] == "93600")
    check("carries epoch", fields and fields["epoch"] == "g999")
    check("carries binding", fields and fields["binding"] == "b1")
    check("carries protocol", fields and fields["proto"] == str(H.PROTOCOL))
    check("carries acceptance deadline", fields and int(fields["deadline"]) > 0)
    check("uses the client request id", fields and fields["id"] == "roundtrip0000001")
    # Free the slot so later sections are not blocked by this one.
    mod.publish(r1="roundtrip0000001:applied:")
    get(f"{base}/api/state")

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
    mod.publish(kind="world", reach="0", power_src="mains", name="HAM radio")
    code, view = get(f"{base}/api/state")
    radio = view["radio"]
    check("kind reported", radio["kind"] == "world")
    check("out of reach reported", radio["in_reach"] is False)
    check("mains power reported", radio["power_source"] == "mains")
    check("still linked while out of reach", view["status"] == "linked")
    mod.publish(kind="world", reach="1", power_src="mains")
    code, view = get(f"{base}/api/state")
    check("back in reach", view["radio"]["in_reach"] is True)

    print("power model (BF-10)")
    for source in ("battery", "mains", "unpowered", "unknown"):
        mod.publish(power_src=source)
        code, view = get(f"{base}/api/state")
        check(f"{source} reported verbatim", view["radio"]["power_source"] == source)
    # An unreadable channel range must not be exported as an authoritative band.
    pairs = [(k, v) for k, v in state_pairs() if k not in ("chmin", "chmax", "chstep")]
    mod.seq += 1
    (mod.dir / "state_a.txt").write_text(H.frame(mod.seq, pairs), encoding="utf-8")
    code, view = get(f"{base}/api/state")
    check("missing range is not 0..0", view["radio"]["channel_min"] is None)
    check("missing range marks untunable", view["radio"]["tunable"] is False)
    mod.publish()
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
    # BF-01: an earlier build put the pairing key in start_url, handing the
    # credential to any device that could reach the port. The manifest is
    # public, so it must be byte-identical for everyone and carry no key.
    check("start_url carries no key", manifest["start_url"] == "/",
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

    print("single-flight command broker (BF-02)")
    mod.publish()
    # A burst must produce exactly one outstanding command and explicit
    # refusals for the rest -- never silent overwriting of cmd.txt.
    codes = [post(f"{base}/api/command",
                  {"command": "set_channel", "value": 93600 + i * 200})[0]
             for i in range(20)]
    check("exactly one of 20 accepted", codes.count(202) == 1, str(codes.count(202)))
    check("the rest are explicitly busy", codes.count(409) == 19, str(codes.count(409)))
    active = H.Handler.broker.active
    check("broker holds one active command", active is not None)

    # Free the burst's slot first, or the idempotency checks below would all
    # hit "busy" and pass for the wrong reason.
    mod.publish(r1=f"{active}:applied:")
    get(f"{base}/api/state")
    check("slot freed before idempotency checks", H.Handler.broker.active is None)

    # The same request id must not produce a second game action.
    first = post(f"{base}/api/command", {"command": "set_power", "value": False},
                 request_id="idem000000000001")
    check("first submission accepted", first[0] == 202, str(first))
    seq_before = H.Handler.mailbox._seq   # count only what the REPLAY emits
    replay = post(f"{base}/api/command", {"command": "set_power", "value": False},
                  request_id="idem000000000001")
    check("replayed id returns the same receipt", first[1] == replay[1], str(replay))
    check("replay emits no second command",
          H.Handler.mailbox._seq == seq_before, "sequence advanced twice")

    conflict = post(f"{base}/api/command", {"command": "set_power", "value": True},
                    request_id="idem000000000001")
    check("same id, different payload is refused", conflict[0] == 409
          and conflict[1].get("error") == "request_id_reused", str(conflict))

    # Resolving the outcome frees the slot.
    mod.publish(r1="idem000000000001:applied:")
    get(f"{base}/api/state")
    check("terminal outcome frees the slot", H.Handler.broker.active is None)

    print("outcome recovery (BF-02)")
    accepted = post(f"{base}/api/command", {"command": "set_volume", "value": 0.4},
                    request_id="recover000000001")
    check("accepted for recovery test", accepted[0] == 202, str(accepted))
    with urllib.request.urlopen(urllib.request.Request(
            f"{base}/api/result?request_id=recover000000001",
            headers={"X-PZRL-Token": TOKEN}), timeout=5) as response:
        receipt = json.loads(response.read())
    check("receipt is retrievable by id", receipt["request_id"] == "recover000000001")
    code, _ = get(f"{base}/api/result?request_id=nope000000000000")
    check("unknown receipt is 404, not a lie", code == 404)
    mod.publish(r1="recover000000001:applied:")
    get(f"{base}/api/state")

    print("target identity (BF-04)")
    mod.publish()
    stale = post(f"{base}/api/command", {"command": "set_power", "value": True},
                 expected={"epoch": "g999", "binding": "OLD-BINDING"})
    check("stale binding refused", stale[0] == 409
          and stale[1].get("error") == "stale_binding", str(stale))
    stale_epoch = post(f"{base}/api/command", {"command": "set_power", "value": True},
                       expected={"epoch": "ANCIENT", "binding": "b1"})
    check("stale epoch refused", stale_epoch[0] == 409
          and stale_epoch[1].get("error") == "stale_epoch", str(stale_epoch))
    missing = post(f"{base}/api/command", {"command": "set_power", "value": True},
                   raw=True)
    check("missing expected block refused", missing[0] == 400, str(missing))
    preset = post(f"{base}/api/command",
                  {"command": "select_preset", "index": 1,
                   "frequency": 88500, "preset_revision": 12345})
    check("preset carries list identity", preset[0] == 202, str(preset))
    fields = mod.read_command()
    check("preset revision reaches the mod", fields and fields["prev"] == "12345")
    check("preset frequency reaches the mod", fields and fields["freq"] == "88500")
    mod.publish(r1=f"{H.Handler.broker.active}:applied:")
    get(f"{base}/api/state")

    print("hostile input (BF-08)")
    for name, body in [
        ("array as command", {"command": [], "value": 1}),
        ("object as command", {"command": {}, "value": 1}),
        ("null command", {"command": None}),
        ("huge integer", {"command": "set_channel", "value": 10 ** 30}),
        ("missing request id", {"command": "set_power", "value": True}),
    ]:
        if name == "missing request id":
            code, _ = post(f"{base}/api/command", body, raw=True)
            # raw omits request_id entirely
            check(f"rejects {name}", code == 400, str(code))
            continue
        code, _ = post(f"{base}/api/command", body)
        check(f"rejects {name}", code == 400, str(code))
    # A NaN literal is not valid JSON, but Python emits it; the server must not
    # turn it into a command.
    request = urllib.request.Request(
        f"{base}/api/command",
        data=b'{"request_id":"nanx000000000001","expected":{"epoch":"g999",'
             b'"binding":"b1"},"command":"set_volume","value":NaN}',
        headers={"Content-Type": "application/json", "X-PZRL-Token": TOKEN},
        method="POST")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            check("NaN volume refused", response.status == 400, str(response.status))
    except urllib.error.HTTPError as error:
        check("NaN volume refused", error.code == 400, str(error.code))

    print("protocol version (BF-08)")
    mismatched = [(k, "1" if k == "proto" else v) for k, v in state_pairs()]
    mod.seq += 1
    (mod.dir / "state_a.txt").write_text(H.frame(mod.seq, mismatched), encoding="utf-8")
    code, view = get(f"{base}/api/state")
    check("mod on the wrong protocol is explicit", view["status"] == "protocol_mismatch")
    check("and not connected", view["connected"] is False)
    mod.publish()
    get(f"{base}/api/state")

    print("credential disclosure (BF-01)")
    # Sweep every route an unauthenticated device can reach, including error
    # responses and headers, and assert the key appears in none of them.
    public_routes = ["/", "/index.html", "/manifest.webmanifest", "/icon-192.png",
                     "/icon-512.png", "/apple-touch-icon.png", "/favicon.ico",
                     "/api/state", "/api/command", "/nope", "/../hostkey.txt"]
    leaked = []
    for route in public_routes:
        try:
            request = urllib.request.Request(base + route)
            with urllib.request.urlopen(request, timeout=5) as response:
                body, headers = response.read(), str(response.headers)
        except urllib.error.HTTPError as error:
            body, headers = error.read(), str(error.headers)
        except urllib.error.URLError:
            continue
        blob = body + headers.encode()
        if TOKEN.encode() in blob:
            leaked.append(route)
    check("no public route discloses the key", not leaked, f"leaked via {leaked}")

    # Anonymous requests to the manifest must be identical to paired ones:
    # a manifest that varied by caller could still leak through a paired device.
    with urllib.request.urlopen(f"{base}/manifest.webmanifest", timeout=5) as r1:
        anon = r1.read()
    paired_req = urllib.request.Request(f"{base}/manifest.webmanifest",
                                        headers={"X-PZRL-Token": TOKEN})
    with urllib.request.urlopen(paired_req, timeout=5) as r2:
        paired = r2.read()
    check("manifest identical for all callers", anon == paired)

    print("key strength and migration (BF-01)")
    check("new keys are 128-bit", H.KEY_CHARS == 32)
    import tempfile as _tf
    with _tf.TemporaryDirectory() as tmp:
        keyfile = Path(tmp) / "PZRadioLink" / "hostkey.txt"
        keyfile.parent.mkdir(parents=True)
        original = os.environ.get("LOCALAPPDATA")
        os.environ["LOCALAPPDATA"] = tmp
        try:
            keyfile.write_text("0123456789abcdef", encoding="utf-8")  # old 64-bit
            migrated, reason = H.load_or_create_key()
            check("short legacy key is retired", reason == "migrated"
                  and migrated != "0123456789abcdef")
            check("migrated key is the new length", len(migrated) == H.KEY_CHARS)
            again, reason2 = H.load_or_create_key()
            check("a good key is kept", again == migrated and reason2 == "kept")
            rotated, reason3 = H.load_or_create_key(rotate=True)
            check("--new-key rotates", rotated != migrated and reason3 == "rotated")
        finally:
            if original is None:
                del os.environ["LOCALAPPDATA"]
            else:
                os.environ["LOCALAPPDATA"] = original

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
