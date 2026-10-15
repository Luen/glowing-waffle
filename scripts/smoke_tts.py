#!/usr/bin/env python3
"""End-to-end CPU smoke test for the native TTS path.

Loads the Kokoro files from assets/tts/ with the *same* sherpa-onnx config the
app uses in lib/tts/tts_engine_mobile.dart, synthesizes a sentence and writes a
WAV. Run scripts/download_kokoro.sh first.

    pip install -r scripts/requirements.txt
    python scripts/smoke_tts.py --out /tmp/hello.wav "Hello from Glowing Waffle."
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
ASSETS = ROOT / "assets" / "tts"
REQUIRED = ["model.onnx", "tokens.txt", "voices.bin", "lexicon-us-en.txt", "espeak-ng-data.zip"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?", default="Hello from Glowing Waffle. This audio was generated on the CPU.")
    ap.add_argument("--out", default="smoke.wav")
    ap.add_argument("--sid", type=int, default=0, help="speaker id (0 = af_alloy)")
    args = ap.parse_args()

    missing = [f for f in REQUIRED if not (ASSETS / f).exists()]
    if missing:
        print(f"Missing in {ASSETS}: {', '.join(missing)}. Run scripts/download_kokoro.sh", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp:
        zipfile.ZipFile(ASSETS / "espeak-ng-data.zip").extractall(tmp)
        kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
            model=str(ASSETS / "model.onnx"),
            tokens=str(ASSETS / "tokens.txt"),
            voices=str(ASSETS / "voices.bin"),
            data_dir=f"{tmp}/espeak-ng-data",
            lexicon=str(ASSETS / "lexicon-us-en.txt"),
            lang="en-us",
        )
        config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(kokoro=kokoro, num_threads=2, provider="cpu")
        )
        if not config.validate():
            print("Invalid sherpa-onnx config", file=sys.stderr)
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
