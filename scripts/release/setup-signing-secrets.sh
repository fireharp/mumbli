#!/usr/bin/env bash
set -euo pipefail

# One-time setup of the GitHub Actions secrets that switch releases from ad-hoc
# signing to Developer ID (signed + notarized + Gatekeeper-clean).
#
# Run this yourself — it handles your signing certificate and your App Store
# Connect key, and neither should pass through anything but your own shell.
# Nothing is written to disk outside a temp dir that is wiped on exit, and no
# secret value is ever echoed.
#
# It sets, in fireharp/mumbli:
#   MACOS_CERTIFICATE       base64 of your Developer ID .p12
#   MACOS_CERTIFICATE_PWD   the .p12 export password
#   KEYCHAIN_PWD            random string, generated here, protects the CI keychain
#   APPLE_API_KEY           base64 of your App Store Connect .p8
#   APPLE_API_KEY_ID        the key id
#   APPLE_API_ISSUER        the issuer UUID
#
# See docs/for-developers/release-signing.mdx for where each value comes from.
#
# usage:
#   scripts/release/setup-signing-secrets.sh          # prompts for each value
#
#   # or supply any of them up front and only the rest is prompted for:
#   P12_PATH=~/Downloads/Certificates.p12 P12_PASSWORD=... \
#   ASC_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8 \
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<uuid> \
#     scripts/release/setup-signing-secrets.sh
#
# The environment form takes the same variable names as build-signed-dmg.sh, so
# one exported set of values drives both.

REPO="${REPO:-fireharp/mumbli}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

command -v gh > /dev/null 2>&1 || fail "gh (GitHub CLI) is required. brew install gh"
gh auth status > /dev/null 2>&1 || fail "gh is not authenticated. Run: gh auth login"

echo "==> Repository: $REPO"

# ---------------------------------------------------------------------------
# 1. Signing certificate
# ---------------------------------------------------------------------------
#
# The .p12 must contain a *Developer ID Application* identity with its private
# key. "Apple Development" certificates cannot notarize, so we check explicitly
# rather than letting CI fail 10 minutes into a release.

echo
echo "==> Developer ID certificate"

if [[ -z "${P12_PATH:-}" ]]; then
  echo "    Identities currently in your keychain:"
  security find-identity -v -p codesigning | sed 's/^/    /'
  echo
  echo "    Export the 'Developer ID Application' one from Keychain Access"
  echo "    (right-click the certificate -> Export -> .p12, set a password),"
  echo "    or point this at a .p12 you exported earlier."
  echo
  read -r -p "    Path to .p12: " P12_PATH
fi
P12_PATH="${P12_PATH/#\~/$HOME}"
[[ -f "$P12_PATH" ]] || fail "no such file: $P12_PATH"
echo "    Using $P12_PATH"

# P12_PASSWORD is the documented input name; P12_PWD is what the openssl calls
# below read from the environment.
P12_PWD="${P12_PASSWORD:-}"
if [[ -z "$P12_PWD" ]]; then
  read -r -s -p "    Password for that .p12: " P12_PWD
  echo
fi
[[ -n "$P12_PWD" ]] || fail "the .p12 password cannot be empty"
# Passed to openssl through the environment rather than argv, so it never shows
# up in ps output.
export P12_PWD

# -legacy first, then without: Keychain Access still writes RC2-encrypted bags
# that OpenSSL 3 only opens in legacy mode, while LibreSSL (/usr/bin/openssl)
# has no -legacy flag at all. Whichever the caller's PATH resolves to, one of
# the two works.
p12() {
  openssl pkcs12 -in "$P12_PATH" -legacy -passin env:P12_PWD "$@" 2> /dev/null \
    || openssl pkcs12 -in "$P12_PATH" -passin env:P12_PWD "$@" 2> /dev/null
}

# `-info` writes the bag listing to stderr, so this variant keeps it.
p12_info() {
  openssl pkcs12 -in "$P12_PATH" -info -nokeys -legacy -passin env:P12_PWD 2>&1 \
    || openssl pkcs12 -in "$P12_PATH" -info -nokeys -passin env:P12_PWD 2>&1
}

CERT_DUMP="$WORK_DIR/cert.txt"
p12 -nokeys > "$CERT_DUMP" || true
[[ -s "$CERT_DUMP" ]] \
  || fail "could not open the .p12 — wrong password, or not a PKCS#12 file"

grep -q "Developer ID Application" "$CERT_DUMP" \
  || fail "that .p12 has no 'Developer ID Application' certificate in it — notarization needs one"

echo "    ✓ $(grep -m1 "Developer ID Application" "$CERT_DUMP" | sed 's/^ *//')"

