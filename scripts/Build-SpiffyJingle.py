"""Original three-second computer-speaker jingle. Deterministic, no samples."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
# A bright welcome, a repeated sales flourish, then an awkward hanging note.
NOTES = [(76, .15), (79, .15), (83, .26), (81, .15), (79, .15),
         (76, .32), (0, .12), (79, .15), (83, .15), (86, .32),
         (84, .15), (83, .15), (79, .32), (0, .14), (80, .64)]
samples = []
for note, seconds in NOTES:
    count = round(seconds * RATE)
    frequency = 440 * 2 ** ((note - 69) / 12) if note else 0
    for i in range(count):
        t = i / RATE
        envelope = min(1, t / .009, (seconds-t) / .045)
        tone = sum(math.sin(2*math.pi*frequency*h*t)/(h*h) for h in (1, 3, 5)) if note else 0
        samples.append(round(12500 * max(0, envelope) * tone))
destination = Path(__file__).resolve().parents[1] / 'SurvivorCompanion/42/media/sound/LFSpiffyJingle.wav'
with wave.open(str(destination), 'wb') as output:
    output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
    output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
print(f'SPIFFY_JINGLE_BUILD seconds={len(samples)/RATE:.2f} peak={max(abs(s) for s in samples)}')
