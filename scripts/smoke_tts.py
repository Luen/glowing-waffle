#!/usr/bin/env python3
"""End-to-end CPU smoke test for the native TTS path.

Loads a model with the *same* sherpa-onnx config the app uses in
lib/tts/tts_engine_mobile.dart, synthesizes a sentence and writes a WAV. Run
scripts/download_tts_model.sh first (pass kitten for the small model):

    pip install -r scripts/requirements.txt
    scripts/download_tts_model.sh
    python scripts/smoke_tts.py --out /tmp/hello.wav "Hello from Glowing Waffle."
    scripts/download_tts_model.sh kitten
    python scripts/smoke_tts.py --engine kitten --out /tmp/kitten.wav
"""
import argparse
import pathlib
import sys
import tempfile
import time
import zipfile

import sherpa_onnx
import soundfile as sf

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Mirrors lib/tts/tts_models.dart: which files the engine reads per model.
ENGINES = {
    "kokoro": {
        "assets": ROOT / "assets" / "tts",
        "onnx": "model.onnx",
        "files": ["tokens.txt", "voices.bin", "lexicon-us-en.txt", "espeak-ng-data.zip"],
    },
    "kitten": {
        "assets": ROOT / "assets" / "tts_kitten",
        "onnx": "model.fp16.onnx",
        # Kitten has no lexicon: espeak-ng does the phonemizing.
        "files": ["tokens.txt", "voices.bin", "espeak-ng-data.zip"],
    },
}


def build_model_config(engine: str, assets: pathlib.Path, data_dir: str):
    """The model config lib/tts/tts_engine_mobile.dart builds for [engine]."""
    if engine == "kokoro":
        return sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=str(assets / "model.onnx"),
                tokens=str(assets / "tokens.txt"),
                voices=str(assets / "voices.bin"),
                data_dir=data_dir,
                lexicon=str(assets / "lexicon-us-en.txt"),
                lang="en-us",
            ),
            num_threads=2,
            provider="cpu",
        )
    return sherpa_onnx.OfflineTtsModelConfig(
        kitten=sherpa_onnx.OfflineTtsKittenModelConfig(
            model=str(assets / "model.fp16.onnx"),
            tokens=str(assets / "tokens.txt"),
            voices=str(assets / "voices.bin"),
            data_dir=data_dir,
        ),
        num_threads=2,
        provider="cpu",
    )


def _safe_extract_zip(zip_path: pathlib.Path, dest: pathlib.Path) -> None:
    """Extract [zip_path] into [dest], refusing path-traversal members (CWE-22).

    ZipFile.extractall / extract write member names as-is, so a crafted
    archive can escape dest via ``..`` or absolute paths. Validate each
    member, then copy bytes ourselves (no extract*) so nothing leaves dest
    (Snyk python/TarSlip, #75).
    """
    dest = dest.resolve()
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            member = pathlib.PurePosixPath(info.filename)
            if member.is_absolute() or ".." in member.parts:
                raise ValueError(f"refusing unsafe zip member: {info.filename!r}")
            target = (dest / pathlib.Path(*member.parts)).resolve()
            try:
                target.relative_to(dest)
            except ValueError as exc:
                raise ValueError(
                    f"refusing unsafe zip member: {info.filename!r}"
                ) from exc
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, target.open("wb") as out:
                out.write(src.read())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?", default="Hello from Glowing Waffle. This audio was generated on the CPU.")
    ap.add_argument("--out", default="smoke.wav")
    ap.add_argument("--engine", choices=sorted(ENGINES), default="kokoro")
    ap.add_argument("--sid", type=int, default=0, help="speaker id (kokoro: 0-19, kitten: 0-7)")
    ap.add_argument("--assets", type=pathlib.Path, default=None,
                    help="model directory (default: assets/tts, assets/tts_kitten for kitten)")
    args = ap.parse_args()

    spec = ENGINES[args.engine]
    assets = args.assets or spec["assets"]
    missing = [f for f in spec["files"] + [spec["onnx"]] if not (assets / f).exists()]
    if missing:
        stage = "scripts/download_tts_model.sh" + (" kitten" if args.engine == "kitten" else "")
        print(f"Missing in {assets}: {', '.join(missing)}. Run {stage}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        _safe_extract_zip(assets / "espeak-ng-data.zip", pathlib.Path(tmp))
        config = sherpa_onnx.OfflineTtsConfig(
            model=build_model_config(args.engine, assets, f"{tmp}/espeak-ng-data")
        )
        if not config.validate():
            print(f"Invalid sherpa-onnx config ({args.engine})", file=sys.stderr)
            return 1
        tts = sherpa_onnx.OfflineTts(config)
        start = time.time()
        audio = tts.generate(args.text, sid=args.sid, speed=1.0)
        elapsed = time.time() - start

    if len(audio.samples) == 0:
        print("No audio generated", file=sys.stderr)
        return 1
    sf.write(args.out, audio.samples, samplerate=audio.sample_rate, subtype="PCM_16")
    dur = len(audio.samples) / audio.sample_rate
    print(f"Wrote {args.out}: {dur:.2f}s @ {audio.sample_rate} Hz in {elapsed:.2f}s (RTF {elapsed / dur:.2f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
