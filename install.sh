#!/bin/bash
set -euo pipefail

REPO="fireharp/mumbli"
APP_NAME="Mumbli.app"
INSTALL_DIR="/Applications"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}==>${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

# Check macOS
[[ "$(uname)" == "Darwin" ]] || error "Mumbli is a macOS app. This script only works on macOS."

# Check for existing installation
if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
    if [[ "${1:-}" == "--force" ]] || [[ ! -t 0 ]]; then
        info "Removing existing installation..."
        rm -rf "$INSTALL_DIR/$APP_NAME"
    else
        echo "Mumbli is already installed at $INSTALL_DIR/$APP_NAME"
        read -rp "Overwrite? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR/$APP_NAME"
        else
            echo "Aborted."
            exit 0
        fi
    fi
fi

# Get latest release
info "Fetching latest release..."
RELEASE_URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' \
    | head -1 \
    | cut -d'"' -f4) || error "Failed to fetch release info. Check your internet connection."

[[ -n "$RELEASE_URL" ]] || error "No DMG found in latest release."

# Download
TMPDIR_PATH=$(mktemp -d)
DMG_PATH="$TMPDIR_PATH/Mumbli.dmg"
trap 'rm -rf "$TMPDIR_PATH"' EXIT

info "Downloading $(basename "$RELEASE_URL")..."
curl -fSL --progress-bar -o "$DMG_PATH" "$RELEASE_URL" || error "Download failed."

# Mount DMG
info "Mounting disk image..."
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>/dev/null | grep '/Volumes/' | sed 's/.*\/Volumes/\/Volumes/')
[[ -n "$MOUNT_POINT" ]] || error "Failed to mount DMG."

# Copy app
info "Installing to $INSTALL_DIR..."
cp -R "$MOUNT_POINT/$APP_NAME" "$INSTALL_DIR/" || error "Failed to copy app. Try: sudo bash install.sh"

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

# Strip quarantine
info "Clearing quarantine attribute..."
xattr -cr "$INSTALL_DIR/$APP_NAME"

success "Mumbli installed successfully!"
echo ""
echo "Open Mumbli from your Applications folder or run:"
echo "  open /Applications/Mumbli.app"
