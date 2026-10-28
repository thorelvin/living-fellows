<!-- SPDX-License-Identifier: MIT -->

# Speaker colour acceptance

`native-probe.lua` exercises production speech and save capture in the prepared
disposable camp used by the bed/speech acceptance harness. It stages existing
people, adds twelve temporary test companions, holds autonomous decisions and
uses the actual renderer. It never saves or installs into the player's game.

Run `./artifacts/speech-colors/run-native.ps1 -FontSize 2`, then `-FontSize 6`.
The two settings produce different native Small font metrics on this host.
The runner restores the clone's options and stops only its owned process.
All original screenshots and logs go under `build/speech-colors/native-font-*`.
The 21 zoom samples per setting cover short, authored multiline and wrapped
speech at 50, 75, 100, 125, 150, 175 and 200 percent.

`review.py CAPTURES OUTPUT` creates labelled, unscaled review crops and three
colour-vision simulations. It also verifies native mint glyph pixels in the
early/late reading-window captures and calculates palette contrast against
black. Pillow and numpy are development dependencies; the game uses neither.
Derived QA images are labelled separately from original game captures.

`-CheckViewTransition` additionally opens and closes a nearby owned secondary
view. This reproduced the existing `Lighting64.dll+0x23fd` native crash on return.
It is excluded from the successful solo matrix and remains an open acceptance
limitation. See [validation and evidence](../../docs/validation-speech-colors.md).
