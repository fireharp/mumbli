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
echo "== Epoch is UTC and matches the shell (Swift) =="
# Compiles the real ProofOfUseConfig so this catches a regression to a hardcoded
# constant or to local time. Local time would shift epoch boundaries per user and
# desync clients from the publish scripts, which derive the epoch with `date -u`.
EPOCH_TMP=$(mktemp -d)
trap 'rm -rf "$EPOCH_TMP"' EXIT
printf 'import Foundation\nprint(ProofOfUseConfig.epoch)\n' > "$EPOCH_TMP/main.swift"
swiftc -O "$MAC_APP_DIR/MumbliApp/ProofOfUse/ProofOfUseConfig.swift" \
  "$EPOCH_TMP/main.swift" -o "$EPOCH_TMP/epochcheck"
swift_epoch="$("$EPOCH_TMP/epochcheck")"
shell_epoch="$(date -u +%Y-%m)"
if [[ "$swift_epoch" != "$shell_epoch" ]]; then
  echo "FAIL  Swift epoch '$swift_epoch' != shell '$shell_epoch'"
  exit 1
fi
for tz in Pacific/Kiritimati Pacific/Midway; do
  tz_epoch="$(TZ="$tz" "$EPOCH_TMP/epochcheck")"
  if [[ "$tz_epoch" != "$shell_epoch" ]]; then
    echo "FAIL  epoch is local-time dependent: $tz gave '$tz_epoch', expected '$shell_epoch'"
    exit 1
  fi
done
echo "OK  epoch $swift_epoch (UTC-stable across TZ ±14h)"

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
    # Aggregate the newest epoch actually present rather than the current month:
    # a dev machine's receipts file is append-only and often has nothing for the
    # month you happen to run this in.
    agg_epoch="${EPOCH:-$(python3 -c "
import json,sys
epochs={json.loads(l)['receipt']['body']['epoch'] for l in open(sys.argv[1]) if l.strip()}
print(max(epochs))
" "$RECEIPTS")}"
    echo "Aggregating epoch $agg_epoch"
    "$POU" aggregate \
      --receipts "$RECEIPTS" \
      --project github.com/fireharp/mumbli \
      --epoch "$agg_epoch" \
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
