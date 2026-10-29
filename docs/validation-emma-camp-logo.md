<!-- SPDX-License-Identifier: MIT -->

# EMMA Camp System logo rework

29 October 2026, `living_fellows/0.26.75`, after the BIOS/hardening update.

The camp header now uses an original shelter/radio shield beside a clearer
EMMA wordmark and a single Camp System subtitle. The previous tiny place/year
line was removed. It has a wider header allowance, bounded to leave caption
space and fit inside the CRT canvas. Business headers retain their existing
layout and original colours.

One neutral source replaces the three-row phosphor atlas and separate purple
runtime selection. The existing native shader keys its black backing and uses
the current screen's phosphor; all four themes share the same source and crop.
The generated bitmap bytes are unchanged. Provenance, measured bounds, source
hash and exact built-in imagegen prompt are in
[the art record](terminal-camp-logo-colours.json). Previous bitmap files are
retained for historical references. No save migration or bridge change is
required, and existing screen colours and computer identities are retained.

The read-only metadata generator now takes the camp source and crop from the
art record. Regeneration changes only the camp rectangle and backing entry;
other business rectangles and palettes are unchanged.

Verification:

- The UI suite passes, including camp tint/crop checks, wider-header bounds
  across ten viewport sizes and four font metrics, and business-layout
  preservation. Existing security, reset, radio, keyboard and hardening tests
  also pass.
- All 243 payload Lua files compile in normal and debug modes. Source hash,
  recorded image dimensions and crop bounds pass the read-only asset audit.
- Native acceptance uses the clone's real powered camp desktop and renderer.
  Green, golden sand, aquamarine and purple all pass keyed monochrome drawing,
  caption clearance and unchanged owner/archive identity. The window closes
  normally with no secondary player view.

Evidence:

- [Green](../artifacts/emma/native-acceptance/emma-camp-v2-green.png)
- [Golden sand](../artifacts/emma/native-acceptance/emma-camp-v2-sand.png)
- [Aquamarine](../artifacts/emma/native-acceptance/emma-camp-v2-aqua.png)
- [Purple](../artifacts/emma/native-acceptance/emma-camp-v2-purple.png)
- [Native results](../artifacts/emma/native-acceptance/terminal-camp-logo-evidence.log)
- [UI checks](../artifacts/emma/native-acceptance/terminal-camp-logo-ui.log)
- [Lua compilation](../artifacts/emma/native-acceptance/terminal-camp-logo-compile.log)

Reproduce with `tests/ui/run_ui_tests.ps1`, `scripts/Test-LuaCompile.ps1` and
`artifacts/emma/run-terminal-camp-logo-native.ps1`. This art/header update uses
focused checks and native previews; the 29-stage project gate was not rerun.
The main game installation and user saves are outside this cloned preview.

After the cloned preview, the updated developer payload was applied to the
existing local installation with Debug retained.
All 338 installed files match the ownership manifest, and the camp artwork,
brand metadata and header code match the working sources. Installation details
are recorded locally in `build/local-camp-logo-install-verification.json`.

The follow-up alignment places the camp logo's left corner marks directly
above the vertical transcript/menu separator. Its aspect ratio is preserved,
and the available width keeps it clear of the close button. The header uses
the same column while menu focus temporarily hides the divider, so the logo
does not jump. Narrow layouts without a menu column retain their existing
header arrangement. The updated UI checks and normal/debug Lua compilation
pass.

The four native palette previews were refreshed and inspected after alignment.
The placement was applied to the existing local build; all 338 manifest files
and the installed header source verify. The local record is
`build/local-logo-alignment-install-verification.json`.
