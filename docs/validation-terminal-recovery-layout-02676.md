# Password recovery layout and office logo

2026-10-30, follow-up to 0.26.76.

The screenshot's password rows painted a complete row, then repainted highlighted words at offsets estimated from the width of `M`. Unequal native glyph advances displaced the second copy and its mouse target. Rows now use measured, non-overlapping colour runs. Each character is painted once; selectable targets reuse those exact offsets and widths. Measured board runs are cached, and board width is fitted on layout changes. Existing words, guesses, attempts and lockout rules are unchanged.

The generic **Local Business** logo had its cream lettering misclassified as background. The shader therefore erased the text and retained the navy silhouette. The read-only metadata generator now keys the navy backing instead, preserves the pale lettering and disables dark-ink inversion. This generic mark follows the active phosphor in green, sand, aqua and purple; named firms retain their existing colour treatment. No source image pixels, shaders or native bridge code changed.

Verification: a native-width fixture failed on the previous password renderer's overlapping runs. The corrected renderer passes **56 checks** across 480×540, 640×480, 1280×720 and 2560×1440, including exact painted text, pixel bounds, zoom, hit targets, cache reuse and one-attempt clicks. Existing recovery paging, lockout and keyboard scenarios pass. Nine additional presentation checks cover office shader parameters in all four themes and preserved named-brand colours.

A read-only check of the original office PNG and the shader's alpha-key calculation finds 327,726 pale lettering pixels: their retained opacity increases from 4.22% to 100%. All 258,701 sampled navy pixels within the key threshold are removed. Local result: `build/terminal-security-layout/logo-ink-check.json`.

Full project gate: **29/29 passed**, 174 seconds. All 244 Lua files compile normally and with debug enabled. Output: `build/terminal-security-layout/project-gate.txt`. The preceding camp-only report menu and tiredness persistence changes are included in this gate.

Live rendered acceptance is pending. These changes were installed with the game closed on 2026-10-30, after the combined follow-ups passed all 29 project stages. Installed terminal and logo metadata match the tested files. They are included in [release 0.26.78](validation-release-0.26.78.md).
