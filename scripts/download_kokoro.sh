#!/usr/bin/env bash
# Download the sherpa-onnx Kokoro v1.0 model and stage the files the native
# app (and scripts/smoke_tts.py) need into assets/tts/:
#   model.onnx, tokens.txt, voices.bin, lexicon-us-en.txt, espeak-ng-data.zip
# Usage: scripts/download_kokoro.sh [cache_dir]
set -euo pipefail

URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/assets/tts"
CACHE="${1:-${XDG_CACHE_HOME:-$HOME/.cache}/glowing-waffle}"
ARCHIVE="$CACHE/kokoro-multi-lang-v1_0.tar.bz2"
SRC="$CACHE/kokoro-multi-lang-v1_0"

mkdir -p "$CACHE" "$ASSETS"
if [ ! -f "$ARCHIVE" ]; then
  echo "Downloading Kokoro v1.0 (~340 MB)..."
  curl -fL --retry 3 -o "$ARCHIVE.part" "$URL"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
if [ ! -f "$SRC/model.onnx" ]; then
  echo "Extracting..."
  if command -v bzip2 >/dev/null 2>&1; then
    tar -xjf "$ARCHIVE" -C "$CACHE"
  else
    # Many minimal images ship tar without bzip2; Python's tarfile handles it.
    python3 -c "import tarfile,sys; tarfile.open(sys.argv[1],'r:bz2').extractall(sys.argv[2])" "$ARCHIVE" "$CACHE"
  fi
fi

for f in model.onnx tokens.txt voices.bin lexicon-us-en.txt; do
  cp -f "$SRC/$f" "$ASSETS/$f"
  echo "  copied $f"
done
rm -f "$ASSETS/espeak-ng-data.zip"
( cd "$SRC" && python3 -c "import shutil; shutil.make_archive('$ASSETS/espeak-ng-data','zip','.','espeak-ng-data')" )
echo "  created espeak-ng-data.zip"
echo "Done. Kokoro assets are in $ASSETS"
