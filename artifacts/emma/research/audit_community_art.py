# SPDX-License-Identifier: MIT
"""Read generated logo alpha and hash identity sources; never rewrite pixels."""
import hashlib
import json
from pathlib import Path

from PIL import Image

project = Path(__file__).resolve().parents[3]
manifest_path = project / "docs/terminal-community-art-manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
for entry in manifest["entries"]:
    asset = project / entry["file"]
    generated = Path(entry["generated_source"])
    entry["sha256"] = hashlib.sha256(asset.read_bytes()).hexdigest()
    assert entry["sha256"] == hashlib.sha256(generated.read_bytes()).hexdigest(), entry["id"]
    entry["reference_sha256"] = hashlib.sha256(Path(entry["reference"]).read_bytes()).hexdigest()
    with Image.open(asset) as image:
        assert image.mode == "RGBA", (entry["id"], image.mode)
        alpha = image.getchannel("A")
        assert alpha.getextrema() == (0, 255), entry["id"]
        bounds = alpha.point(lambda value: 255 if value >= 32 else 0).getbbox()
        assert bounds and 0 < bounds[0] < bounds[2] < image.width, entry["id"]
        assert 0 < bounds[1] < bounds[3] < image.height, entry["id"]
        entry["size"] = list(image.size)
        entry["alpha_bounds"] = list(bounds)
        histogram = alpha.histogram()
        entry["transparent_fraction"] = round(histogram[0] / (image.width * image.height), 4)
        assert entry["transparent_fraction"] > .35, entry["id"]
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(f"PASS {len(manifest['entries'])} transparent headers; source bytes unchanged; references hashed")

game = Path("C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid")
definition_path = game / "media/lua/shared/PrintMedia/PrintMediaDefinitions.lua"
definitions = definition_path.read_text(encoding="utf-8-sig")
site_keys = ["twiggys", "wpdiy", "thewizardskeep", "muldraughpd", "rosewoodfd",
             "riversidepd", "wptownhall", "hobbsandperkinshardware", "ovofarms",
             "lennyscarrepair", "ekroncollege", "alsautoshop", "stuartandlogscrapyard",
             "darkwallowguesthouse", "a1hay", "gunsunlimitedechocreek", "goldensunset"]
for key in site_keys:
    assert f"    {key} = {{ location1 =" in definitions, key
assert "--entire mall" in next(line for line in definitions.splitlines() if "tacodelpancho =" in line)
sources = {
    "date": "2026-10-27",
    "runtime": "42.21.0",
    "definition_file": str(definition_path),
    "definition_sha256": hashlib.sha256(definition_path.read_bytes()).hexdigest(),
    "new_single_business_advert_keys": site_keys,
    "excluded_whole_mall_key": "tacodelpancho",
    "flyer_references": [{"file": e["reference"], "sha256": e["reference_sha256"]} for e in manifest["entries"]],
    "official_context": "https://projectzomboid.com/blog/features-overview-build-42-20/",
    "context_scope": "Western towns, readable local adverts and environmental storytelling; no live world-state claims.",
    "story_status": "All added owners, dated personal entries and EMMA wording are original mod fiction. Staff names are not claimed as stock canon.",
    "retained_state": "Published owner IDs, portable locks, notes and visits; no save-schema or network change.",
}
(project / "artifacts/emma/research/community-sources.json").write_text(
    json.dumps(sources, indent=2) + "\n", encoding="utf-8")
print(f"PASS {len(site_keys)} specific native advert rectangles; whole-mall advert excluded")
