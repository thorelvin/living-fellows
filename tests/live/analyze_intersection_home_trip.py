# SPDX-License-Identifier: MIT
"""Audit a completed public Home car journey, separately from post-trip duty."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-fallback", action="store_true",
                        help="add the historical bumper-fallback exercise requirement")
    args = parser.parse_args()
    manifest = json.loads((args.run / "run-manifest.json").read_text(encoding="utf-8-sig"))
    base = args.run / "cache/Lua/LivingFellowsHarness"
    require((base / "summary.txt").is_file(), "wait for the full Home probe to finish; do not interrupt it")
    events = (base / "events.log").read_text(encoding="utf-8-sig").splitlines()
    bridge = hashlib.sha256(args.bridge.read_bytes()).hexdigest()
    require(manifest["sourceBridgeSha256"].lower() == bridge, "native launch must use the specified bridge")
    require(manifest["homeTripProbe"] and manifest["homeTripTransport"] == "drive", "actual Home car probe required")
    marker = next((i for i, line in enumerate(events) if line.startswith("PASS|home_trip_png_revisited-solo|")), None)
    require(marker is not None, "journey, dormant arrival and solo revisit never completed")
    travel, post = events[:marker + 1], events[marker + 1:]
    require(not any(line.startswith("FAIL|") for line in travel), "a travel or save/restore assertion failed")
    passed = {line.split("|", 2)[1]: line.split("|", 2)[2] for line in travel if line.startswith("PASS|")}
    for name in ("home_trip_public_start", "home_trip_physical_home_drive", "home_trip_native_solo_release",
                 "home_drive_restored_real_car_cargo", "home_trip_primary_identity_after_revisit"):
        require(name in passed, "missing native journey proof: " + name)
    physical = passed["home_trip_physical_home_drive"]
    distance = re.search(r"driven meters=([\d.]+)", physical)
    require(distance and float(distance[1]) >= 100 and "continuity failed=false" in physical
            and "real native crew seats=true" in physical, "continuous physical driving and crew seats required")
    count = manifest["homeTripMembers"]
    for prefix in ("home_trip_dormant_identity_", "home_trip_durable_native_items_",
                   "home_trip_restored_name_", "home_trip_single_restored_native_"):
        require(sum(key.startswith(prefix) for key in passed) == count, "all real crew need proof: " + prefix)
    native = passed["home_trip_native_solo_release"]
    require("numPlayers=1" in native and "slot1=null" in native, "secondary native view must actually release")
    full_failures = [line for line in events if line.startswith("FAIL|")]
    post_failures = [line for line in post if line.startswith("FAIL|")]
    require(all(line.startswith("FAIL|home_trip_drive_delivery_deadline|") for line in post_failures),
            "unexpected post-trip failure; this audit only separates the known duty deadline")
    log = (base / "home-trip.log").read_text(encoding="utf-8-sig")
    fallbacks = [int(value) for value in re.findall(r"cornerFallbacks=(\d+)", log)]
    require(fallbacks, "native corner diagnostics are required")
    if args.require_fallback:
        require(max(fallbacks) >= 1, "native journey must exercise the bumper-corner fallback")
    result = dict(scope="public Home travel, dormant arrival and native save/restore; post-trip duty excluded",
                  run=args.run.name, bridge_sha256=bridge, members=count, driven_metres=float(distance[1]),
                  corner_fallbacks=max(fallbacks), armed=manifest.get("homeTripArmed", False),
                  camp_margin=manifest.get("homeTripCampMargin", 0),
                  full_home_probe_pass=not full_failures, post_trip_failures=post_failures)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"INTERSECTION_HOME_TRAVEL_PASS metres={distance[1]} members={count} "
          f"fallbacks={max(fallbacks)} full_home_probe_pass={not full_failures}")


if __name__ == "__main__":
    main()
