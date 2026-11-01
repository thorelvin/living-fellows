"""Generate original, quiet LARCH/SCAN feedback. Python standard library only."""
from pathlib import Path
import math
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
SOUNDS = {
    "LFTerminalScanPing": [(660, .11, .13)],
    "LFTerminalScanBlip": [(1046.5, .045, .08)],
    "LFTerminalScanDone": [(523.25, .09, .14), (659.25, .09, .14), (783.99, .18, .13)],
}


def generate():
    for name, notes in SOUNDS.items():
        frames = []
        for frequency, duration, amplitude in notes:
            samples = int(RATE * duration)
            for i in range(samples):
                t = i / RATE
                envelope = min(1, t / .008) * (1 - i / samples) ** 2
                value = amplitude * envelope * math.sin(2 * math.pi * frequency * t)
                frames.append(struct.pack("<h", round(value * 32767)))
        path = ROOT / "SurvivorCompanion/42/media/sound" / (name + ".wav")
        with wave.open(str(path), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(b"".join(frames))


if __name__ == "__main__":
    generate()
