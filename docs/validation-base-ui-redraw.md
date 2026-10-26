<!-- SPDX-License-Identifier: MIT -->

# Base overlay redraw validation

Validated on 2026-10-26 against the pinned Project Zomboid 42.21.0 runtime.

## Cause and changes

The installed game's `FBORenderAreaHighlights` stamps submitted highlights with `UIManager.uiRenderTimeMS` and retains every entry with that timestamp. Submitting a mark on every world frame therefore stacks duplicate tints between UI redraws, then drops them together when the UI timestamp changes.

Base-area and storage tints, construction guide fills, grouped-room flashes and marking previews now submit from `OnPreUIDraw`. World outlines, construction ghost sprites and persistent storage-object outlines retain their world render path. The existing caches and explicit marking invalidation remain in use.

Base tab previously included the selected companion's entire live roster description in its rebuild signature. Its companion signature now uses identity, name and order. Its separate base-state signature still detects job, policy, role, marking and displayed retry-minute changes. Roster values and control availability continue refreshing without rebuilding the page.

## Automated verification

- The focused UI suite passes, including 93 static UI contracts and the existing native checkbox, storage-menu, medical-menu, construction and companion-name checks.
- A highlight-lifetime fixture models the native UI timestamp retention at world rates of 30, 60 and 120 FPS and UI rates of 15, 30 and 60 FPS. All nine combinations keep one submission per mark per UI redraw and constant opacity between redraws.
- Additional redraw cases cover cache refreshes, focus, unmarking storage, floor changes, hiding the layout, marking previews, grouped-room flash expiry and split-screen construction guides.
- The Base refresh regression runs the actual roster refresh path. Changing health, hunger, distance, activity, action details and sub-minute retry time retains the controls while updating row data. Names, duty orders, roles, policies, zones, storage and retry-minute boundaries still refresh the page.
- Both new regressions fail when run against the pre-fix production sources from commit `76c288e5`.
- The full project gate passes all 29 stages: 93.4 seconds for the stages, 97 seconds including preparation. This includes Lua compilation, native isolation, both NPC adapters, packaging and installer transaction checks.

Local evidence is under `build/ui-refresh-fix/`: `project-gate.log`, `negative-overlay.log` and `negative-base-refresh.log`.

## Live confirmation

No new in-game visual acceptance was run for this patch. The redraw-rate tests model the inspected native lifetime; they are not screenshots or an observed game session. Local installation and visual confirmation of an updating Base tab remain pending.
