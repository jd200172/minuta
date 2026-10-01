"""Builds a synthetic two-channel meeting from script.json using macOS `say`.

Outputs in ./out: mic.wav, system.wav, stereo.wav (L=mic, R=system),
the same three as .ogg (Opus), and ground-truth.json with per-turn timing.
Requires macOS (`say`, `afconvert`) and ffmpeg with libopus.
"""
import array
import json
import subprocess
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE / "out"
RATE = 16000
DEFAULT_GAP = 0.6


def synthesize(voice: str, text: str, workdir: Path, index: int) -> array.array:
    aiff = workdir / f"{index}.aiff"
    wav = workdir / f"{index}.wav"
    subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", str(aiff), str(wav)],
        check=True,
    )
    with wave.open(str(wav), "rb") as w:
        samples = array.array("h")
        samples.frombytes(w.readframes(w.getnframes()))
    return samples


def mix_into(track: array.array, samples: array.array, start: int) -> None:
    end = start + len(samples)
    if end > len(track):
        track.extend([0] * (end - len(track)))
    for i, s in enumerate(samples):
        value = track[start + i] + s
        track[start + i] = max(-32768, min(32767, value))


def write_wav(path: Path, channels: list[array.array]) -> None:
    length = max(len(c) for c in channels)
    for c in channels:
        c.extend([0] * (length - len(c)))
    if len(channels) == 1:
        data = channels[0]
    else:
        data = array.array("h", [0] * (length * len(channels)))
        for idx, c in enumerate(channels):
            data[idx::len(channels)] = c
    with wave.open(str(path), "wb") as w:
        w.setnchannels(len(channels))
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def to_opus(wav_path: Path) -> None:
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav_path),
         "-c:a", "libopus", "-b:a", "24k", str(wav_path.with_suffix(".ogg"))],
        check=True,
    )


def main() -> None:
    script = json.loads((HERE / "script.json").read_text(encoding="utf-8"))
    speakers = script["speakers"]
    OUT.mkdir(exist_ok=True)
    tracks = {"mic": array.array("h"), "system": array.array("h")}
    truth = []
    cursor = 0.0
    with tempfile.TemporaryDirectory() as tmp:
        for i, turn in enumerate(script["turns"], start=1):
            info = speakers[turn["speaker"]]
            samples = synthesize(info["voice"], turn["text"], Path(tmp), i)
            start = max(0.0, cursor + turn.get("gap", DEFAULT_GAP))
            mix_into(tracks[info["channel"]], samples, int(start * RATE))
            end = start + len(samples) / RATE
            cursor = end
            truth.append({
                "id": f"t-{int(start):06d}",
                "speaker": turn["speaker"],
                "channel": info["channel"],
                "start_s": round(start, 2),
                "end_s": round(end, 2),
                "text": turn["text"],
            })
    mic, system = tracks["mic"], tracks["system"]
    write_wav(OUT / "mic.wav", [array.array("h", mic)])
    write_wav(OUT / "system.wav", [array.array("h", system)])
    write_wav(OUT / "stereo.wav", [array.array("h", mic), array.array("h", system)])
    for name in ("mic", "system", "stereo"):
        to_opus(OUT / f"{name}.wav")
    (OUT / "ground-truth.json").write_text(
        json.dumps({"meeting_date": script["meeting_date"], "turns": truth},
                   ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"turns: {len(truth)}  duration: {cursor:.1f}s")


if __name__ == "__main__":
    main()
