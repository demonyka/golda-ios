"""Builds the voice note's chimes, ios/Golda/Resources/Sounds/voice-start.wav and voice-stop.wav.

Usage: python3 ios/tools/voice_chimes.py [output folder]

Two soft bell-like tones a fifth apart: rising when the microphone starts listening, falling when it
stops. They are Golda's own, drawn from sine waves here, not taken from any system sound. Each tone
is a sine with a quiet octave partial, a few milliseconds of attack so it does not click, and an
exponential decay; the second tone starts before the first has died away, so the pair reads as one
gesture. The peak sits well under full scale: the chime plays even with the ring switch on silent,
as the system's own listening sounds do, so it must stay polite.

Only the standard library: the output is 16-bit mono PCM WAV at 44.1 kHz, which AVAudioPlayer plays
as is. A change to the sound happens here, and the files are re-generated and committed.
"""
import math
import pathlib
import struct
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'ios/Golda/Resources/Sounds'

RATE = 44_100
# About -15 dBFS at the loudest moment: audible over a quiet room, never a jolt.
PEAK = 0.18

# G5 and D6, a perfect fifth: open and unresolved enough to say "go on", unlike a major third's
# "done". The falling pair reverses it.
LOW = 783.99
HIGH = 1174.66

# The second tone enters 75 ms after the first; each rings out over about 0.2 s.
STEP = 0.075
ATTACK = 0.006
DECAY = 0.055
LENGTH = 0.24


def tone(frequency, start, total):
    """One bell tone starting at [start] seconds, as samples over [total] seconds."""
    samples = [0.0] * int(total * RATE)
    for index in range(int(start * RATE), len(samples)):
        t = index / RATE - start
        if t > LENGTH:
            break
        envelope = min(1.0, t / ATTACK) * math.exp(-t / DECAY)
        # A faint octave partial gives the sine a little body, like a struck glass.
        wave_ = math.sin(2 * math.pi * frequency * t) + 0.12 * math.sin(2 * math.pi * 2 * frequency * t)
        samples[index] = envelope * wave_
    return samples


def chime(first, second):
    total = STEP + LENGTH + 0.02
    a = tone(first, 0.0, total)
    # The second tone a touch softer, so the pair falls away instead of ending on a push.
    b = tone(second, STEP, total)
    mixed = [x + 0.85 * y for x, y in zip(a, b)]
    loudest = max(abs(s) for s in mixed) or 1.0
    scaled = [s / loudest * PEAK for s in mixed]
    # A short fade at the very end, so the file never stops on a non-zero sample.
    fade = int(0.01 * RATE)
    for i in range(fade):
        scaled[-1 - i] *= i / fade
    return scaled


def write(path, samples):
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', round(s * 32767)) for s in samples))


OUT.mkdir(parents=True, exist_ok=True)
write(OUT / 'voice-start.wav', chime(LOW, HIGH))
write(OUT / 'voice-stop.wav', chime(HIGH, LOW))
print(f'Wrote {OUT / "voice-start.wav"} and {OUT / "voice-stop.wav"}')
