<!-- SPDX-License-Identifier: MIT -->

# Contributing to Living Fellows

Thank you for helping make survivors more believable, useful, and safe to play alongside.

## Before opening a pull request

- Discuss large behavior, persistence, actor-bridge, or UI changes in an issue first.
- Keep shipped interface text and dialogue in English.
- Preserve single-player fail-closed behavior. Never register a companion as the local player or silently fall back to an unsafe actor.
- Do not include decompiled Project Zomboid source, proprietary game assets, copied third-party mod code, saves, logs, or generated playtest payloads.
- Add or update deterministic tests for every behavior change.
- Keep decisions bounded. A companion should not scan the whole world every frame or repeat a failed action indefinitely.

## Development setup

Living Fellows targets Project Zomboid 42.20.4. PowerShell 5.1 or newer and a local Windows installation of the game are currently required for the complete Java bridge build.

Run the complete project gate from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Project.ps1
```

Build the two distribution paths independently:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Workshop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Standalone.ps1
```

The standalone builder must pass its isolated install/uninstall transaction, including byte-equivalent restoration of the synthetic launcher configuration.

## Runtime conventions

- Native actions use explicit ownership: select, reserve, approach, settle, animate, commit, verify, and resume.
- Gameplay effects happen only after the complete verified animation. Cancellation must release reservations and roll back staged state.
- Survival, escape, new orders, vehicle transitions, and severe injury may interrupt ordinary work.
- Companion speech, scans, recovery, and world events require cooldowns and upper bounds.
- Persistence changes are additive and normalized. Never mutate an established stable document after an incomplete capture.
- Public builds keep experimental providers, automatic debug spawning, and movement recording disabled.
- Never send companion animation, speech, movement, or timed actions through the local player's queues.

## Bug fixes

A useful fix includes:

1. a small reproducible scenario;
2. the actual cause rather than only the visible symptom;
3. a bounded fix that preserves ownership and rollback;
4. regression coverage; and
5. updated player-facing documentation when behavior changes.

## Artwork and dialogue

Only submit work you created or have the right to license under MIT. Do not imitate or copy another mod's distinctive assets. Dialogue should be concise, contextual, rate-limited, and varied enough that one action does not repeat one line constantly.

## License

By contributing, you agree that your contribution is licensed under the repository's [MIT License](LICENSE).
