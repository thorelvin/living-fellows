<!-- SPDX-License-Identifier: MIT -->

# EMMA factory reset

28 October 2026, `living_fellows/0.26.74`, after `9b27e043`.

`factory reset` and explicit variants such as `Emma, reset this computer to
factory settings` propose a reset of the current machine. EMMA discloses the
permanent erasure and waits for Y/N confirmation. Questions such as `What does
factory reset do?` explain the operation without proposing it. The command
works away from camp, without granting access to camp records.

Confirmation clears the old owner's archive, firm branding, saved operator
nickname, notes, visit count and cached conversation. Both legacy and portable
memory slots are cleared. The old window loses its session before closing, so
its close handler cannot write erased notes back. A new window runs POST and
creates a fresh EMMA session. Its personal directory is empty and retains a
working numbered Back command. The factory archive is excluded from discovery
pools, so reopening or moving the computer cannot select another old owner.

The machine retains its persistent identity, seed, screen colour (including
purple), access state, password-recovery history and one-time Electrical XP
record. Actual mounted parts and unrelated portable/mod data are untouched.
Building links and connected equipment keep their current settings. Installed
county/EMMA reference files remain available. Other machines' saved data and
cached conversations are not reset.

Requests bind the exact window, object and access record, expire after two
minutes and are consumed before dispatch. Confirmation rechecks main-player
ownership, life, proximity, power, presence and unlocked access. A different
question, refusal, close, expired ticket or changed machine cancels the request.

Automated coverage includes explicit and informational phrasing, unrelated job
commands, cancellation, expiry, power loss, movement, changed access records,
locked/invalid security data, single dispatch, session replacement, legacy
memory, independent computers, repeated resets and a simulated serialized
furniture pickup/reload boundary. Security tests verify that the same puzzle
history and XP ledger survive normalization. Existing story pools keep all 135
owners and 540 entries.

Native acceptance used Project Zomboid 42.21.0 and the paired protocol
`42.21-isocompanion-24` in a disposable cloned save. A real powered desktop with
a mounted radio was operated through its actual terminal input. Old office
software and user notes were staged on that clone. The run verified proposal,
refusal, accepted reset, POST, fresh operator memory, empty directory, stable
physical identity, untouched unrelated payload, rejected ticket replay and
reopening after clearing the session cache. No secondary player slot was used.
Four 1280×720 framebuffer captures were inspected: confirmation, POST, empty
personal files and clean EMMA. Native save-to-disk/relaunch and furniture pickup
were not repeated for this change; those boundaries are covered here by the
portable-data and normalization tests.

The final full project gate passed **29/29 stages**, in 159.3 seconds for the
stages and 162 seconds overall. It includes the new reset UI tests, the brain
and security harnesses, existing computer/building services, and compilation
of all 241 payload Lua files in normal and debug configurations.

Reproduction and evidence:

- `artifacts/emma/run-terminal-civic-tests.ps1` — brain/security/archive checks.
- `tests/ui/run_ui_tests.ps1` — confirmation, UI and portable-memory regressions.
- `artifacts/emma/run-terminal-reset-native.ps1` and
  `artifacts/emma/terminal-reset-native.lua` — cloned-game acceptance.
- `artifacts/emma/native-acceptance/terminal-reset-*.log` and
  `emma-reset-*.png` — validation logs and inspected captures.

This is a Lua-only addition. No runtime network access, native bridge or game
installation changes are required by the command.
