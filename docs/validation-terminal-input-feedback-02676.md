# Terminal hover and interaction audio

2026-10-30, follow-up to 0.26.76.

Password words and complete matching bracket groups gain a bold stroke while the pointer is over their current selectable span. The code font, measured geometry and click areas remain unchanged. The extra stroke is clipped within the span and releases its stencil immediately. Junk, used groups and locked-out targets do not gain emphasis. Hover spends no attempt and plays no sound.

Imported the user's `mouse_click.mp3` and `login.mp3` from Downloads. Original copies and hashes are recorded in `docs/terminal-input-audio.json`; the payload uses locally encoded Ogg Vorbis with the decoded rates, channel counts and duration preserved. The click is 0.366 seconds; login is 0.914 seconds. Both are non-looping, non-spatial UI sounds.

The click plays once for password mouse presses, mouse/keyboard menu choices, input focus, close/back controls and radio controls. Native button activation uses the custom sound instead of adding it to the default sound. A successful password recovery plays the login cue for either mouse or keyboard input. Wrong guesses, hover and reopening an already unlocked machine do not play login. Audio errors do not block the chosen action.

Verification: the UI suite passes, including **88 password pixel/hover checks**, **29 audio checks**, **263 radio checks** and 93 Python UI contract tests. All **244 Lua files compile** normally and in debug mode. Both packaged clips decode successfully and match their source/payload hashes, duration, channels and UI sound registrations. Local output: `build/terminal-input-feedback/ui-tests.txt` and `lua-compile.txt`.

Later verification, 2026-10-30: the combined follow-ups, including these UI/audio additions, passed all 29 project stages in 120 seconds and were installed with the game closed. Installed terminal/audio files match the source hashes. Live visual/audio acceptance remains outstanding. These changes are included in [release 0.26.78](validation-release-0.26.78.md); see `validation-car-wash-retry-02676.md` for the combined run before the version bump.
