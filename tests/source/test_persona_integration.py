"""Persona integration and unchanged supplied-engine contract."""
import hashlib
import re
import wave
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CLIENT=ROOT/'SurvivorCompanion/42/media/lua/client'
PINS={'SCTerminalPersona.lua': '30b28a1b5a8b36d9968d474081bd7f067e19a2da3a13d25f798e90883c140891', 'SCTerminalPersonaSpiffy.lua': '0d78cb8c9c591bfa175e6377ea5c2af5e5c0f8b18b2191f1485739b1481c7536', 'SCTerminalPersonaEllis.lua': 'fc5a3f2ad4004a6c20c2ee23df4fcb1c16e5532fb897f172b3a068379eab6a75', 'SCTerminalPersonaDuty.lua': '9c272386d40145e6a3c3a7165e13a431806b6ff67d33e33e5ac86738dd61b70b'}

for name,digest in PINS.items():
    actual=hashlib.sha256((CLIENT/name).read_text(encoding='utf-8').encode()).hexdigest()
    assert actual==digest, f'{name}: supplied engine/dialogue changed; review with author before changing the pin'
ui=(CLIENT/'SCTerminalPersonaUI.lua').read_text(encoding='utf-8')
terminal=(CLIENT/'SCTerminal.lua').read_text(encoding='utf-8')
locks=(CLIENT/'SCTerminalLocks.lua').read_text(encoding='utf-8')
discovery=(CLIENT/'SCTerminalPersonaDiscovery.lua').read_text(encoding='utf-8')
assert 'P.choose(' in discovery and 'state.fresh=nil' in discovery
assert 'if not state.fresh then return false end' in discovery
assert 'SCConfig' in discovery and 'SC.Config' in discovery
assert 'OnTick' not in discovery and 'Events.' not in discovery
assert 'OnTick' not in ui and 'Events.' not in ui, 'open window owns persona work'
assert 'getInternalText' in ui and 'setX(-10000)' in ui
assert 'saved.noiseAt=hours' in ui and 'saved.reliefDay=day' in ui and 'saved.cheerDay=day' in ui
weights=re.search(r'L.WEIGHTS=([^\n]+)',locks).group(1)
kinds=re.search(r'L.KINDS=([^\n]+)',locks).group(1)
assert 'persona' not in weights+kinds
assert terminal.index('SC.TerminalPersonaUI.input(self,raw)') < terminal.index('SC.TerminalLocks.input(self,trimmed,option)')
assert 'debugPersona = nil' in (ROOT/'SurvivorCompanion/42/media/lua/shared/SCConfig.lua').read_text()
with wave.open(str(ROOT/'SurvivorCompanion/42/media/sound/LFSpiffyJingle.wav')) as sound:
    assert sound.getnchannels()==1 and sound.getsampwidth()==2
    assert 2 < sound.getnframes()/sound.getframerate() < 6
assert 'sound LFSpiffyJingle' in (ROOT/'SurvivorCompanion/42/media/scripts/sounds_LivingFellowsLocks.txt').read_text()
print('PERSONA_INTEGRATION_PASS original-engine=true original-dialogue=true natural-director=true bounded=true original-jingle=true')
