#!/usr/bin/env bash
# Builds llama.xcframework (Metal enabled) from the pinned llama.cpp submodule
# and places it where the medha_llama podspec expects it. Run on macOS with
# Xcode installed:  ./tool/build_ios_llama.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA="$ROOT/native/llama.cpp"
DEST="$ROOT/packages/medha_llama/ios/Frameworks"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

git -C "$ROOT" submodule update --init --depth 1 native/llama.cpp

(cd "$LLAMA" && ./build-xcframework.sh)

mkdir -p "$DEST"
rm -rf "$DEST/llama.xcframework"
cp -R "$LLAMA/build-apple/llama.xcframework" "$DEST/"
echo "Copied llama.xcframework to $DEST"
