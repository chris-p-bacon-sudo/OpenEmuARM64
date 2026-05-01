#!/usr/bin/env bash
# make-dmg.sh — Build the OpenEmu-Silicon styled DMG installer.
#
# Pipeline:
#   1. Render Scripts/dmg-assets/background.html → background.png via offscreen WebKit
#   2. Inject the app path into appdmg.json
#   3. Run appdmg to produce the final UDZO DMG with correct background + icon positions
#
# Usage:
#   ./Scripts/make-dmg.sh <app-path> <output.dmg>

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
[ $# -ge 2 ] || die "Usage: $0 <app-path> <output.dmg>"

APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/dmg-assets"
HTML="$ASSETS/background.html"
BG_PNG="$ASSETS/background.png"
APPDMG_TEMPLATE="$ASSETS/appdmg.json"
RENDERER="$SCRIPT_DIR/render-html-background.swift"

[ -d "$APP" ]              || die "App not found: $APP"
[ -f "$HTML" ]             || die "background.html not found: $HTML"
[ -f "$APPDMG_TEMPLATE" ]  || die "appdmg.json not found: $APPDMG_TEMPLATE"
[ -f "$RENDERER" ]         || die "render-html-background.swift not found: $RENDERER"
command -v appdmg &>/dev/null || die "appdmg not found — install with: npm install -g appdmg"

echo "=== make-dmg ==="
echo "  app:    $APP"
echo "  output: $OUTPUT"

# ── 1. Render HTML → PNG ──────────────────────────────────────────────────────
echo "--- 1/3  Rendering background.html → background.png (WebKit)"
swift "$RENDERER" "$HTML" "$BG_PNG"
[ -f "$BG_PNG" ] || die "Render failed — background.png not produced."

# ── 2. Build appdmg.json with the real app path ───────────────────────────────
echo "--- 2/3  Building appdmg config"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

WORK_JSON="$WORK_DIR/appdmg.json"
# Replace the {{APP_PATH}} placeholder and point background to the absolute PNG path
sed \
    -e "s|{{APP_PATH}}|$APP|g" \
    -e "s|\"background\": \"background.png\"|\"background\": \"$BG_PNG\"|g" \
    "$APPDMG_TEMPLATE" > "$WORK_JSON"

# ── 3. Run appdmg ────────────────────────────────────────────────────────────
echo "--- 3/3  Running appdmg"
mkdir -p "$(dirname "$OUTPUT")"
appdmg "$WORK_JSON" "$OUTPUT"

echo "=== make-dmg: done → $OUTPUT"
