"""Builds synthetic two-channel meetings from scenarios/<name>/script.json using macOS `say`.

Usage: build.py <scenario> [<scenario> ...] | --all | --list
A scenario is a folder name under scenarios/ (or a path to one).

Outputs in <scenario>/out: mic.wav, system.wav, stereo.wav (L=mic, R=system),
the same three as .ogg (Opus), and ground-truth.json with per-turn timing.
Requires macOS (`say`, `afconvert`) and ffmpeg with libopus.
"""
import array
import json
import sys
import subprocess
import tempfile
import wave
from pathlib import Path

HERE = Path(__file__).parent
SCENARIOS = HERE / "scenarios"
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


def build(folder: Path) -> None:
    script = json.loads((folder / "script.json").read_text(encoding="utf-8"))
    speakers = script["speakers"]
    OUT = folder / "out"
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
    print(f"{folder.name}: turns {len(truth)}  duration {cursor:.1f}s")


def resolve(name: str) -> Path:
    path = Path(name)
    if (path / "script.json").exists():
        return path
    if (SCENARIOS / name / "script.json").exists():
        return SCENARIOS / name
    sys.exit(f"scenario not found: {name}")


def main() -> None:
    args = sys.argv[1:]
    available = sorted(p.parent for p in SCENARIOS.glob("*/script.json"))
    if not args or args == ["--list"]:
        print("\n".join(p.name for p in available))
        return
    folders = available if args == ["--all"] else [resolve(a) for a in args]
    for folder in folders:
        build(folder)


if __name__ == "__main__":
    main()
