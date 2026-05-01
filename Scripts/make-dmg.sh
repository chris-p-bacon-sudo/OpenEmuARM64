#!/usr/bin/env bash
# make-dmg.sh — Build the OpenEmu-Silicon styled DMG installer.
#
# Pipeline:
#   1. Render Scripts/dmg-assets/background.html → background.png via offscreen WebKit.
#      WebKit on a retina display takes a 2× snapshot, so the output PNG is 1920×1360
#      pixels tagged 144 DPI (Finder reads this as a 960×680 logical @2× retina image).
#
#   2. Run dmgbuild with Scripts/dmg-assets/dmgbuild_settings.py.
#      dmgbuild writes the .DS_Store binary directly via the mac_alias library —
#      it does not call AppleScript or Finder, so it is immune to the macOS 26
#      Finder/alias-bookmark regressions that broke earlier hdiutil+AppleScript
#      and appdmg approaches.
#
# Usage:
#   ./Scripts/make-dmg.sh <app-path> <output.dmg>

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
[ $# -ge 2 ] || die "Usage: $0 <app-path> <output.dmg>"

APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT="$2"
VOLNAME="OpenEmu-Silicon"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$SCRIPT_DIR/dmg-assets"
HTML="$ASSETS/background.html"
BG_PNG="$ASSETS/background.png"
SETTINGS="$ASSETS/dmgbuild_settings.py"
RENDERER="$SCRIPT_DIR/render-html-background.swift"

[ -d "$APP" ]      || die "App not found: $APP"
[ -f "$HTML" ]     || die "background.html not found: $HTML"
[ -f "$SETTINGS" ] || die "dmgbuild_settings.py not found: $SETTINGS"
[ -f "$RENDERER" ] || die "render-html-background.swift not found: $RENDERER"

# Find dmgbuild — pipx installs it under ~/.local/bin which may not be in PATH yet
DMGBUILD=""
if command -v dmgbuild &>/dev/null; then
    DMGBUILD="dmgbuild"
elif [ -x "$HOME/.local/bin/dmgbuild" ]; then
    DMGBUILD="$HOME/.local/bin/dmgbuild"
else
    die "dmgbuild not installed — run: pipx install dmgbuild  (or: pip3 install --user dmgbuild)"
fi

echo "=== make-dmg ==="
echo "  app:    $APP"
echo "  output: $OUTPUT"

# ── 1. Render HTML → PNG ──────────────────────────────────────────────────────
echo "--- 1/2  Rendering background.html → background.png (WebKit)"
swift "$RENDERER" "$HTML" "$BG_PNG"
[ -f "$BG_PNG" ] || die "Render failed — background.png not produced."

# ── 2. Build the DMG ──────────────────────────────────────────────────────────
echo "--- 2/2  Building DMG with dmgbuild"
mkdir -p "$(dirname "$OUTPUT")"

# dmgbuild fails if the output already exists — remove first
rm -f "$OUTPUT"

APP_PATH="$APP" BG_PATH="$BG_PNG" "$DMGBUILD" -s "$SETTINGS" "$VOLNAME" "$OUTPUT"

echo "=== make-dmg: done → $OUTPUT"
