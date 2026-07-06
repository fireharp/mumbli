#!/usr/bin/env bash
set -euo pipefail

# Embed a freshly issued project grant into the Mumbli app source tree.

RELEASE="${1:-0.5.0-dev}"
APP_PATH="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
GRANT_DEST="$MAC_APP_DIR/MumbliApp/ProofOfUse/project-grant.json"

"$POU_REPO/ProofOfUseLocal/scripts/issue-mumbli-grant.sh" "$RELEASE" "$APP_PATH"
GRANT_OUT="${GRANT_OUT:-$POU_REPO/ProofOfUseLocal/out/project-grant.json}"
cp "$GRANT_OUT" "$GRANT_DEST"
echo "Embedded grant at $GRANT_DEST"
