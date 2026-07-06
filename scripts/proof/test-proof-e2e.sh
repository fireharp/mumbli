#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
RECEIPTS="${RECEIPTS:-$HOME/Library/Application Support/Mumbli/proof/receipts.jsonl}"
REGISTRY="${REGISTRY:-$POU_REPO/ProofOfUseLocal/registry/grant-registry.json}"

echo "== Canonical JSON (Swift) =="
swift "$SCRIPT_DIR/test-canonical.swift"

echo ""
echo "== proof-of-use Go tests =="
(cd "$POU_REPO" && make smoke)

echo ""
echo "== Grant verify (embedded dev grant) =="
POU="$POU_REPO/bin/pou"
[[ -x "$POU" ]] || (cd "$POU_REPO" && go build -o bin/pou ./cmd/pou)
"$POU" verify-grant "$MAC_APP_DIR/MumbliApp/ProofOfUse/project-grant.json" \
  --trusted-keys "$MAC_APP_DIR/docs/proof/trusted-keys.json"

echo ""
echo "== Receipt file check =="
if [[ -f "$RECEIPTS" ]]; then
  count=$(grep -c . "$RECEIPTS" || true)
  echo "Local receipts: $count"
  if [[ "$count" -gt 0 ]]; then
    echo "== Verify receipts + aggregate =="
    VERIFY_FLAGS=(--trusted-keys "$MAC_APP_DIR/docs/proof/trusted-keys.json" --grant-policy optimistic)
    if [[ -f "$REGISTRY" ]]; then
      VERIFY_FLAGS+=(--grant-registry "$REGISTRY")
    fi
    "$POU" verify-receipts --receipts "$RECEIPTS" "${VERIFY_FLAGS[@]}"
    STAGING=$(mktemp -d)
    ISSUER_PUB=$(python3 -c "import json; print(json.load(open('$MAC_APP_DIR/docs/proof/trusted-keys.json'))['issuer_public_key'])")
    "$POU" aggregate \
      --receipts "$RECEIPTS" \
      --project github.com/fireharp/mumbli \
      --epoch 2026-07 \
      --attestor-key-file "$POU_REPO/keys/mumbli/attestor.json" \
      --issuer-public-key "$ISSUER_PUB" \
      --out "$STAGING"
    "$POU" verify-audit "$STAGING/public-proof.json" "$STAGING/audit-pack.json" \
      --trusted-keys "$STAGING/trusted-keys.json" \
      --grant-policy optimistic \
      $([[ -f "$REGISTRY" ]] && echo --grant-registry "$REGISTRY")
    rm -rf "$STAGING"
    echo "OK  aggregate + verify passed"
  fi
else
  echo "No local receipts yet (dictate with proof enabled to create $RECEIPTS)"
fi

echo ""
echo "All proof e2e checks passed"
