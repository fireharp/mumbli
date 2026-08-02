#!/usr/bin/env bash
set -euo pipefail

# Embed a freshly issued project grant into the Mumbli app source tree.
#
# The grant is issued BEFORE the build and deliberately does not pin a cdhash.
# Pinning one here would be circular: the grant is bundled into the app, so
# embedding it changes the very cdhash it claims to describe. The artifact is
# measured after the release instead — see scripts/proof/issue-release-binding.sh.

RELEASE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
GRANT_DEST="$MAC_APP_DIR/MumbliApp/ProofOfUse/project-grant.json"

if [[ -z "$RELEASE" ]]; then
  RELEASE="$(sed -nE 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' "$MAC_APP_DIR/project.yml" | head -1)"
  if [[ -z "$RELEASE" ]]; then
    echo "usage: $(basename "$0") <release>   (could not read MARKETING_VERSION from project.yml)" >&2
    exit 1
  fi
  echo "Release not given; using MARKETING_VERSION from project.yml: $RELEASE"
fi

"$POU_REPO/ProofOfUseLocal/scripts/issue-mumbli-grant.sh" "$RELEASE"
GRANT_OUT="${GRANT_OUT:-$POU_REPO/ProofOfUseLocal/out/project-grant.json}"
cp "$GRANT_OUT" "$GRANT_DEST"
echo "Embedded grant at $GRANT_DEST"
echo "Rebuild the app, cut the release, then run: scripts/proof/issue-release-binding.sh v$RELEASE"
