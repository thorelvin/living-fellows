"""Original local UI ticks and mechanical drawer cues; no imported recordings."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
SOUNDS = {
    "LFTerminalLampTick": (0.025, 1450, 0.06, 0.15),
    "LFReelClunk": (0.075, 180, 0.13, 0.45),
    "LFTerminalGranted": (0.25, 85, 0.22, 0.35),
    "LFDrawerClunk": (0.3, 110, 0.3, 0.6),
    "LFDrawerForce": (0.75, 75, 0.5, 0.85),
    "LFDiceRoll": (0.65, 350, 0.28, 0.85),
}


def generate():
    for index, (name, (duration, frequency, amplitude, noise)) in enumerate(SOUNDS.items()):
        rng = random.Random(1993 + index)
        frames = bytearray()
        count = round(RATE * duration)
        for i in range(count):
            t = i / RATE
            envelope = min(1, t / 0.002) * (1 - i / count) ** 3
            tone = math.sin(2 * math.pi * frequency * t) + 0.25 * math.sin(2 * math.pi * frequency * 2.3 * t)
            value = amplitude * envelope * ((1 - noise) * tone + noise * rng.uniform(-1, 1))
            frames.extend(struct.pack("<h", round(max(-1, min(1, value)) * 32767)))
        path = ROOT / "SurvivorCompanion/42/media/sound" / (name + ".wav")
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(frames)
    # Original US-cadence ring, handset click and five-note escrow signature.
    # The scheduler owns ring cadence; this file is just one two-second burst.
    for name, duration in (("LFPhoneRing", 2.0), ("LFPhoneAnswer", .22), ("LFNumbersTune", 1.5)):
        frames = bytearray()
        count = round(RATE * duration)
        for i in range(count):
            t = i / RATE
            edge = min(1, t / .012, (duration - t) / .025)
            if name == "LFPhoneRing":
                value = .25 * edge * (.55 + .45 * math.sin(2 * math.pi * 20 * t)) * (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t))
            elif name == "LFPhoneAnswer":
                value = .3 * math.exp(-30*t) * (math.sin(2*math.pi*170*t) + .3*math.sin(2*math.pi*1530*t))
            else:
                note = min(4, int(t / .3))
                frequency = (523.25, 392, 440, 329.63, 493.88)[note]
                value = .19 * edge * min(1, (.3 - t % .3) / .06) * math.sin(2*math.pi*frequency*t)
            frames.extend(struct.pack("<h", round(max(-1, min(1, value)) * 32767)))
        path = ROOT / "SurvivorCompanion/42/media/sound" / (name + ".wav")
        with wave.open(str(path), "wb") as stream:
            stream.setnchannels(1)
            stream.setsampwidth(2)
            stream.setframerate(RATE)
            stream.writeframes(frames)


if __name__ == "__main__":
    generate()
