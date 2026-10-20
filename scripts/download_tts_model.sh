#!/usr/bin/env bash
# Stage a sherpa-onnx speech model for scripts/smoke_tts.py and for offline
# development builds.
#
# The app itself no longer needs this: native builds download the selected model
# on first run (issues #6, #7) and only use the assets directories below when
# they are declared in pubspec.yaml.
#
# Usage: scripts/download_tts_model.sh [kokoro|kitten] [cache_dir]
#   kokoro (default)  Kokoro v1.0  -> assets/tts/         (model.onnx,
#                                                          tokens.txt,
#                                                          voices.bin,
#                                                          lexicon-us-en.txt,
#                                                          espeak-ng-data.zip)
#   kitten            Kitten nano  -> assets/tts_kitten/  (model.fp16.onnx,
#                                                          tokens.txt,
#                                                          voices.bin,
#                                                          espeak-ng-data.zip)
#   --kitten is still accepted as the old spelling of the model argument.
set -euo pipefail

MODEL="kokoro"
CACHE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --kitten) MODEL="kitten" ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    kokoro|kitten) MODEL="$arg" ;;
    *) CACHE_ARG="$arg" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${CACHE_ARG:-${XDG_CACHE_HOME:-$HOME/.cache}/glowing-waffle}"

if [ "$MODEL" = "kitten" ]; then
  URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kitten-nano-en-v0_2-fp16.tar.bz2"
  ARCHIVE="$CACHE/kitten-nano-en-v0_2-fp16.tar.bz2"
  SRC="$CACHE/kitten-nano-en-v0_2-fp16"
  ASSETS="$ROOT/assets/tts_kitten"
  FILES="model.fp16.onnx tokens.txt voices.bin"
  SIZE="~25 MB"
else
  URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
  ARCHIVE="$CACHE/kokoro-multi-lang-v1_0.tar.bz2"
  SRC="$CACHE/kokoro-multi-lang-v1_0"
  ASSETS="$ROOT/assets/tts"
  FILES="model.onnx tokens.txt voices.bin lexicon-us-en.txt"
  SIZE="~340 MB"
fi

mkdir -p "$CACHE" "$ASSETS"
if [ ! -f "$ARCHIVE" ]; then
  echo "Downloading $MODEL ($SIZE)..."
  curl -fL --retry 3 -o "$ARCHIVE.part" "$URL"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
if [ ! -f "$SRC/tokens.txt" ]; then
  echo "Extracting..."
  if command -v bzip2 >/dev/null 2>&1; then
    tar -xjf "$ARCHIVE" -C "$CACHE"
  else
    # Many minimal images ship tar without bzip2; Python's tarfile handles it.
    python3 -c "import tarfile,sys; tarfile.open(sys.argv[1],'r:bz2').extractall(sys.argv[2])" "$ARCHIVE" "$CACHE"
  fi
fi

for f in $FILES; do
  cp -f "$SRC/$f" "$ASSETS/$f"
  echo "  copied $f"
done
rm -f "$ASSETS/espeak-ng-data.zip"
( cd "$SRC" && python3 -c "import shutil; shutil.make_archive('$ASSETS/espeak-ng-data','zip','.','espeak-ng-data')" )
echo "  created espeak-ng-data.zip"
echo "Done. $MODEL assets are in $ASSETS"
