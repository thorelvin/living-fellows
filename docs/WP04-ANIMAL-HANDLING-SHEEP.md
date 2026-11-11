<!-- SPDX-License-Identifier: MIT -->
# WP04 — sheep care, wool and ewe milking

Target 0.27.9; base 0.27.8 at `7c3f2d21`, Project Zomboid 42.22.2.

Farmers supply sheep troughs, shear adult sheep, physically gather their native
wool drops and deliver them to Crafting, then General storage. Ewes use the
existing measured milk workflow with SheepMilk and nursing-lamb reserves.
Player choices: include ewe milking; shear year-round under vanilla eligibility.

All three vanilla breeds, ewes, rams and lambs share the existing bounded farm
lane. Complete enclosures and interaction sides must remain within the existing
30-tile camp work reach. Sheep pastures support 1,024 tiles; scans retain the
16-square/32-animal slices, eight-zone and 128-receipt limits. No new service,
role, area, storage category or native bridge protocol is introduced.

Shearing starts at 80% of native maximum fleece, above one native unit, in
daylight with stress at most 40. Manual shears are preferred over electric
ones; native wear, battery use, XP and animal stress remain native. Lambs and
young animals are never sheared. Borrowed equipment returns to permitted source
storage. Water/feed, hutch timing, milk and eggs retain precedence.

Each native fleece debit must match one newly created raw-wool item. Claim
that exact item before another worker can sort it. Carrying room, ledger space
and storage are checked before another increment. Partial batches are gathered
and delivered before work resumes; full storage preserves cargo and retries.
Cancellation, death and reload must retain native ownership without replacing
missing or ambiguous output. Movement holds, sounds and tool state must be
released after every action outcome.

Ewe milk uses 50% start without a lamb, 70% with a nursing lamb, 40% retained
reserve, 80% urgency and the existing daily limit/multiple-load job. SheepMilk
and CowMilk remain distinct. Existing CowMilk receipts keep their legacy
stable-animal-ID field and remain readable.

Phases: native contracts; species/trough/milk generalization; shearing and
exact delivery/recovery; release/docs. Extend existing essential groups rather
than adding a test framework. Focused cloned-save tests cover breeds, both
tools, low/skilled Farmers, mixed pastures, interruption, storage pressure and
exact cargo reload. Run one low-impact game instance at a time; capture every
blocker zoomed out. Finish with one five-check serial release gate and record
automated and native results separately.

Breeding management, culling, wool processing and the broader animal overview
remain outside this package. Sheep gates remain off until native acceptance.

Implemented on 2026-11-11. Sheep defaults are enabled after native acceptance;
the five-check release gate passes. See
`animal-native-probe-2026-11-11-sheep.md` for measurements and explicit limits.
