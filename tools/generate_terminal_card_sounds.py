"""Original deterministic magnetic-stripe UI cues; no imported recordings."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050


def generate():
    rng = random.Random(19930709)
    for name, duration in (("LFCardSwipe", .4), ("LFCardRead", .13)):
        frames = bytearray()
        count = round(RATE * duration)
        low = previous = 0.0
        for i in range(count):
            t = i / RATE
            edge = min(1, t / .008, (duration - t) / .018)
            if name == "LFCardSwipe":
                # Two low-pass stages and their difference form a soft band of
                # paper/head friction, with a restrained roller pulse.
                low += .32 * (rng.uniform(-1, 1) - low)
                previous += .055 * (low - previous)
                envelope = math.sin(math.pi * i / count) ** .65
                value = .50 * edge * envelope * (low - previous)
                value += .025 * edge * envelope * math.sin(2 * math.pi * 180 * t)
            else:
                frequency = 1050 if t < .065 else 1450
                note = t % .065
                value = .15 * edge * min(1, note / .004, (.065 - note) / .012)
                value *= math.sin(2 * math.pi * frequency * t)
            frames.extend(struct.pack("<h", round(max(-1, min(1, value)) * 32767)))
        path = ROOT / "SurvivorCompanion/42/media/sound" / (name + ".wav")
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(frames)


if __name__ == "__main__":
    generate()
