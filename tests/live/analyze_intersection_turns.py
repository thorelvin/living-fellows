# SPDX-License-Identifier: MIT
"""Check same-save native turn receipts against an independent analytic lane."""
import argparse
import csv
import hashlib
import json
import math
import re
import statistics
from pathlib import Path

BASELINE_SHA = "16463719ec55e184c02fdabb34bda144d75538cf73356717be05a34b26b26236"


def require(value, message):
    if not value:
        raise AssertionError(message)


def add(a, b): return a[0] + b[0], a[1] + b[1]
def sub(a, b): return a[0] - b[0], a[1] - b[1]
def mul(a, s): return a[0] * s, a[1] * s
def dot(a, b): return a[0] * b[0] + a[1] * b[1]
def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def right(a): return -a[1], a[0]
def norm(a): return math.hypot(*a)
def unit(a): return mul(a, 1 / norm(a))
def wrap(a): return math.atan2(math.sin(a), math.cos(a))


def intersection(p, a, q, b):
    return add(p, mul(a, cross(sub(q, p), b) / cross(a, b)))


def segment_distance(p, a, b):
    d = sub(b, a)
    t = max(0, min(1, dot(sub(p, a), d) / dot(d, d)))
    return norm(sub(p, add(a, mul(d, t))))


class Lane:
    def __init__(self, points):
        require(len(points) == 3, "native fixture must contain exactly one junction")
        first, origin, last = [p[:2] for p in points]
        self.origin = origin
        self.a, self.b = unit(sub(origin, first)), unit(sub(last, origin))
        self.angle = math.atan2(cross(self.a, self.b), dot(self.a, self.b))
        require(abs(abs(self.angle) - math.pi / 2) < .001, "native fixture is a quarter turn")
        wi, wo = points[0][2], points[2][2]
        oi, oo = wi / 4 if wi >= 6 else 0, wo / 4 if wo >= 6 else 0
        self.first, self.last = add(first, mul(right(self.a), oi)), add(last, mul(right(self.b), oo))
        p = intersection(add(origin, mul(right(self.a), oi)), self.a,
                         add(origin, mul(right(self.b), oo)), self.b)
        # Measured stock sedan geometry from Phase 0. Offsets are already scaled.
        rmin = 1.25 * 2.65993 / math.tan(.3 + .6 * (1 - 6 / 90))
        if self.angle > 0:
            kerb = intersection(add(origin, mul(right(self.a), wi / 2)), self.a,
                                add(origin, mul(right(self.b), wo / 2)), self.b)
            safe = []
            for millimetres in range(500, 20001, 5):
                r = millimetres / 1000
                c = add(sub(p, mul(self.a, r * math.tan(self.angle / 2))), mul(right(self.a), r))
                if r - norm(sub(c, kerb)) >= .809991 + .3:
                    safe.append(r)
            self.radius = max(rmin, min(wi / 2, wo / 2, max(safe, default=0)))
        else:
            self.radius = max(rmin, wo / 2 + oi)
        tangent = self.radius * math.tan(abs(self.angle) / 2)
        self.start, self.end = sub(p, mul(self.a, tangent)), add(p, mul(self.b, tangent))
        self.center = add(self.start, mul(right(self.a), math.copysign(self.radius, self.angle)))

    def distance(self, p):
        best = min(segment_distance(p, self.first, self.start), segment_distance(p, self.end, self.last),
                   norm(sub(p, self.start)), norm(sub(p, self.end)))
        u, v = sub(self.start, self.center), sub(p, self.center)
        angle = math.atan2(cross(u, v), dot(u, v))
        if angle * self.angle >= 0 and abs(angle) <= abs(self.angle):
            best = min(best, abs(norm(v) - self.radius))
        return best


