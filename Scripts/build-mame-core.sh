#!/usr/bin/env bash
# Build the OpenEmu-Silicon MAME core from source.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MAME_DIR="$REPO_ROOT/MAME"
DD="$MAME_DIR/build/XcodeDerived"

"$SCRIPT_DIR/prepare-mame-core.sh"

cd "$MAME_DIR/deps/mame"
make NOWERROR=1 REGENIE=1 macosx_arm64_clang \
  OSD="headless" verbose=1 TARGETOS="macosx" CONFIG="release" \
  TARGET=mame SUBTARGET=arcade MACOSX_DEPLOYMENT_TARGET=11.0 \
  -j"$(sysctl -n hw.ncpu)"

install_name_tool -id mamearcade_headless.dylib mamearcade_headless.dylib

xcodebuild \
  -project "$REPO_ROOT/OpenEmu-SDK/OpenEmu-SDK.xcodeproj" \
  -scheme OpenEmuBase \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build

xcodebuild \
  -project "$MAME_DIR/MAME.xcodeproj" \
  -scheme MAME \
  -configuration Release \
  -derivedDataPath "$DD" \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  build

PLUGIN="$DD/Build/Products/Release/MAME.oecoreplugin"

echo ""
echo "Built: $PLUGIN"
file "$PLUGIN/Contents/MacOS/MAME"
file "$PLUGIN/Contents/Frameworks/mamearcade_headless.dylib"
