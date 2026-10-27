<!-- SPDX-License-Identifier: MIT -->

# Taxi radio device filtering

27 October 2026, `living_fellows/0.26.72` continuation.

The inventory menu previously chose the first native `Radio` item even when
`TaxiBooking.checkRadio` rejected it. Stock televisions use that same native
item class, so a TV received a misleading taxi submenu. The stock TV could
not complete the old booking validation: it is not portable, not two-way and
has zero transmit range.

The menu now selects only a handset that passes booking validation, and
explicitly excludes televisions from the shared transmit-menu path. Booking
validation also rejects the TV flag even if other device fields claim it can
transmit. Terminal radio installation and issued station endpoints apply the
same TV exclusion. This uses device capabilities rather than a list of allowed
walkie-talkie item names. The native bridge and save schemas are unchanged.

Focused checks cover TV-class devices, receive-only and unusable handsets,
mixed item stacks, exact callback binding, stale callbacks, mounted-component
ownership and endpoint revalidation. Existing taxi booking, fare recovery,
pickup, in-car actions and UI tests pass.

The native probe runs in an existing disposable cloned world. It creates
`Base.TvAntique`, `Base.TvBlack` and `Base.TvWideScreen`, confirms their native
`Radio` class and TV/portable/two-way/range flags, and calls the production
inventory-menu builder. None receives a taxi submenu. `Base.RadioRed` is also
rejected; a powered `Base.WalkieTalkie2` retains the menu both alone and in a
mixed stack. Turning it off hides the menu. Setting its TV flag rejects a
stale booking request. The probe removes its own items and never dispatches a
cab or invokes a valid booking request. The player's actual save is untouched.

- [Native evidence](../artifacts/emma/native-acceptance/taxi-radio-devices-evidence.log)
- [Native probe](../artifacts/emma/taxi-radio-devices-native.lua)
- Stock data: installed 42.21.0 `media/scripts/generated/items/radio.txt`.

The full project gate passed **29/29 stages**, including all 237 Lua files in
normal and debug compilation, taxi regressions and UI tests. Its result is recorded in
[taxi-tv-project-gate.log](../artifacts/emma/native-acceptance/taxi-tv-project-gate.log).
Local installation is separate from this source-validation pass.
