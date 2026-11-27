# SPDX-License-Identifier: MIT
"""Verify owned reference citations against installed 42.22 game data.

Only paths, hashes and pass receipts are written; game source is never copied.
The native log pins the installed build used for the manual content review.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / 'LivingFellows/42/media/lua/client'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def block(text, header):
    match = re.search(header + r'\s*\{', text)
    if not match:
        raise ValueError('Missing source definition: ' + header)
    start = text.index('{', match.start())
    depth = 0
    for i in range(start, len(text)):
        depth += (text[i] == '{') - (text[i] == '}')
        if depth == 0:
            return text[start:i + 1]
    raise ValueError('Unclosed source definition: ' + header)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-root', type=Path, default=Path(
        r'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid'))
    parser.add_argument('--native-log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    native = args.native_log.read_text(encoding='utf-8-sig', errors='replace')
    versions = set(re.findall(r'\bversion=(42\.22\.\d+)\b', native))
    if len(versions) != 1:
        raise ValueError('Native log must identify one installed Build 42.22 version')
    data = CLIENT / 'SCEmmaReferenceData.lua'
    topics = re.findall(r'topic\("([^"]+)","[^"]+",\{[^}]+\},\s*"([^"]+)"',
                        data.read_text(encoding='utf-8'))
    if len(topics) != 27 or len({row[0] for row in topics}) != 27:
        raise ValueError('Expected all 27 unique authored reference topics')
    sources = {}
    for topic, citations in topics:
        for citation in citations.split('; '):
            base = CLIENT if citation.startswith('mod:') else args.game_root / 'media'
            relative = citation.removeprefix('mod:')
            path = (base / relative).resolve()
            if not path.is_relative_to(base.resolve()) or not path.is_file():
                raise ValueError(f'Missing or escaped citation for {topic}: {citation}')
            sources[citation] = {'sha256': digest(path), 'bytes': path.stat().st_size}

    def source(name):
        path = args.game_root / 'media' / name
        sources.setdefault(name, {'sha256': digest(path), 'bytes': path.stat().st_size})
        return path.read_text(encoding='utf-8-sig')

    checks = []

    def require(label, text, *needles):
        if not all(needle in text for needle in needles):
            raise ValueError('Game fact changed: ' + label)
        checks.append(label)

    trapping = source('scripts/generated/recipes/recipes_trapping.txt')
    require('crate trap recipe, learning and tools', block(trapping, r'craftRecipe MakeWoodenBoxTrap'),
            'NeedToBeLearn = true', 'Trapping:4', 'base:saw', 'base:hammer',
            'item 3 [Base.Plank]', 'item 5 [Base.Nails]', 'Base.TrapCrate')
    require('stick trap recipe', block(trapping, r'craftRecipe MakeStickTrap'),
            'item 4 [Base.WoodenStick2]', 'item 1 [Base.Twine]', 'Base.TrapStick')
    names = json.loads(source('lua/shared/Translate/EN/ItemName.json'))
    for name, label in {'Pistol': 'M9 Pistol', 'Pistol2': 'M1911 Pistol',
                        'Pistol3': 'B-F Pistol', 'TrapCrate': 'Crate Trap'}.items():
        if names.get('Base.' + name) != label:
            raise ValueError('Item name changed: ' + name)
        checks.append('item name: ' + name)
    weapons = source('scripts/generated/items/weapon.txt')
    for name, ammo in {'Pistol': 'bullets_9mm', 'Pistol2': 'bullets_45',
                       'Pistol3': 'bullets_44', 'Shotgun': 'shotgun_shells',
                       'DoubleBarrelShotgun': 'shotgun_shells'}.items():
        require('ammunition: ' + name, block(weapons, r'\bitem ' + name + r'\b'),
                'AmmoType = base:' + ammo)
    require('campfire extinguishing action', source('lua/shared/Camping/ISCampingMenu.lua'),
            'campingText.putOutCampfire', 'ISPutOutCampfireAction:new')
    require('vehicle siphoning needs hose', source('lua/client/Vehicles/ISUI/ISVehiclePartMenu.lua'),
            'SIPHON_GAS')
    require('generator repair requires scrap', source('lua/shared/TimedActions/ISFixGenerator.lua'),
            'ElectronicsScrap')
    report = {'gameVersion': versions.pop(), 'referenceSha256': digest(data),
              'nativeLog': str(args.native_log.resolve()), 'topics': len(topics),
              'sourceCount': len(sources), 'sources': dict(sorted(sources.items())),
              'factChecks': checks,
              'scope': 'Citations and selected exact facts. Authored advice also requires content review.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f"EMMA_SOURCE_PASS version={report['gameVersion']} topics={len(topics)} "
          f"sources={len(sources)} exact_checks={len(checks)} receipt={args.output}")


if __name__ == '__main__':
    main()
