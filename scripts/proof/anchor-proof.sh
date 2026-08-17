#!/usr/bin/env bash
set -euo pipefail

# Anchor a published epoch proof to a GitHub Release.
#
# publish-proof.sh writes the epoch artifacts into the repo. This publishes the
# same bytes as release assets under a `proof-<epoch>` tag, so the Merkle root
# for an epoch is pinned at a point in time rather than only living in a branch
# that can be rewritten.
#
# This anchors WHAT WAS PUBLISHED. It does not prove the publisher included every
# receipt they held — see the completeness caveat in docs/proof/README.md.
#
# usage: anchor-proof.sh [epoch]     defaults to the current UTC epoch

EPOCH="${1:-${EPOCH:-$(date -u +%Y-%m)}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO="${REPO:-fireharp/mumbli}"
EPOCH_DIR="$MAC_APP_DIR/docs/proof/$EPOCH"
BINDINGS_DIR="$MAC_APP_DIR/docs/proof/releases"
TAG="proof-$EPOCH"

if [[ ! -f "$EPOCH_DIR/public-proof.json" ]]; then
  echo "No published proof at $EPOCH_DIR/public-proof.json" >&2
  echo "Run scripts/proof/publish-proof.sh first." >&2
  exit 1
fi

read -r MERKLE_ROOT EVENTS USERS < <(python3 - "$EPOCH_DIR/public-proof.json" <<'PY'
import json, sys
statement = json.load(open(sys.argv[1]))["statement"]
print(statement.get("merkle_root", "?"),
      statement.get("total_events", "?"),
      statement.get("unique_users_in_epoch", "?"))
PY
)

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cp "$EPOCH_DIR/public-proof.json" "$WORK_DIR/"
[[ -f "$EPOCH_DIR/audit-pack.json" ]] && cp "$EPOCH_DIR/audit-pack.json" "$WORK_DIR/"
cp "$MAC_APP_DIR/docs/proof/trusted-keys.json" "$WORK_DIR/"

# Bindings travel with the proof so a verifier needs nothing but these assets.
if [[ -d "$BINDINGS_DIR" ]]; then
  while IFS= read -r binding; do
    tag_name="$(basename "$(dirname "$binding")")"
    cp "$binding" "$WORK_DIR/release-binding-${tag_name}.json"
  done < <(find "$BINDINGS_DIR" -name 'release-binding.json' | sort)
fi

(cd "$WORK_DIR" && shasum -a 256 ./*.json | sed 's|\./||' > checksums.txt)

NOTES="$WORK_DIR/notes.md"
cat > "$NOTES" <<EOF
Usage proof for epoch **$EPOCH**.

| | |
|---|---|
| Merkle root | \`$MERKLE_ROOT\` |
| Total events | $EVENTS |
| Distinct installs | $USERS |

Verify without trusting this page:

\`\`\`bash
gh release download $TAG --repo $REPO
pou verify-public public-proof.json --trusted-keys trusted-keys.json
pou verify-audit public-proof.json audit-pack.json \\
  --trusted-keys trusted-keys.json \\
  \$(for b in release-binding-*.json; do printf -- '--release-binding %s ' "\$b"; done)
\`\`\`

Each \`release-binding-*.json\` ties a receipt's app identity to the SHA-256 of a
released DMG, which GitHub's build provenance ties back to a source commit:

\`\`\`bash
gh attestation verify Mumbli-<version>.dmg --repo $REPO
\`\`\`

This anchors what was published for this epoch. It does not prove the publisher
included every receipt they held — see docs/proof/README.md.
EOF

if gh release view "$TAG" --repo "$REPO" > /dev/null 2>&1; then
  echo "==> Updating existing release $TAG"
  gh release edit "$TAG" --repo "$REPO" --notes-file "$NOTES"
else
  echo "==> Creating release $TAG"
  gh release create "$TAG" --repo "$REPO" \
    --title "Usage proof $EPOCH" \
    --notes-file "$NOTES"
fi

gh release upload "$TAG" --repo "$REPO" --clobber "$WORK_DIR"/*.json "$WORK_DIR/checksums.txt"

echo ""
echo "Anchored epoch $EPOCH at https://github.com/$REPO/releases/tag/$TAG"
echo "Merkle root: $MERKLE_ROOT"
echo ""
echo "Now attest the published proof digest (tamper-evidence beyond the release itself):"
echo "  gh workflow run attest-proof.yml --repo $REPO -f epoch=$EPOCH"
