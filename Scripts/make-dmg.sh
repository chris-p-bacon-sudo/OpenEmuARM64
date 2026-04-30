#!/usr/bin/env bash
# make-dmg.sh — Create a styled DMG installer with custom background and icon layout.
#
# Usage:
#   ./Scripts/make-dmg.sh <app-path> <output.dmg>
#
# What it does:
#   1. Creates a temporary read-write disk image
#   2. Copies the app and a /Applications symlink into it
#   3. Installs the custom background image (dmg-assets/dmg-background.png)
#   4. Uses Finder/AppleScript to set window appearance and icon positions
#   5. Compresses the result into the final UDZO DMG
#
# Requirements:
#   - Finder must be running (true on any interactive macOS session or CI runner)
#   - Scripts/dmg-assets/dmg-background.png must exist (run generate-dmg-bg.swift once)

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
[ $# -ge 2 ] || die "Usage: $0 <app-path> <output.dmg>"

APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT="$2"
VOLNAME="OpenEmu-Silicon"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BG_SRC="$SCRIPT_DIR/dmg-assets/dmg-background.png"

[ -d "$APP" ]    || die "App not found: $APP"
[ -f "$BG_SRC" ] || die "Background PNG not found: $BG_SRC (run: swift Scripts/generate-dmg-bg.swift Scripts/dmg-assets/dmg-background.png)"

# ── Workspace ─────────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

STAGING_DMG="$WORK_DIR/staging.dmg"
MOUNT_POINT="$WORK_DIR/mount"
mkdir -p "$MOUNT_POINT"

echo "=== make-dmg: creating styled DMG ==="
echo "  app:    $APP"
echo "  output: $OUTPUT"

# ── 1. Create a scratch read-write disk image ─────────────────────────────────
echo "--- 1/5  Creating scratch RW image"
hdiutil create \
    -size 600m \
    -volname "$VOLNAME" \
    -fs HFS+ \
    "$STAGING_DMG" \
    > /dev/null

# ── 2. Mount it ───────────────────────────────────────────────────────────────
echo "--- 2/5  Mounting"
ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$STAGING_DMG")
DEV=$(echo "$ATTACH_OUT" | grep -E '^/dev/disk' | head -1 | awk '{print $1}')
# Get the actual mount point from hdiutil output (handles name collisions like "OpenEmu-Silicon 1")
VOLUME=$(echo "$ATTACH_OUT" | grep -E '/Volumes/' | tail -1 | sed 's|.*\(/Volumes/[^\t]*\)|\1|' | tr -d '[:space:]' || true)
[ -n "$VOLUME" ] || VOLUME="/Volumes/$VOLNAME"

echo "  device:  $DEV"
echo "  volume:  $VOLUME"

# Derive the actual volume name from the mount point (needed for AppleScript)
ACTUAL_VOLNAME=$(basename "$VOLUME")

# Give Finder a moment to register the mount
sleep 1

# ── 3. Populate the volume ────────────────────────────────────────────────────
echo "--- 3/5  Populating volume"

# App bundle
ditto "$APP" "$VOLUME/OpenEmu.app"

# Applications symlink — users drag the icon here to install
ln -s /Applications "$VOLUME/Applications"

# Background — hidden folder so Finder uses it as the window background
mkdir -p "$VOLUME/.background"
cp "$BG_SRC" "$VOLUME/.background/background.png"

# Ensure Finder can read but users don't stumble on the hidden folder
SetFile -a V "$VOLUME/.background" 2>/dev/null || true

sync

# ── 4. Configure window appearance via AppleScript ────────────────────────────
echo "--- 4/5  Configuring Finder window (AppleScript)"

# Ensure Finder is running
open -a Finder 2>/dev/null || true
sleep 2

osascript <<APPLESCRIPT
tell application "Finder"
    -- Open the DMG window
    tell disk "$ACTUAL_VOLNAME"
        open

        -- Window chrome
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false

        -- Window size: 660 × 420 (positioned roughly centred on a 1440-wide screen)
        set the bounds of container window to {390, 150, 1050, 570}

        -- Icon view options
        set theViewOpts to icon view options of container window
        set arrangement of theViewOpts to not arranged
        set icon size of theViewOpts to 120
        set text size of theViewOpts to 12
        set label position of theViewOpts to bottom

        -- Custom background
        set background picture of theViewOpts to file ".background:background.png"

        -- Icon positions (top-left of icon bounding box, window-relative)
        -- 120px icons, centred at x=175 and x=485 horizontally
        -- 660px window → left icon left-edge ≈ 115, right icon left-edge ≈ 425
        set position of item "OpenEmu.app"  of container window to {115, 160}
        set position of item "Applications" of container window to {425, 160}

        -- Flush changes to .DS_Store on the volume
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 1

# ── 5. Eject and convert to compressed DMG ────────────────────────────────────
echo "--- 5/5  Compressing to UDZO"

hdiutil detach "$DEV" -quiet 2>/dev/null || hdiutil detach "$VOLUME" -quiet 2>/dev/null || true
sleep 1

mkdir -p "$(dirname "$OUTPUT")"
hdiutil convert "$STAGING_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT" \
    > /dev/null

echo "=== make-dmg: done → $OUTPUT"
