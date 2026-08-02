#!/usr/bin/env bash
set -euo pipefail

# Sign the release binding for a published Mumbli release.
#
# Run this AFTER the GitHub release exists. It downloads the published DMG,
# measures it (sha256 of the DMG, cdhash/team/bundle of the .app inside), and
# signs a release-binding:v1 document tying:
#
#   dmg_sha256 -> cdhash -> app_identity -> grant_id -> source commit
#
# That is the missing link between a usage receipt (which carries app_identity
# and grant_id) and the SLSA build provenance GitHub attached to the DMG
# (which carries dmg_sha256 -> commit). Neither half proves much alone.
#
# usage: issue-release-binding.sh <tag>        e.g. issue-release-binding.sh v0.5.0

TAG="${1:-}"
if [[ -z "$TAG" ]]; then
  echo "usage: $(basename "$0") <tag>   e.g. $(basename "$0") v0.5.0" >&2
  exit 1
fi
VERSION="${TAG#v}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
ISSUER_KEY="${ISSUER_KEY:-$POU_REPO/keys/mumbli/issuer.json}"
GRANT_FILE="${GRANT_FILE:-$MAC_APP_DIR/MumbliApp/ProofOfUse/project-grant.json}"
REPO="${REPO:-fireharp/mumbli}"
OUT_DIR="$MAC_APP_DIR/docs/proof/releases/$TAG"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if ! command -v gh > /dev/null 2>&1; then
  echo "gh (GitHub CLI) is required to download the release and check its provenance." >&2
  echo "Install it with: brew install gh" >&2
  exit 1
fi

POU="$POU_REPO/bin/pou"
if [[ ! -x "$POU" ]]; then
  echo "Building pou from $POU_REPO ..."
  (cd "$POU_REPO" && go build -o bin/pou ./cmd/pou)
fi

if [[ ! -f "$ISSUER_KEY" ]]; then
  echo "Issuer key not found at $ISSUER_KEY" >&2
  echo "The issuer key is maintainer-local and never lives in CI." >&2
  exit 1
fi

echo "==> Downloading release assets for $TAG"
gh release download "$TAG" --repo "$REPO" --pattern '*.dmg' --dir "$WORK_DIR"
DMG="$(find "$WORK_DIR" -maxdepth 1 -name '*.dmg' | head -1)"
if [[ -z "$DMG" ]]; then
  echo "No DMG found in release $TAG" >&2
  exit 1
fi
echo "    $(basename "$DMG")"

echo "==> Resolving source commit for $TAG"
COMMIT="$(gh api "repos/$REPO/git/ref/tags/${TAG}" --jq '.object.sha')"
# Annotated tags point at a tag object; dereference to the commit.
OBJ_TYPE="$(gh api "repos/$REPO/git/ref/tags/${TAG}" --jq '.object.type')"
if [[ "$OBJ_TYPE" == "tag" ]]; then
  COMMIT="$(gh api "repos/$REPO/git/tags/$COMMIT" --jq '.object.sha')"
fi
echo "    $COMMIT"

echo "==> Verifying GitHub build provenance"
if gh attestation verify "$DMG" --repo "$REPO"; then
  PROVENANCE_URL="https://github.com/$REPO/attestations"
else
  echo "!! Provenance verification failed or no attestation found." >&2
  echo "   Releases built before SLSA provenance was enabled have none." >&2
  if [[ "${ALLOW_NO_PROVENANCE:-}" == "1" ]]; then
    echo "   ALLOW_NO_PROVENANCE=1 — continuing without a provenance reference." >&2
  elif [[ -t 0 ]]; then
    read -r -p "   Continue and sign a binding with no provenance reference? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || exit 1
  else
    echo "   Refusing to sign a binding with no provenance in a non-interactive shell." >&2
    echo "   Re-run with ALLOW_NO_PROVENANCE=1 if that is genuinely what you want." >&2
    exit 1
  fi
  PROVENANCE_URL=""
fi

echo "==> Measuring artifact and signing binding"
mkdir -p "$OUT_DIR"
"$POU" binding issue \
  --grant-file "$GRANT_FILE" \
  --dmg "$DMG" \
  --key "$ISSUER_KEY" \
  --provenance-url "$PROVENANCE_URL" \
  --commit "$COMMIT" \
  --tag "$TAG" \
  --out "$OUT_DIR/release-binding.json"

echo "==> Verifying the binding against the DMG it describes"
"$POU" binding verify \
  --binding "$OUT_DIR/release-binding.json" \
  --trusted-keys "$MAC_APP_DIR/docs/proof/trusted-keys.json" \
  --dmg "$DMG"

echo ""
echo "Wrote $OUT_DIR/release-binding.json"
echo "Commit it, then publish-proof.sh will feed it to the verifier automatically."
