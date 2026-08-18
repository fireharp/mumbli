#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize and staple a DMG locally — the same sequence
# .github/workflows/release-please.yml runs, minus release-please and the
# provenance attestation (which only GitHub can produce).
#
# The point is to fail here instead of halfway through a published release.
# Notarization is the step that actually needs Apple to say yes, and finding
# out it doesn't after a tag exists is the expensive way to learn.
#
# Notarization credentials, in the order tried:
#   1. $ASC_KEY_PATH + $ASC_KEY_ID + $ASC_ISSUER_ID
#   2. --keychain-profile "$NOTARY_PROFILE" (see notarytool store-credentials)
#   3. skipped, with the Gatekeeper rejection shown so it is obvious why
#
# usage: scripts/release/build-signed-dmg.sh [version]

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

VERSION="${1:-$(sed -nE 's/^ *MARKETING_VERSION: "(.+)".*$/\1/p' project.yml | head -1)}"
[[ -n "$VERSION" ]] || { echo "could not determine version; pass one explicitly" >&2; exit 1; }

BUILD_DIR="build/local-release"
APP="$BUILD_DIR/Mumbli.app"
DMG="$BUILD_DIR/Mumbli-$VERSION.dmg"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')}"
if [[ -z "$IDENTITY" ]]; then
  echo "error: no 'Developer ID Application' identity in your keychain." >&2
  echo "See docs/for-developers/release-signing.mdx" >&2
  exit 1
fi
echo "==> Identity: $IDENTITY"

# The checked-in project is used as-is by default. Regenerating is opt-in
# because XcodeGen 2.45 writes objectVersion 77, which needs Xcode 16+ — the
# checked-in project is 56, and CI's macos-latest runner is new enough either
# way. On an Xcode 15 machine, regenerating produces a project the local
# xcodebuild cannot open at all.
if [[ -n "${REGENERATE:-}" ]]; then
  echo "==> Regenerating Xcode project"
  command -v xcodegen > /dev/null 2>&1 || { echo "xcodegen is required. brew install xcodegen" >&2; exit 1; }
  xcodegen generate
else
  echo "==> Using checked-in MumbliApp.xcodeproj (REGENERATE=1 to run xcodegen)"
fi

# Built unsigned, then signed explicitly below, so the hardened-runtime flags
# and entitlements are applied exactly once and in one place.
echo "==> Building Release archive"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project MumbliApp.xcodeproj \
  -scheme MumbliApp \
  -configuration Release \
  -archivePath "$BUILD_DIR/Mumbli.xcarchive" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  > "$BUILD_DIR/xcodebuild.log" 2>&1 \
  || { tail -40 "$BUILD_DIR/xcodebuild.log" >&2; echo "build failed; full log: $BUILD_DIR/xcodebuild.log" >&2; exit 1; }

cp -R "$BUILD_DIR/Mumbli.xcarchive/Products/Applications/Mumbli.app" "$BUILD_DIR/"

echo "==> Signing app"
codesign --force --timestamp --options runtime \
  --entitlements MumbliApp/MumbliApp.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
# -dvvv is required here: lower verbosity does not print CDHash at all.
codesign -dvvv "$APP" 2>&1 | grep -E '^Identifier|^TeamIdentifier|^CDHash|^Timestamp|flags='

# The Applications alias and the window layout both come from make-dmg.sh, which
# CI calls too — so the image opened here is laid out exactly like the published
# one rather than approximating it.
"$(dirname "${BASH_SOURCE[0]}")/make-dmg.sh" "$APP" "Mumbli" "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

NOTARIZED=false
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  echo "==> Notarizing (API key $ASC_KEY_ID)"
  xcrun notarytool submit "$DMG" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --timeout 30m
  NOTARIZED=true
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing (keychain profile $NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 30m
  NOTARIZED=true
else
  echo "==> Skipping notarization: no credentials in the environment."
  echo "    Set ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID, or NOTARY_PROFILE."
fi

if [[ "$NOTARIZED" == true ]]; then
  # Stapling rewrites the DMG, so the checksum below must come after it.
  echo "==> Stapling"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "==> Gatekeeper assessment"
if spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1; then
  echo "    ✓ accepted — this DMG opens with no warning on a clean Mac"
else
  echo "    ✗ rejected (see 'source=' above)."
  echo "      'Unnotarized Developer ID' means signing worked and only"
  echo "      notarization is missing."
fi

echo "==> $DMG"
shasum -a 256 "$DMG"
