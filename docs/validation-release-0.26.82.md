<!-- SPDX-License-Identifier: MIT -->

# 0.26.82 validation - beds and backup sleep places

This release includes the hospital-bed, upstairs-entry and backup-sleep fixes
recorded in [the Rosewood acceptance report](validation-firestation-rest-2026-10-30.md).
It retains bridge protocol `42.21-isocompanion-24`, Project Zomboid 42.21.0 and
the existing save schemas. Lua and the rebuilt native bridge ship together.

## Live evidence

The final five-case run, `SC-Harness-20261030-200616-940e22c3`, passed in a
disposable Rosewood world with Living Fellows alone. Companions walked from
downstairs to both original hospital beds, a deployed sleeping bag, a backup
couch and a bunk. Each reached the intended floor and room, retained health
through entry, slept, recovered fatigue and got up through normal cancellation.
Original screenshots were inspected for mattress alignment and floor clipping.

The catalogue audit covered 108 bed tiles, 88 deployed sleeping-bag tiles and
120 couch tiles. This is classification coverage; individual live pose checks
were the five cases above. The tester's exact save and door layout were not
available. All 3,430 files in the original source save matched their pre-run
SHA-256 hashes afterwards.

## Release identity

The version file, README badge, shipped README, both mod descriptors and Lua
release constant identify 0.26.82. The bridge manifest's implementation version
also identifies 0.26.82. Its 75 class files are byte-for-byte identical to the
native build used in acceptance; the final manifest is the only archive-content
change from that build.

Packaged bridge SHA-256:
`2a325b578aa70d6899a9a3b52632311ab9c48a79d377ece6ab519abdcd702487`.

Release synchronization and `git diff --check` passed. The final 0.26.82
project gate passed all 29 stages in 173.1 seconds (8 concurrent jobs).
The local gate transcript is `build/release-0.26.82/project-gate.txt`;
generated logs are excluded from the release commit.