def analyze(record):
    require(record["exit"] == 0, "native runner must exit zero: " + record["label"])
    root = Path(record["run"])
    manifest = json.loads((root / "run-manifest.json").read_text(encoding="utf-8-sig"))
    base = root / "cache/Lua/SurvivorCompanionHarness"
    events = (base / "events.log").read_text(encoding="utf-8-sig")
    require("FAIL|" not in events, "native assertion failed: " + record["label"])
    baseline = record["variant"] == "baseline"
    common = ["turn_observer_healthy", "turn_requested_side", "drive_driver_gets_out"]
    if not baseline:
        common.append("turn_no_collision")
    for check in common:
        require("PASS|" + check + "|" in events, "missing native receipt " + check)
    route = next(csv.DictReader((base / "turn-route-tsv.txt").open(encoding="utf-8-sig"), delimiter="\t"))
    require(route["side"] == record["side"], "requested side and receipt disagree")
    require((route["baseline"] == "true") == baseline, "baseline mode must be explicit")
    bridge = manifest["sourceBridgeSha256"].lower()
    require(bridge == record["bridge_sha256"].lower(), "bridge index and launch disagree")
    if baseline:
        require(bridge == BASELINE_SHA and manifest["sourceRelease"] == "0.27.34", "baseline must be exact 0.27.34")
    points = [tuple(map(float, point.split(","))) for point in route["geometry"].split(";")]
    lane = Lane(points)
    require((lane.angle > 0) == (record["side"] == "Right"), "geometry takes the requested turn side")
    rows = list(csv.DictReader((base / "turn-track-csv.txt").open(encoding="utf-8-sig")))
    require(len(rows) >= 30 and rows[-1]["mode"] == "arrived", "complete physical track required")
    entered, exited, peak, error = False, False, 0, 0
    for index, row in enumerate(rows):
        p = float(row["x"]), float(row["y"])
        error = max(error, lane.distance(p))
        entered = entered or dot(sub(p, lane.start), lane.a) >= 0
        heading = math.atan2(float(row["fy"]), float(row["fx"]))
        aligned = abs(wrap(heading - math.atan2(lane.b[1], lane.b[0]))) < math.radians(15)
        exited = exited or entered and dot(sub(p, lane.end), lane.b) > 0 and aligned
        if entered and not exited:
            peak = max(peak, abs(float(row["speed_kmh"])))
        if not baseline:
            require(float(row["health"]) >= 99.9 and float(row["zombies_killed"]) == 0, "driver/contact receipt changed")
        if index:
            previous = rows[index - 1]
            dt = (float(row["ms"]) - float(previous["ms"])) / 1000
            require(0 <= dt <= 1, "native track must remain continuous")
            travel = norm(sub(p, (float(previous["x"]), float(previous["y"]))))
            allowance = max(abs(float(row["speed_kmh"])), abs(float(previous["speed_kmh"]))) / 3.6 * dt + .35
            require(travel <= allowance, "unexplained car displacement in native receipt")
    require(exited, "physical turn never completed")
    body = [float(row["body_condition"]) for row in rows]
    contact = max(body) != min(body) or max(float(row["zombies_killed"]) for row in rows) > 0
    if not baseline:
        require(not contact, "native body damage or contact occurred")
    match = re.search(r"PASS\|turn_receipts_saved\|[^\r\n]*seconds=([\d.]+)", events)
    require(match is not None, "native completion time missing")
    seconds = float(match[1])
    require(abs(float(rows[-1]["ms"]) / 1000 - seconds) < .001, "last sample must use the real completion clock")
    reported = max([float(row["maxLaneError"]) for row in rows if row["maxLaneError"]] or [0])
    if not baseline:
        require(error <= 1.5 and reported <= 1.5, "candidate exceeds native lane-error limit")
        require(peak <= 8, "candidate exceeds native physical corner-speed limit")
        for check in ("turn_checked_arc", "turn_lane_error", "turn_speed_held"):
            require("PASS|" + check + "|" in events, "candidate metadata/check missing: " + check)
    return dict(label=record["label"], variant=record["variant"], side=record["side"], run=root.name,
                bridge_sha256=bridge, seed=manifest["seedSave"], seconds=seconds,
                independent_lane_error=round(error, 5), reported_lane_error=round(reported, 5),
                physical_corner_peak=round(peak, 4), samples=len(rows),
                contact=contact,
                min_fps=min(float(row["fps"]) for row in rows),
                track_sha256=hashlib.sha256((base / "turn-track-csv.txt").read_bytes()).hexdigest(),
                geometry=points)


