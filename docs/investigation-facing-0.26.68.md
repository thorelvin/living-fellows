<!-- SPDX-License-Identifier: MIT -->

# Isometric facing investigation, 26 October 2026

Status: the reported continuous backward-facing movement remains unresolved. It was not reproduced in the available local save. No production facing change has been made.

## Release comparison

The released 0.26.67 (`18a47a19`) and 0.26.68 (`125b9adf`) bridges contain identical native class bytes. `SCNativeCompanion.class` SHA-256 is `73f279368a8d195f76503fab43b87e18dc83a69da62ef7f3209c32b68072e6f7` in both. The release's only gameplay Lua change is the expedition waypoint watchdog. This comparison does not exclude a saved-state, loader or interaction-dependent problem.

## Passive live check

Run `SC-Harness-20261026-031633-0e450d01` used the complete released 0.26.68 mod extracted from Git, including bridge SHA-256 `90c8a0dffd0179c5acb403258d43c9be8dea182b1783c8584ea9ef22b86ddacc`, against Project Zomboid 42.21.0. Bandits and Viewpoint were absent. The private standalone launcher and disposable save were used; the private payload enables diagnostics and removes the public ZombieBuddy dependency.

The probe first watched saved NPCs for 45 seconds without changing their orders, equipment or positions. It then created one ordinary Unemployed companion and issued two opposite public Move here orders along a loaded strip. The fixture set daylight and moved the main observer before the fresh-companion phase. It did not clear zombies, boost companion statistics or write facing/animation state.

| Observation | Result |
| --- | --- |
| Saved actors with movement | Five; 309 moving samples in total |
| Saved backward-facing samples | Five: four associated with taking a seat, one during a path-search turn; no continuous global reversal observed |
| Fresh companion | Both legs completed; 79 moving/body-angle samples, zero with body/travel dot product below -0.5 |
| Main-player ownership | Identity, native slots and player count unchanged in both phases |
| Visual review | Opposite-leg screenshots show the body changing direction with travel |

`SCFacingProbe` compares actual displacement with native forward direction and `getAnimAngle()` in degrees. It never calls `getAnimationPlayer()`, because that accessor can allocate or rebind a model. A body/logical-angle difference provides independent evidence of native animation rotation; a fallback-only trace cannot pass a fresh walking leg. Eleven Kahlua observer checks cover reversed bodies, angle units, absent models, stationary/nonfinite data and the forbidden allocating accessor. The live-harness static suite also passes.

Earlier exploratory runs used an animation getter and are not the basis of the passive result. Two attempted road-follow fixtures could not release saved workers' borrowed supplies and never produced useful facing evidence.

Evidence is retained under `build/moonwalk-regression/`: `release-bridge-comparison.json`, `passive-facing-observer-static.log`, `complete-release-passive-facing.log`, and the extracted release root's `build/live-sandbox-runs/SC-Harness-20261026-031633-0e450d01/` directory with console, events and screenshots.

## Remaining reproduction requirements

The affected session's More → Support report and whether the symptom begins immediately after loading or after Base Watch/expedition return are still needed. These runs do not validate the public ZombieBuddy loader, other mod combinations or a post-view-transition reproduction. The local installed payload remains 0.26.67; it was not replaced by these tests. The original save remains unchanged.
