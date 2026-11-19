#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="${1:-$PROJECT_DIR/dist}"
mkdir -p "$DEST_DIR"
DEST_DIR="$(cd "$DEST_DIR" && pwd)"
bash "$PROJECT_DIR/build.sh" "$DEST_DIR"
/usr/bin/ditto -c -k --norsrc --noextattr --noacl --keepParent \
  "$DEST_DIR/Caps Awake.app" "$DEST_DIR/CapsAwake-Mac.zip"
(
  cd "$DEST_DIR"
  /usr/bin/shasum -a 256 CapsAwake-Mac.zip > SHA256SUMS.txt
)
printf 'Packaged: %s\n' "$DEST_DIR/CapsAwake-Mac.zip"
