# SPDX-License-Identifier: MIT
"""Static guards for the action-supervisor ownership contract.

These encode the 0.25.5 residual-risk review conclusions that cannot be proved
from inside a single Kahlua harness, because they are properties of *every*
call site rather than of one code path:

  1. `Supervisor.begin` refuses for two unrelated reasons -- the actor is really
     unavailable, or queued urgent work was just dispatched and the caller must
     stand down for a cycle. Every caller has to tell those apart, or an urgent
     preemption silently reads as a work failure and burns retry budget.
  2. Kahlua does not honour Lua weak tables, so the supervisor's actor maps only
     shrink through the explicit release path. Retirement paths must call it.
  3. The deferral vocabulary lives in exactly one place, so adapters cannot
     drift apart as new statuses are added.
"""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
LUA = ROOT / "SurvivorCompanion/42/media/lua"
CLIENT = LUA / "client"

failures: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        failures.append(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


supervisor = read(CLIENT / "SCActionSupervisor.lua")

# ---------------------------------------------------------------------------
# 1. The deferral vocabulary is defined once, and every status begin() can
#    return for an urgent/preemption hand-off is in it.
# ---------------------------------------------------------------------------
table = re.search(
    r"local deferredStatuses = \{(.*?)\n\}", supervisor, re.S
)
require(table is not None, "SCActionSupervisor must define a deferredStatuses table")
declared = set(re.findall(r"^\s*([a-z_]+) = true", table.group(1), re.M)) if table else set()

expected = {
    "urgent_dispatched",
    "actor_owned_after_urgent_dispatch",
    "actor_owned_after_preemption",
}
require(
    declared == expected,
    f"deferred status vocabulary drifted: declared {sorted(declared)} != {sorted(expected)}",
)

# Every deferral status begin() actually emits must be declared. Catches a new
# hand-off status added to begin() without teaching callers to defer on it.
emitted = set(
    re.findall(r'return nil, "([a-z_]*(?:urgent|preemption)[a-z_]*)"', supervisor)
) | set(
    re.findall(r'return nil, "([a-z_]*(?:urgent|preemption)[a-z_]*):"', supervisor)
)
for status in emitted:
    require(
        status in declared,
        f"begin() emits '{status}' but it is not in deferredStatuses, "
        "so callers will treat an urgent hand-off as a refusal",
    )

for name in ("isDeferredStatus", "containsDeferredStatus"):
    require(
        f"function Supervisor.{name}(" in supervisor,
        f"SCActionSupervisor must expose {name} as the single classification point",
    )

# ---------------------------------------------------------------------------
# 2. Every begin() call site classifies deferrals.
# ---------------------------------------------------------------------------
call_sites: list[tuple[Path, int]] = []
for path in sorted(CLIENT.glob("SC*.lua")):
    if path.name == "SCActionSupervisor.lua":
        continue
    text = read(path)
    for match in re.finditer(r"\b(?:service|supervisor)\.begin\(", text):
        line = text.count("\n", 0, match.start()) + 1
        call_sites.append((path, line))

require(
    len(call_sites) >= 9,
    f"expected the known begin() call sites, found {len(call_sites)}",
)

for path, line in call_sites:
    text = read(path)
    # The refusal handling follows the call within a short window; require the
    # classification to appear there rather than anywhere in the file, so a
    # second call site in the same module cannot borrow the first one's guard.
    window = "\n".join(text.splitlines()[line - 1 : line + 60])
    require(
        "containsDeferredStatus" in window or "isDeferredStatus" in window,
        f"{path.name}:{line} calls Supervisor.begin without classifying an "
        "urgent/preemption deferral; an urgent hand-off would be counted as a "
        "work refusal",
    )

# ---------------------------------------------------------------------------
# 3. The decision layer yields the pulse on a deferral instead of cascading
#    into the fallback ladder or a safety hold.
# ---------------------------------------------------------------------------
decision = read(CLIENT / "SCDecision.lua")
require(
    "containsDeferredStatus" in decision,
    "SCDecision must recognise a deferred begin() so it does not descend the "
    "fallback ladder while urgent work owns the actor",
)
require(
    re.search(
        r"if not handled and deferredToUrgentWork\(reason\) then", decision
    )
    is not None,
    "SCDecision.update must yield the pulse on a deferral before the fallback "
    "candidate loop runs",
)

# ---------------------------------------------------------------------------
# 4. Retirement paths reach the explicit release (weak tables are a no-op).
# ---------------------------------------------------------------------------
actor = read(CLIENT / "SCActor.lua")
quarantine = re.search(
    r"local function quarantineRecord\(record, reason\)(.*?)\nend", actor, re.S
)
require(quarantine is not None, "SCActor must define quarantineRecord")
require(
    quarantine is not None and "releaseActionOwnership" in quarantine.group(1),
    "SCActor.quarantineRecord marks a record inactive, so it must release "
    "supervisor ownership first or the actor's maps leak for the session",
)
require(
    quarantine is not None
    and "preserveVehicleBoardCommit" in quarantine.group(1),
    "quarantineRecord must honour the vehicle-board commit exemption rather "
    "than tearing down a commit-phase board transaction",
)

require(
    "function Supervisor.trackedActors()" in supervisor,
    "SCActionSupervisor must expose trackedActors so teardown boundaries can "
    "find orphaned state",
)
runtime = read(CLIENT / "SCRuntime.lua")
require(
    "function runtime.sweepOrphanSupervisorState(" in runtime,
    "SCRuntime must provide the teardown-boundary orphan sweep",
)
require(
    "sweepOrphanSupervisorState" in runtime.split("function runtime.onMainMenuEnter()")[-1],
    "runtime.onMainMenuEnter must run the orphan sweep",
)

# ---------------------------------------------------------------------------
# 5. Rollback quarantine is bounded and fails closed while native work runs.
# ---------------------------------------------------------------------------
force = re.search(
    r"local function forceReleaseExhaustedRollback\(token, obligation\)(.*?)\nend\n",
    supervisor,
    re.S,
)
require(force is not None, "SCActionSupervisor must bound rollback quarantine")
body = force.group(1) if force else ""
require(
    "actionRollbackQuarantineMs" in body,
    "the force-release must wait a configured grace window, not fire immediately",
)
require(
    "nativeActivity" in body and "rollback_quarantined_native_busy" in body,
    "the force-release must fail closed while a native action still owns the body",
)
require(
    "rollback_force_released" in body,
    "the force-release must leave a history event Support can report",
)
require(
    re.search(r"if rollback\.exhausted == true then\s*\n\s*return forceReleaseExhaustedRollback",
              supervisor)
    is not None,
    "Supervisor.update must route an exhausted rollback into the force-release",
)

support = read(CLIENT / "SCSupport.lua")
for name in ("leakedReservationDetails", "quarantineSnapshot"):
    require(
        name in support,
        f"SCSupport must surface {name} so a copied report names the stuck owner",
    )

if failures:
    for item in failures:
        print("SUPERVISOR_CONTRACT_FAIL: " + item)
    raise SystemExit(1)

print(
    "SUPERVISOR_CONTRACT_PASS call-sites=%d deferred-statuses=%d"
    % (len(call_sites), len(declared))
)
