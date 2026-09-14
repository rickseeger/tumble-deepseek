#!/usr/bin/env bash
# Locate or fetch a Godot 4.x binary; prints its path on stdout.
set -euo pipefail

GODOT_VERSION="4.7.2"
GODOT_BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.godot-bin"
BIN="$GODOT_DIR/$GODOT_BIN_NAME"

# 1. A `godot` (or `godot4`) already on PATH.
if command -v godot >/dev/null 2>&1; then
  echo "godot"
  exit 0
fi
if command -v godot4 >/dev/null 2>&1; then
  echo "godot4"
  exit 0
fi

# 2. A previously downloaded binary (cached locally, not committed).
if [ -x "$BIN" ]; then
  echo "$BIN"
  exit 0
fi

# 3. Download the official Linux build once (cached in .godot-bin).
echo "Downloading Godot ${GODOT_VERSION} (one-time, cached in .godot-bin) ..." >&2
mkdir -p "$GODOT_DIR"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${GODOT_BIN_NAME}.zip"
if command -v curl >/dev/null 2>&1; then
  curl -fL "$URL" -o "$GODOT_DIR/godot.zip"
else
  wget -O "$GODOT_DIR/godot.zip" "$URL"
fi
unzip -o -q "$GODOT_DIR/godot.zip" -d "$GODOT_DIR"
chmod +x "$BIN"
echo "$BIN"
