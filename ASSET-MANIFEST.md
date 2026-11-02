<!-- SPDX-License-Identifier: MIT -->

# Living Fellows asset manifest

The release artwork is an original clean-room generation. No input image, reference image, imported icon pack, copied game asset, logo, trademark, recognizable character, or earlier companion-mod artwork was used.

## Generation

- Mode: built-in `image_gen`
- Calls: three independent generations using the same prompt
- References: none
- Source format: 1254×1254 RGB PNG

```text
Use case: stylized-concept
Asset type: square game mod poster
Primary request: an original isometric survival scene showing teamwork
Scene/backdrop: a simple rainy early-1990s rural American street
Subject: three anonymous survivors; one injured and seated or prone, one
kneeling to bandage them, and one standing guard against distant zombie
silhouettes
Style/medium: deliberately blocky low-poly character models rendered as crisp
low-resolution pixel art; hard pixel clusters; limited sprite-like shading;
looks like a genuine in-game isometric scene rather than illustration
Composition/framing: square, readable silhouettes at thumbnail size
Color palette: muted olive, charcoal, faded denim, rust, and wet asphalt
Constraints: original designs; no text; no logos; no trademarks; no gore; no
recognizable characters; no copied game assets; no reference images
Avoid: photorealism; painterly brushwork; cinematic concept art; smooth skin;
soft AI-generated detail; dramatic lens effects; imitation of a named game
```

## Source variants

| Variant | Project copy | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| 01 | `assets/poster-variants/poster-variant-01.png` | 1254×1254 RGB | `989b26d8e246551231bf542ff449547a4995a9c7180d2c9e8b4226383200b775` |
| 02 | `assets/poster-variants/poster-variant-02.png` | 1254×1254 RGB | `c8589795be5607409b46fde9469e635ca5835c28be108cd67bf8011d0f0b24fb` |
| 03 | `assets/poster-variants/poster-variant-03.png` | 1254×1254 RGB | `6b44c5ba56b7165392f791097e9869ce8ab017ecf747a4c4fee19ce64634aaa1` |

Variant 02 was selected because it best matches the intended isometric geometry, hard pixel clusters, readable teamwork scene, and muted rainy-street palette.

## Selected source and derivatives

The poster and preview derivatives were resized from the selected source with nearest-neighbor sampling only; no sharpening, repainting, compositing, color adjustment, or reference image was used on them. The README banner is a separate wide title-card image supplied for the project (a dusk isometric street scene of the survivor group), replacing the earlier crop of the selected source.

