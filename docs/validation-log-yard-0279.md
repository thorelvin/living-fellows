<!-- SPDX-License-Identifier: MIT -->

# Native log-yard bundling and untying — 2026-11-11

Project Zomboid 42.22.2, `living_fellows/0.27.9`, working changes after
`807d28b7`. Lua only; the native bridge and protocol are unchanged.

The old yard exchanged items immediately and recognized only `Base.Rope`.
Its independent idle-worker pass could also wait behind a permanently busy
camp queue. Full tiles now request ordinary `stack_logs` jobs. Workers fetch
rope through the normal storage interaction and run the installed
`ISHandcraftAction` with `Base.MakeFourLogStack`: four exact ground logs and
two exact carried ropes. Vanilla creates the bundle, consumes the inputs and
writes `ropeItems`. The existing four-log row layout is retained.

Only one stacking preparation runs at a time, preventing two workers from
each retaining one of the final two ropes. Missing supplies return the partial
loan, release claims and retry after three minutes. Optional saved job receipts
retain stable input/output identities; an ambiguous attempted craft is never
replayed. Native callbacks are instance-scoped. Cancellation releases only the
matching job's action and returns surviving borrowed rope. Yard discovery shares
the maintenance round-robin, inspecting at most eight tiles per slice. Rope
discovery retains its cursor and inspects at most 64 items/four containers per
work update, after building a bounded carried-container list. Exact receipt
lookups also resume bounded scans when inventory ids change on load; cached
items are revalidated and native ids are only hints. Large shelves cannot be
misreported as missing stock simply because an earlier scan stopped at 1,024 items.

## Automated checks

- Full five-check gate passed, serially, in 110.3 seconds:
  `build/test-results/20261111-215143-ade7de`.
- Final Cargo passed after adding an inactive-item fast path:
  `build/test-results/20261111-215533-e59399`. Unmarked haul/sort stock does
  not call the new yard ownership lookup.
- Cargo includes the installed handcraft Lua action body and covers rope-tagged
  variants, exact native consumption/output metadata, no consumption during
  preparation, repeated callbacks, competing jobs, a one-rope shortage,
  cancellation, a refused output drop, incremental discovery and exact lookup beyond 1,500 shelf items,
  native failure after output creation, stale container/id-cache references,
  consumed personal-bag rope cleanup, and persisted receipt normalization.
- Existing work-transport/yard layout, withdrawal and split regressions passed
  as a focused 58-source run using `build/log-yard-checks/work-transport.txt`.
  Obsolete instant-bundling tests were replaced or removed.

## Live acceptance

Passed **14 checks, zero failures** in
`build/live-sandbox-runs/SC-Harness-20261111-215428-71a8fce3`.
The source save was read only. One low-impact game process ran at a time.

The isolated clone supplied a real outdoor crate marked Crafting, four exact
native ropes, eight native logs and two adjacent log-yard tiles. The worker
used normal BaseWork scheduling and storage withdrawals. Clone-only camp/job
isolation and fatigue/endurance/time setup kept unrelated duties out of this
targeted test. Native crafting was observed; both tiles finished as one
`Base.LogStacks4` each in about 38 seconds. All four supplied ropes were consumed;
both outputs retained the native two-rope `ropeItems` metadata. Before, tying
and finished screenshots are in that run's `cache/Screenshots` directory.

Earlier setup runs are retained separately: `212039-b0efd2eb` failed to register
the probe, `212250-492fd869` lacked a loaded permitted shelf, and
`212620-0b8e9e1a` completed the physical craft but incorrectly recorded progress
messages as failures. `214308-4a8e5e47` caught an overly early consumption check added during
large-inventory hardening. Native item pointers can lag physical removal; the
controller now reconciles actual floor/container membership after action release.
The native work cleanup also checks surviving membership before returning bagged
rope, preventing consumed inputs from being restored. The final run includes
these corrections. The earlier `214858-7b552cab` run also passed all 14
checks; the final run waits a rendered frame before its finished screenshot.
This live run
does not claim reload/death coverage; interruption and save receipts were checked
in the automated scenarios above.

## Native untying

Construction and sawing now open `Base.LogStacks2`, `Base.LogStacks3` and
`Base.LogStacks4` through the installed `ISHandcraftAction` and corresponding
`UnstackTwoLogs`, `UnstackThreeLogs` and `UnstackFourLogs` recipes. The native
recipe creates the loose logs; its `splitLogStack` callback returns the original
rope types recorded in `ropeItems`. LF moves these actual outputs, takes one
log and leaves the remainder on the source yard tile. It does not synthesize
logs, refund guessed rope or reconstruct a consumed bundle.

An optional receipt belongs to the existing construction/production job,
retaining its worker, source identity, attempt flag and native output identities.
Cancellation waits for the matching native action to release. Surviving items
stay with their real owners; ambiguous attempted work blocks rather than
replaying. Previously saved version-one split receipts keep their legacy
reconciliation path. Missing native rope metadata is refused before consumption.

Focused Cargo passed in `build/test-results/20261111-232240-0190e5`.
The final full five-check gate passed serially in 104.2 seconds:
`build/test-results/20261111-233119-50b36a`.
The existing native-action fixture covers all three sizes, mixed rope types,
exact output pickup, repeated callbacks, cancellation before/after consumption,
refused output drops and saved receipt normalization. The focused 58-source
work-transport/legacy-split regression also passed. Obsolete synchronous split
tests were removed now that the native action owns consumption and creation.

Live acceptance passed **21 checks, zero failures** in
`build/live-sandbox-runs/SC-Harness-20261111-232655-598c5cd5`.
The same isolated yard fixture first crafted two four-log bundles, then opened
one under a leased construction parent job. The native unstack action was
observed; the exact source bundle was consumed, one native log entered the
worker's inventory, three native logs remained on that yard tile, two native
ropes returned and the parent receipt/claims cleared. Rendered screenshots
include `log-yard-untying.png` and `log-yard-unstacked.png` suffixes in that run's
`cache/Screenshots` directory. This checks the physical untying operation, not a
completed building or sawing order. Two-/three-log bundles, rope variants,
interruption and save normalization were automated checks, not separate live
reload/death scenarios. The original save was unchanged.
