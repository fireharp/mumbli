#!/usr/bin/env bash
set -euo pipefail

# Aggregate local Mumbli receipts, verify, and write publishable proof artifacts.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
ATTESTOR_KEY="${ATTESTOR_KEY:-$POU_REPO/keys/mumbli/attestor.json}"
TRUSTED_KEYS="$MAC_APP_DIR/docs/proof/trusted-keys.json"
REGISTRY="${REGISTRY:-$POU_REPO/ProofOfUseLocal/registry/grant-registry.json}"
ALLOWLIST="${ALLOWLIST:-$POU_REPO/ProofOfUseLocal/allowlist/mumbli.json}"
RECEIPTS="${RECEIPTS:-$HOME/Library/Application Support/Mumbli/proof/receipts.jsonl}"
PROJECT="github.com/fireharp/mumbli"
EPOCH="${EPOCH:-$(date -u +%Y-%m)}"
BINDINGS_DIR="$MAC_APP_DIR/docs/proof/releases"
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

# receipts.jsonl is append-only across months, so scope verification to the epoch
# being published. Without this, publishing would also re-verify every earlier
# epoch in the file and fail loudly if the epoch being published has no receipts.
VERIFY_FLAGS=(--epoch "$EPOCH" --trusted-keys "$TRUSTED_KEYS" --grant-policy optimistic)
if [[ -f "$REGISTRY" ]]; then
  VERIFY_FLAGS+=(--grant-registry "$REGISTRY")
fi
if [[ -f "$ALLOWLIST" ]]; then
  VERIFY_FLAGS+=(--allowlist "$ALLOWLIST")
fi

# Every signed release binding is fed to the verifier, which then requires each
# grant-backed receipt to carry the app_identity of the artifact actually shipped
# for its grant. Without bindings the verifier keeps its old, weaker behaviour.
BINDING_FLAGS=()
while IFS= read -r binding; do
  BINDING_FLAGS+=(--release-binding "$binding")
done < <(find "$BINDINGS_DIR" -name 'release-binding.json' 2>/dev/null | sort)
if [[ ${#BINDING_FLAGS[@]} -eq 0 ]]; then
  echo "Note: no release bindings under $BINDINGS_DIR — receipts will not be checked"
  echo "      against a released artifact. Run scripts/proof/issue-release-binding.sh <tag>."
else
  echo "Using ${#BINDING_FLAGS[@]} release binding(s) from $BINDINGS_DIR"
  VERIFY_FLAGS+=("${BINDING_FLAGS[@]}")
fi

rm -rf "$STAGING"
mkdir -p "$STAGING" "$OUT_DIR"

"$POU" verify-receipts --receipts "$RECEIPTS" "${VERIFY_FLAGS[@]}"

"$POU" aggregate \
  --receipts "$RECEIPTS" \
  --project "$PROJECT" \
  --epoch "$EPOCH" \
  --attestor-key-file "$ATTESTOR_KEY" \
  --issuer-public-key "$ISSUER_PUB" \
  --out "$STAGING"

AUDIT_FLAGS=(--trusted-keys "$STAGING/trusted-keys.json" --grant-policy optimistic)
if [[ -f "$REGISTRY" ]]; then
  AUDIT_FLAGS+=(--grant-registry "$REGISTRY")
fi
if [[ -f "$ALLOWLIST" ]]; then
  AUDIT_FLAGS+=(--allowlist "$ALLOWLIST")
fi
if [[ ${#BINDING_FLAGS[@]} -gt 0 ]]; then
  AUDIT_FLAGS+=("${BINDING_FLAGS[@]}")
fi

"$POU" verify-public "$STAGING/public-proof.json" --trusted-keys "$STAGING/trusted-keys.json"
"$POU" verify-audit "$STAGING/public-proof.json" "$STAGING/audit-pack.json" "${AUDIT_FLAGS[@]}"

cp "$STAGING/public-proof.json" "$OUT_DIR/public-proof.json"
cp "$STAGING/audit-pack.json" "$OUT_DIR/audit-pack.json"

echo ""
echo "Published to $OUT_DIR/"
echo "Trusted keys (repo root): $TRUSTED_KEYS"
echo ""
echo "Anyone can verify:"
echo "  pou verify-public docs/proof/$EPOCH/public-proof.json --trusted-keys docs/proof/trusted-keys.json"
