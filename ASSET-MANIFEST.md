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

The source was resized with nearest-neighbor sampling only, and the README banner is a rectangular crop of the selected source. No sharpening, repainting, compositing, color adjustment, or reference image was used.

| Purpose | Path | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| Selected source | `assets/poster-selected-source.png` | 1254×1254 RGB | `c8589795be5607409b46fde9469e635ca5835c28be108cd67bf8011d0f0b24fb` |
| README banner | `assets/banner.png` | 1254×800 RGB | `9d1f7cd2e74a7f5424f49cdd6cf764ef4b596c33fddbd00d6b829184c9732a9f` |
| Workshop image | `assets/preview-512.png` | 512×512 RGB | `4733a0c1a6d1253516e691b07ee4252332abd418bd413d3e2eacc640e1fabdba` |
| Mod poster | `assets/poster-256.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |
| Workshop preview | `Workshop/preview.png` | 512×512 RGB | `4733a0c1a6d1253516e691b07ee4252332abd418bd413d3e2eacc640e1fabdba` |
| Payload poster | `SurvivorCompanion/poster.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |
| Build 42 poster | `SurvivorCompanion/42/poster.png` | 256×256 RGB | `394943ab5257d57cfe72e11fd0a2e5266173160cc9dcac892bbf96acc194faec` |

## UI symbols

All UI symbols are original deterministic pixel bitmaps declared in `SurvivorCompanion/42/media/lua/client/SCUIPixels.lua` and rendered at runtime with ISUI rectangles. No generated or imported icon asset is used.
