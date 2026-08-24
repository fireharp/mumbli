#!/usr/bin/env bash
set -euo pipefail

# Stamps the built app's Info.plist with the release version and the git commit
# it was actually built from.
#
# The release version lives in exactly one place — MARKETING_VERSION in
# project.yml, which release-please bumps. The checked-in Xcode project carries
# its own copy of that setting and drifts (it is only refreshed when someone
# runs xcodegen), which is why the About pane used to show a version several
# releases old. Reading project.yml here makes the drift invisible.
#
# Between releases the version alone is a lie in the other direction: main is
# usually N commits past the last tag. So the commit and the distance from the
# tag go in alongside it, and the UI shows them.
#
# Runs as a build phase scheduled after Xcode processes Info.plist, which means
# after Xcode has already signed the bundle — so the phase re-signs whatever it
# stamped. Release builds sign later and externally (see
# scripts/release/build-signed-dmg.sh), where CODE_SIGNING_ALLOWED is NO and
# this step does nothing.
#
# Also runnable by hand:
#
#   scripts/version-stamp.sh --print

SRCROOT="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$SRCROOT"

version="$(sed -nE 's/^ *MARKETING_VERSION: "(.+)".*$/\1/p' project.yml | head -1)"
[[ -n "$version" ]] || { echo "error: no MARKETING_VERSION in project.yml" >&2; exit 1; }

git() { command git -C "$SRCROOT" "$@"; }
in_git_repo() { git rev-parse --git-dir > /dev/null 2>&1; }

commit="unknown"
describe="v$version-nogit"
ahead="0"
state="unknown"
build="1"   # CFBundleVersion must be a positive number

if in_git_repo; then
  commit="$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
  describe="$(git describe --tags --always --dirty 2>/dev/null || echo "g$commit")"
  build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
  # CI sets this right after checkout, before "xcodegen generate" gets a chance
  # to rewrite project.pbxproj — which it always does (it writes objectVersion 77
  # no matter what project.yml asks for). Checking git diff here, after xcodegen
  # has already run, would see that self-inflicted change and call every release
  # build dirty, including ones built from a pristine tag. Local/interactive runs
  # have no such variable and fall back to the live check, which is meaningful
  # there since nothing upstream has touched the tree.
  if [[ -n "${MUMBLI_SOURCE_STATE:-}" ]]; then
    state="$MUMBLI_SOURCE_STATE"
  elif git diff --quiet HEAD 2>/dev/null; then
    state="clean"
  else
    state="dirty"
  fi
  # Distance from the tag matching the release version. A shallow clone (CI's
  # default checkout) has no tags, so this stays 0 rather than guessing.
  if git rev-parse -q --verify "refs/tags/v$version" > /dev/null 2>&1; then
    ahead="$(git rev-list --count "v$version..HEAD" 2>/dev/null || echo 0)"
  fi
elif [[ -n "${GITHUB_SHA:-}" ]]; then
  commit="${GITHUB_SHA:0:7}"
  describe="g$commit"
  state="clean"
fi

# What a human should read back to us in a bug report.
display="$version"
[[ "$ahead" != "0" ]] && display="$display+$ahead.g$commit"
[[ "$state" == "dirty" ]] && display="$display.dirty"

if [[ "${1:-}" == "--print" ]]; then
  printf 'version   %s\ncommit    %s\ndescribe  %s\nahead     %s\nstate     %s\nbuild     %s\ndisplay   %s\n' \
    "$version" "$commit" "$describe" "$ahead" "$state" "$build" "$display"
  exit 0
fi

plist="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
if [[ ! -f "$plist" ]]; then
  echo "warning: no built Info.plist at '$plist' — nothing stamped" >&2
  exit 0
fi

set_key() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$plist" 2> /dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$plist"
}

# CFBundleShortVersionString stays a plain release version — notarization and
# Sparkle-style comparisons both want it that way. The provenance goes in
# Mumbli* keys next to it.
set_key CFBundleShortVersionString "$version"
set_key CFBundleVersion "${build:-1}"
set_key MumbliVersionDisplay "$display"
set_key MumbliGitCommit "$commit"
set_key MumbliGitDescribe "$describe"
set_key MumbliCommitsSinceTag "$ahead"
set_key MumbliSourceState "$state"

# Editing a plist inside a signed bundle breaks the seal, and a broken seal
# means the proof-of-use module cannot read a valid signature. Put it back.
bundle="${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}"
if [[ "${CODE_SIGNING_ALLOWED:-NO}" == "YES" && -d "$bundle/Contents/_CodeSignature" ]]; then
  identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
  args=(--force --sign "${identity:--}")
  # Re-signing without entitlements would silently strip microphone and network
  # access. Xcode's compiled .xcent is the exact input it used; the source
  # entitlements file is the fallback when this runs outside a build.
  xcent="${TARGET_TEMP_DIR:-}/${PRODUCT_NAME:-}.app.xcent"
  [[ -f "$xcent" ]] || xcent="${CODE_SIGN_ENTITLEMENTS:+$SRCROOT/$CODE_SIGN_ENTITLEMENTS}"
  [[ -f "$xcent" ]] || xcent="$SRCROOT/MumbliApp/MumbliApp.entitlements"
  [[ -f "$xcent" ]] && args+=(--entitlements "$xcent" --generate-entitlement-der)
  [[ "${ENABLE_HARDENED_RUNTIME:-NO}" == "YES" ]] && args+=(--options runtime)
  # A timestamp needs Apple's server; ad-hoc signatures cannot carry one anyway.
  if [[ "$identity" == "-" ]]; then args+=(--timestamp=none); else args+=(--timestamp); fi
  codesign "${args[@]}" "$bundle"
  codesign --verify --strict "$bundle" \
    || { echo "error: re-signing after the version stamp failed" >&2; exit 1; }
  echo "note: re-signed after stamping ($identity)"
fi

echo "note: stamped $display ($describe)"