| Purpose | Path | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| Selected source | `assets/poster-selected-source.png` | 1254×1254 RGB | `c8589795be5607409b46fde9469e635ca5835c28be108cd67bf8011d0f0b24fb` |
| README banner | `assets/banner.png` | 2172×724 RGB | `09dfb2b08aa8b89b9f13ffed821166ba33f6847db25655d5463bd42c99bd23e1` |
| Workshop image | `assets/preview-512.png` | 512×512 RGB | `4733a0c1a6d1253516e691b07ee4252332abd418bd413d3e2eacc640e1fabdba` |
| Mod poster | `assets/poster-256.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |
| Workshop preview | `Workshop/preview.png` | 512×512 RGB | `4733a0c1a6d1253516e691b07ee4252332abd418bd413d3e2eacc640e1fabdba` |
| Payload poster | `SurvivorCompanion/poster.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |
| Build 42 poster | `SurvivorCompanion/42/poster.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |

## UI symbols

All UI symbols are original deterministic pixel bitmaps declared in `SurvivorCompanion/42/media/lua/client/SCUIPixels.lua` and rendered at runtime with ISUI rectangles. No generated or imported icon asset is used.

## EMMA terminal artwork

The terminal uses original generated CRT glass, a transparent 1993 Larchfield
casing, sector emblems, a camp emblem and selected transparent adaptations of
fictional in-game firms. Stock company textures remain supplied by Project
Zomboid. A UI shader applies the shared phosphor treatment at draw time;
generation and image analysis never run in the game.

Source prompts, references and selected outputs are recorded in
`docs/terminal-art-manifest.json`, `docs/terminal-expanded-art-manifest.json`,
`docs/terminal-skin-art.json` and `docs/terminal-camp-logo-colours.json`.
Selected outputs in the expanded manifest supersede baseline entries for the
same destination file, including the transparent Knox Bank replacement.
Native captures and the distinction between checks and remaining live
scenarios are in `docs/validation-camp-computer-system.md`.

## Computer lock artwork

Original lock artwork is recorded in `docs/terminal-lock-art.json`, including
the image-generation prompt, original and packaged hashes, and dimensions.
The black-backed bitmaps use the existing phosphor shader for all four screen
colours. Generated originals are retained. Lossless texture partitioning keeps
each PNG below 300 KiB, with sampling gutters for scaled edges. The packaging
tool reconstructs every complete image and asserts identical decoded RGB pixels.

Phase 2 adds an UNDELETE title, the Larchfield handbook cover, three handbook
illustrations and a wheel hub/pointer. These use the same generated-art manifest
and phosphor treatment. Turning rings and glyphs are live code; their fixed
mapping also generates `docs/larchfield-code-wheel.svg` through
`tools/generate_larchfield_wheel.py`. A source check compares the printable's
embedded mapping with `SCTerminalLockWheelData.lua`. The physical handbook uses
vanilla Book and BookClosedGround models; no game model or texture is copied.

Phase 3 adds original LARCH/DIAL-BACK, County Key Escrow and USER2 artwork,
generated with the built-in image_gen tool. The complete prompt set, source
hashes and all lossless packaged rectangles are in the same manifest. All 13
artworks total 5,968,965 bytes in 29 PNGs; largest PNG 297,491 bytes. Each is
tinted by the current CRT phosphor colour; no game or real-company art is used.
The three new pictures have display viewports around their visible ink, so
unused black margins do not shrink them into stickers. The viewport changes
only draw geometry; the complete original RGB pixels remain packaged unchanged.

## Computer lock audio

Eight original synthesized cues are generated by
`tools/generate_terminal_lock_sounds.py` using Python's standard library,
with no imported recordings: mono, 16-bit PCM, 22,050 Hz. The lamp tick,
reel and granted cues use UI audio. Drawer cues play at the physical desk;
forcing also emits gameplay world noise.
The original two-second telephone ring uses a 440/480 Hz pair with 20 Hz
modulation; the callback scheduler supplies the quiet four-second gap. The
handset answer is a short mechanical click. The five-note escrow signature is
original UI audio heard on a verified radio-key receipt. No voice recording,
network service or downloaded music is used.

| Asset under `SurvivorCompanion/42/media/sound/` | SHA-256 |
| --- | --- |
| `LFTerminalLampTick.wav` | 2dbb6b866938d8b89a33c80498570192fe7fe7982f25f25d58dfcfaa79821c77 |
| `LFReelClunk.wav` | 2de70df6919fad95d91aa0c3472ce2b0d7ddf057744fc4f0d939ae6340e654b4 |
| `LFTerminalGranted.wav` | a81bd2416be52b3d4c7e08b817ca6d6495867ced8a2bab7490792c579c2b8b7e |
| `LFDrawerClunk.wav` | 8b4eaa6aaa42599e397434524582449363a13865614a1fd1158a731d9dc7d90f |
| `LFDrawerForce.wav` | 3d55cb1b897e17d757c5a586c2fe282196be49cd87fa6b552eee30f431984419 |
| `LFPhoneRing.wav` | 11fcb9ac42f0d9e8ce6bc720e6ba4ab570b2a00f6ed898f39a47db65f06ea401 |
| `LFPhoneAnswer.wav` | 715964e1df5f8cfd87737a50bfc6a2250ec57aaf9bfa1a243b441bf7e7c941e6 |
| `LFNumbersTune.wav` | b02920e707c103ae14751057b4950a4c15c702237a89fa6f4561bacfd0f7bed8 |

## Building discovery audio

Three original synthesized UI cues are generated deterministically by
`tools/generate_terminal_scan_sounds.py`, using only Python's standard library.
They use no imported recordings or game audio: mono, 16-bit PCM, 22,050 Hz.
The ping, discovery blip and completion phrase play through the UI sound path,
without world noise or zombie attraction.

| Asset under `SurvivorCompanion/42/media/sound/` | SHA-256 |
| --- | --- |
| `LFTerminalScanPing.wav` | d1ae4b66c8f9c6ef3320ea43258d0e365e59ae21c670c1818430ad49d73bfd0c |
| `LFTerminalScanBlip.wav` | 88356dbe59f4401592c19e2942e43a361c902dc303edbf469062c76585e97704 |
| `LFTerminalScanDone.wav` | 9e850ab717fe2490f98258fe8f1502d734559cc02d64cd51a483d9c7f8a1da52 |

- `LFDiceRoll.wav`: original locally synthesized UI dice cue, generated by `tools/generate_terminal_lock_sounds.py`; SHA-256 `ce8cb5e5944cbad349947b91a4a04321c100302def1889203ada298e1f100fcf`.

Phase-four shareware artwork: original built-in image_gen art, losslessly packaged into four images/sheets with independent display windows. Prompts, source hashes, UV windows and exact packaged hashes are in `docs/terminal-lock-art.json`. All lock artwork together: 9,380,939 bytes; maximum texture file 297,491 bytes.
- `StoryTitle`: 1254 x 1254; source SHA-256 `42f9b556096768122829a9d3243c0cce66e067690177f073277d3638a5b0ae4c`.
- `StoryClasses`: 1254 x 1254; source SHA-256 `94a34ea4f71f1fc2924991bd02edf40fef7be07581d09d37440442e6a929d215`.
- `StoryScenes`: 1254 x 1254; source SHA-256 `e7be560ab9f704ab8466a6a1c0159e3ab14b011121059d2299b18bdaf31d4390`.
- `StoryEndings`: 1254 x 1254; source SHA-256 `aa2004fe576bfacb76318db9d73df4e6cf34bbd31c6bfe276d96634bd130c948`.