# A .p12 exported without its private key signs nothing, and CI would only find
# out after importing it. The keybag line from -info proves the key is in there;
# checking it this way never puts the key itself on stdout. (`-nocerts -noout`
# looks like the obvious test and is not one — it exits 0 on a cert-only .p12.)
if [[ "$(p12_info | grep -ci 'keybag' || true)" == "0" ]]; then
  fail "that .p12 contains no private key — re-export it including the key"
fi
echo "    ✓ private key present"

# Expiry, because a certificate that dies mid-quarter should be noticed now.
NOT_AFTER="$(p12 -nokeys | openssl x509 -noout -enddate 2> /dev/null | cut -d= -f2 || true)"
if [[ -n "$NOT_AFTER" ]]; then
  echo "    ✓ valid until $NOT_AFTER"
fi

# ---------------------------------------------------------------------------
# 2. Notarization credentials
# ---------------------------------------------------------------------------
#
# Verified against Apple *before* upload: notarytool history is a cheap
# authenticated round-trip, and a bad triple here is otherwise invisible until
# a release is already half-published.

echo
echo "==> App Store Connect API key (for notarization)"

P8_PATH="${ASC_KEY_PATH:-}"
if [[ -z "$P8_PATH" ]]; then
  echo "    Create one at appstoreconnect.apple.com/access/integrations/api with"
  echo "    the Developer role. The issuer id is the UUID above the key list."
  echo
  read -r -p "    Path to AuthKey_XXXXXXXXXX.p8: " P8_PATH
fi
P8_PATH="${P8_PATH/#\~/$HOME}"
[[ -f "$P8_PATH" ]] || fail "no such file: $P8_PATH"

# The key id is in the filename Apple gives you, so it rarely needs typing.
DEFAULT_KEY_ID="$(basename "$P8_PATH" | sed -nE 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/p')"
KEY_ID="${ASC_KEY_ID:-}"
if [[ -z "$KEY_ID" ]]; then
  if [[ -n "$DEFAULT_KEY_ID" ]]; then
    read -r -p "    Key ID [$DEFAULT_KEY_ID]: " KEY_ID
    KEY_ID="${KEY_ID:-$DEFAULT_KEY_ID}"
  else
    read -r -p "    Key ID: " KEY_ID
  fi
fi
[[ -n "$KEY_ID" ]] || fail "the key id cannot be empty"

ISSUER_ID="${ASC_ISSUER_ID:-}"
if [[ -z "$ISSUER_ID" ]]; then
  read -r -p "    Issuer ID (UUID): " ISSUER_ID
fi
[[ "$ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "the issuer id should be a 36-character UUID"
echo "    Using key $KEY_ID"

echo "    Checking the credentials against Apple ..."
if xcrun notarytool history --key "$P8_PATH" --key-id "$KEY_ID" --issuer "$ISSUER_ID" \
  > "$WORK_DIR/notary.txt" 2>&1; then
  echo "    ✓ Apple accepted the key"
else
  sed 's/^/    /' "$WORK_DIR/notary.txt" >&2
  fail "Apple rejected these notarization credentials — nothing was uploaded"
fi

# ---------------------------------------------------------------------------
# 3. Upload
# ---------------------------------------------------------------------------

echo
echo "==> Setting secrets in $REPO"

# MACOS_CERTIFICATE goes last on purpose: the workflow reads its presence as
# "use Developer ID mode". Setting it first would mean a failure partway
# through this block leaves the next release trying to notarize with
# credentials that were never uploaded.
printf '%s' "$P12_PWD" | gh secret set MACOS_CERTIFICATE_PWD --repo "$REPO"

# Only ever protects the throwaway keychain CI creates and deletes per run.
printf '%s' "$(openssl rand -hex 24)" | gh secret set KEYCHAIN_PWD --repo "$REPO"

base64 -i "$P8_PATH" | gh secret set APPLE_API_KEY --repo "$REPO"
printf '%s' "$KEY_ID" | gh secret set APPLE_API_KEY_ID --repo "$REPO"
printf '%s' "$ISSUER_ID" | gh secret set APPLE_API_ISSUER --repo "$REPO"

base64 -i "$P12_PATH" | gh secret set MACOS_CERTIFICATE --repo "$REPO"

echo
echo "==> Done. Secrets now in $REPO:"
gh secret list --repo "$REPO" | sed 's/^/    /'

cat << 'EOF'

Next:
  1. scripts/release/build-signed-dmg.sh     — signs + notarizes locally, end to end,
                                               without cutting a release
  2. merge the release workflow to main, then let release-please cut the next tag

The first Developer ID release changes the app's code signature, so existing
users must re-grant Accessibility permission once. Say so in the release notes.
EOF
