#!/usr/bin/env bash
set -euo pipefail

# Aggregate local Mumbli receipts, verify, and write publishable proof artifacts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
ATTESTOR_KEY="${ATTESTOR_KEY:-$POU_REPO/keys/mumbli/attestor.json}"
TRUSTED_KEYS="$MAC_APP_DIR/docs/proof/trusted-keys.json"
RECEIPTS="${RECEIPTS:-$HOME/Library/Application Support/Mumbli/proof/receipts.jsonl}"
PROJECT="github.com/fireharp/mumbli"
EPOCH="2026-07"
OUT_DIR="$MAC_APP_DIR/docs/proof/$EPOCH"
STAGING="$MAC_APP_DIR/.proof-staging"

POU="$POU_REPO/bin/pou"
if [[ ! -x "$POU" ]]; then
  echo "Building pou from $POU_REPO ..."
  (cd "$POU_REPO" && go build -o bin/pou ./cmd/pou)
fi

if [[ ! -f "$RECEIPTS" ]]; then
  echo "No receipts at $RECEIPTS"
  echo "Enable Usage Proof in Mumbli and dictate at least once."
  exit 1
fi

if [[ ! -f "$ATTESTOR_KEY" ]]; then
  echo "Attestor key not found at $ATTESTOR_KEY"
  exit 1
fi

ISSUER_PUB="$(python3 -c "import json; print(json.load(open('$TRUSTED_KEYS'))['issuer_public_key'])")"

rm -rf "$STAGING"
mkdir -p "$STAGING" "$OUT_DIR"

"$POU" aggregate \
  --receipts "$RECEIPTS" \
  --project "$PROJECT" \
  --epoch "$EPOCH" \
  --attestor-key-file "$ATTESTOR_KEY" \
  --issuer-public-key "$ISSUER_PUB" \
  --out "$STAGING"

"$POU" verify-public "$STAGING/public-proof.json" --trusted-keys "$STAGING/trusted-keys.json"
"$POU" verify-audit "$STAGING/public-proof.json" "$STAGING/audit-pack.json" --trusted-keys "$STAGING/trusted-keys.json"

cp "$STAGING/public-proof.json" "$OUT_DIR/public-proof.json"
cp "$STAGING/audit-pack.json" "$OUT_DIR/audit-pack.json"

echo ""
echo "Published to $OUT_DIR/"
echo "Trusted keys (repo root): $TRUSTED_KEYS"
echo ""
echo "Anyone can verify:"
echo "  pou verify-public docs/proof/$EPOCH/public-proof.json --trusted-keys docs/proof/trusted-keys.json"
