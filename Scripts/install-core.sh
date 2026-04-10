#!/bin/bash
#
# install-core.sh — install a built core plugin into the OE cores directory
#
# Usage:
#   ./Scripts/install-core.sh <CoreName>
#
# Example:
#   ./Scripts/install-core.sh Dolphin
#   ./Scripts/install-core.sh Flycast
#
# Why this script exists:
#   - cp -Rf on an existing .oecoreplugin bundle silently skips files that
#     already exist at the destination — the old binary stays in place.
#   - If OpenEmu is running, the helper process holds the binary open and
#     cp will silently fail to replace it.
#   This script quits OpenEmu first, then copies the binary and Info.plist
#   individually with -f so the destination is always fully updated.

set -euo pipefail

CORE="${1:?Usage: $0 <CoreName> (e.g. Dolphin, Flycast)}"
DEST="$HOME/Library/Application Support/OpenEmu/Cores/${CORE}.oecoreplugin"
DERIVED=$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenEmu-metal-"*/Build/Products/Debug/"${CORE}.oecoreplugin" 2>/dev/null | head -1)

if [ -z "$DERIVED" ]; then
  echo "error: ${CORE}.oecoreplugin not found in DerivedData."
  echo "       Build the '${CORE}' scheme first:"
  echo "       xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme ${CORE} \\"
  echo "         -configuration Debug -destination 'platform=macOS,arch=arm64' build"
  exit 1
fi

if [ ! -d "$DEST" ]; then
  echo "error: ${CORE}.oecoreplugin not found at:"
  echo "       $DEST"
  echo "       Is the core installed? Launch OpenEmu once to install it."
  exit 1
fi

if pgrep -xq "OpenEmu"; then
  echo "Quitting OpenEmu..."
  osascript -e 'tell application "OpenEmu" to quit'
  sleep 2
  if pgrep -xq "OpenEmu"; then
    echo "error: OpenEmu is still running. Quit it manually and try again."
    exit 1
  fi
fi

echo "Installing ${CORE}.oecoreplugin from DerivedData..."
cp -f "${DERIVED}/Contents/MacOS/${CORE}" "${DEST}/Contents/MacOS/${CORE}"
cp -f "${DERIVED}/Contents/Info.plist"    "${DEST}/Contents/Info.plist"

INSTALLED_DATE=$(stat -f "%Sm" -t "%b %d %H:%M" "${DEST}/Contents/MacOS/${CORE}")
echo "Done. Binary timestamp: ${INSTALLED_DATE}"
