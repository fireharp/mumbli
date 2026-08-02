#!/usr/bin/env bash
set -euo pipefail

# DEV FALLBACK: Issue a legacy usage credential for this Mac's Mumbli install.
# Normal flow uses embedded project-grant auto-enrollment in the app.
# Requires: pou CLI built from proof-of-use repo, issuer private key.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POU_REPO="${POU_REPO:-$HOME/Prog/Stuff/proof-of-use}"
ISSUER_KEY="${ISSUER_KEY:-$POU_REPO/keys/mumbli/issuer.json}"
PROJECT="github.com/fireharp/mumbli"
EPOCH="${EPOCH:-$(date -u +%Y-%m)}"
PROOF_DIR="$HOME/Library/Application Support/Mumbli/proof"
CREDENTIAL_OUT="$PROOF_DIR/credential.json"

POU="$POU_REPO/bin/pou"
if [[ ! -x "$POU" ]]; then
  echo "Building pou from $POU_REPO ..."
  (cd "$POU_REPO" && go build -o bin/pou ./cmd/pou)
fi

if [[ ! -f "$ISSUER_KEY" ]]; then
  echo "Issuer key not found at $ISSUER_KEY"
  echo "Generate with: pou keygen --out keys/mumbli/issuer.json"
  exit 1
fi

mkdir -p "$PROOF_DIR"

# Read install public key from Mumbli Keychain via a one-shot app launch, or from env.
if [[ -n "${INSTALL_PUBLIC_KEY:-}" ]]; then
  INSTALL_PUB="$INSTALL_PUBLIC_KEY"
else
  echo "Enable Usage Proof in Mumbli Settings first, then copy the install public key."
  echo "Or set INSTALL_PUBLIC_KEY=<base64url> and re-run."
  read -r -p "Install public key: " INSTALL_PUB
fi

if [[ -z "$INSTALL_PUB" ]]; then
  echo "Install public key is required."
  exit 1
fi

"$POU" issue-credential \
  --issuer-key-file "$ISSUER_KEY" \
  --install-public-key "$INSTALL_PUB" \
  --project "$PROJECT" \
  --epoch "$EPOCH" \
  --out "$CREDENTIAL_OUT"

echo "Wrote credential to $CREDENTIAL_OUT"
echo "Enable 'Sign dictation usage receipts' in Mumbli Settings if not already on."