def plot(records, results, output):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Rectangle
    from matplotlib.lines import Line2D
    fig, axes = plt.subplots(1, 2, figsize=(10, 5.6))
    colors = {"baseline": "#bc4d48", "candidate": "#006eb3"}
    for ax, side in zip(axes, ("Right", "Left")):
        ax.add_patch(Rectangle((-32, -3), 64, 6, color="#e5e8eb", zorder=0))
        ax.add_patch(Rectangle((-3, -32), 6, 38, color="#e5e8eb", zorder=0))
        group = [row for row in results if row["side"] == side]
        lane = Lane(group[0]["geometry"])
        ox, oy = lane.origin
        for record in records:
            if record["side"] != side:
                continue
            path = Path(record["run"]) / "cache/Lua/SurvivorCompanionHarness/turn-track-csv.txt"
            rows = list(csv.DictReader(path.open(encoding="utf-8-sig")))
            ax.plot([float(row["x"]) - ox for row in rows], [float(row["y"]) - oy for row in rows],
                    color=colors[record["variant"]], alpha=.65, linewidth=1.4)
        radial = sub(lane.start, lane.center)
        ideal = [lane.first]
        for step in range(81):
            angle = lane.angle * step / 80
            ideal.append(add(lane.center, (radial[0]*math.cos(angle)-radial[1]*math.sin(angle),
                                           radial[0]*math.sin(angle)+radial[1]*math.cos(angle))))
        ideal.append(lane.last)
        ax.plot([p[0]-ox for p in ideal], [p[1]-oy for p in ideal], color="#333b44", linestyle=":", linewidth=1.1)
        old = [row for row in group if row["variant"] == "baseline"]
        new = [row for row in group if row["variant"] == "candidate"]
        ax.set_title(f"{side} turn\nMedian {statistics.median(row['seconds'] for row in old):.2f} → "
                     f"{statistics.median(row['seconds'] for row in new):.2f} seconds\n"
                     f"Maximum lane error {max(row['independent_lane_error'] for row in old):.2f} → "
                     f"{max(row['independent_lane_error'] for row in new):.2f} m", fontsize=10, pad=12)
        ax.set_xlim((-4, 30) if side == "Right" else (-30, 4))
        ax.set_ylim(4, -31)
        ax.set_aspect("equal")
        ax.set_xlabel("East of junction (metres)", fontsize=9)
        ax.set_ylabel("South of junction (metres)", fontsize=9)
        ax.grid(alpha=.18)
        ax.spines[["top", "right"]].set_visible(False)
    fig.suptitle("Native companion turns in the same saved world", fontsize=14, y=.99)
    fig.legend(handles=[Line2D([], [], color=colors["baseline"], label="0.27.34"),
                        Line2D([], [], color=colors["candidate"], label="Updated driver"),
                        Line2D([], [], color="#333b44", linestyle=":", label="Independent lane reference")],
               loc="upper center", bbox_to_anchor=(.5, .94), ncol=3, frameon=False, fontsize=9)
    fig.text(.5, .025, "Three completed runs per side and version. Stock sedan; roads 6 m wide. North is up.",
             ha="center", fontsize=9, color="#4c5560")
    fig.tight_layout(rect=(0, .105, 1, .88))
    fig.savefig(output / "native-turns-ab.png", dpi=180)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("index", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--plot", action="store_true")
    args = parser.parse_args()
    records = json.loads(args.index.read_text(encoding="utf-8-sig"))
    results = [analyze(record) for record in records]
    for side in ("Right", "Left"):
        group = [row for row in results if row["side"] == side]
        if group:
            reference = Lane(group[0]["geometry"])
            for row in group:
                lane = Lane(row["geometry"])
                require(lane.origin == reference.origin and lane.last == reference.last
                        and dot(lane.a, reference.a) > .99999 and dot(lane.b, reference.b) > .99999,
                        "A/B repetitions must keep the same approach and exit: " + row["label"])
    require(len({row["seed"] for row in results}) == 1, "A/B runs must use the same saved world")
    require(len({row["bridge_sha256"] for row in results if row["variant"] == "candidate"}) <= 1,
            "candidate code must be identical across repeats")
    if not args.partial:
        require(len(results) == 12, "twelve native A/B runs required")
        for side in ("Right", "Left"):
            for variant in ("baseline", "candidate"):
                require(sum(row["side"] == side and row["variant"] == variant for row in results) == 3,
                        "three native repeats per side/version required")
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "analysis.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    if args.plot:
        plot(records, results, args.output)
    for side in ("Right", "Left"):
        group = [row for row in results if row["side"] == side]
        for variant in ("baseline", "candidate"):
            rows = [row for row in group if row["variant"] == variant]
            if rows:
                clean = [row for row in rows if not row["contact"]]
                print(f"NATIVE_TURN {side} {variant} runs={len(rows)} median_s={statistics.median(row['seconds'] for row in rows):.3f} "
                      f"lane_max={max(row['independent_lane_error'] for row in rows):.3f} peak={max(row['physical_corner_peak'] for row in rows):.3f} "
                      f"contacts={len(rows)-len(clean)} clean_median_s={statistics.median(row['seconds'] for row in clean) if clean else None}")
    print("INTERSECTION_NATIVE_ANALYSIS_PASS complete=" + str(not args.partial).lower())


if __name__ == "__main__":
    main()
