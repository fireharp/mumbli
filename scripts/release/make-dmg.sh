#!/usr/bin/env bash
set -euo pipefail

# Build the Mumbli installer disk image with its window layout baked in.
#
# Shared by CI and build-signed-dmg.sh so the DMG a maintainer inspects locally
# is produced by exactly the same code as the published one.
#
# dmgbuild is installed into a throwaway virtualenv rather than the ambient
# Python: GitHub's runners ship an externally-managed interpreter that refuses
# plain `pip install`, and a venv sidesteps that without --break-system-packages
# or PATH guesswork about where --user scripts land.
#
# usage: make-dmg.sh <signed-app-path> <volume-name> <output.dmg>

APP="${1:?usage: make-dmg.sh <app> <volume-name> <out.dmg>}"
VOLUME_NAME="${2:?missing volume name}"
OUT="${3:?missing output path}"

[[ -d "$APP" ]] || { echo "error: no app bundle at $APP" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$SCRIPT_DIR/dmg-settings.py"
VENV="${DMG_VENV:-${TMPDIR:-/tmp}/mumbli-dmgbuild-venv}"

if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  echo "==> Installing dmgbuild into $VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet dmgbuild
fi

# dmgbuild refuses to overwrite, and a stale image from a previous run would
# otherwise be published as if it were this build's output.
rm -f "$OUT"

echo "==> Building $OUT (volume \"$VOLUME_NAME\")"
DMG_APP_PATH="$APP" "$VENV/bin/dmgbuild" -s "$SETTINGS" "$VOLUME_NAME" "$OUT"
