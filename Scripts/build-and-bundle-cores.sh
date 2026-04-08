#!/usr/bin/env bash
# build-and-bundle-cores.sh — Build all emulation cores in Release config,
# sign them, and bundle them into a .xcarchive ready for notarization.
#
# Usage:
#   ./Scripts/build-and-bundle-cores.sh                        # uses latest xcarchive
#   ./Scripts/build-and-bundle-cores.sh "path/to/archive.xcarchive"
#
# Environment variables:
#   CODE_SIGN_IDENTITY  Signing identity (default: "Developer ID Application")
#                       Set to "" to skip signing (local dev only).
#
# Entry format in CORES array:
#   "SchemeName|path/to/Project.xcodeproj"
#   "SchemeName|path/to/Project.xcodeproj|PluginName"   (when scheme name ≠ output plugin name)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$REPO_ROOT/OpenEmu-metal.xcworkspace"
DESTINATION='platform=macOS,arch=arm64'
SIGN_ID="${CODE_SIGN_IDENTITY:-Developer ID Application}"

die() { echo "ERROR: $*" >&2; exit 1; }

# ── 1. Find archive ───────────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
  ARCHIVE="$1"
else
  ARCHIVE=$(find "$HOME/Library/Developer/Xcode/Archives" -maxdepth 2 \
    -name "*.xcarchive" | sort | tail -1)
fi
[ -d "$ARCHIVE" ] || die "No .xcarchive found. Pass a path or run an Xcode archive first."
echo "Using archive: $ARCHIVE"

APP_IN_ARCHIVE=$(find "$ARCHIVE/Products" -name "OpenEmu.app" -maxdepth 4 | head -1)
[ -n "$APP_IN_ARCHIVE" ] || die "OpenEmu.app not found inside archive."

CORES_DIR="$APP_IN_ARCHIVE/Contents/PlugIns/Cores"
mkdir -p "$CORES_DIR"
echo "Cores will be staged to: $CORES_DIR"
echo ""

# ── 2. Build workspace first (produces OpenEmuBase + other frameworks) ────────
echo "Building OpenEmu workspace (Release) to produce frameworks..."
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme OpenEmu \
  -configuration Release \
  -destination "$DESTINATION" \
  build 2>&1 | tail -3
echo ""

# Re-resolve DERIVED_RELEASE after workspace build
DERIVED_RELEASE=$(find "$HOME/Library/Developer/Xcode/DerivedData/OpenEmu-metal-"* \
  -maxdepth 3 -name "Release" -path "*/Build/Products/Release" 2>/dev/null | head -1)
[ -n "$DERIVED_RELEASE" ] || die "Could not find Release build products after workspace build."
echo "Framework search path: $DERIVED_RELEASE"
echo ""

# ── 3. Core projects to build ─────────────────────────────────────────────────
# Format: "SchemeName|path/to/Project.xcodeproj[|PluginName]"
# PluginName is required when the scheme name differs from the output .oecoreplugin name.
# Reicast excluded (replaced by Flycast)
# Dolphin excluded (in-progress, not in this release)
# BSNES excluded (experimental)
CORES=(
  "4DO|4DO/4DO.xcodeproj"
  "Atari800|Atari800/Atari800.xcodeproj"
  "Bliss|Bliss/Bliss.xcodeproj"
  "CrabEmu|CrabEmu/CrabEmu.xcodeproj"
  "DeSmuME (OpenEmu Plug-in)|DeSmuME/src/cocoa/DeSmuME (Latest).xcodeproj|DeSmuME"
  "FCEU|FCEU/FCEU.xcodeproj"
  "Flycast|Flycast/Flycast.xcodeproj"
  "Gambatte|Gambatte/Gambatte.xcodeproj"
  "GenesisPlus|GenesisPlus/GenesisPlus.xcodeproj"
  "JollyCV|JollyCV/JollyCV.xcodeproj"
  "Mednafen|Mednafen/Mednafen.xcodeproj"
  "Mupen64Plus|Mupen64Plus/Mupen64Plus.xcodeproj"
  "Nestopia|Nestopia/Nestopia.xcodeproj"
  "O2EM|O2EM/O2EM.xcodeproj"
  "PokeMini|PokeMini/PokeMini.xcodeproj"
  "Potator|Potator-Core/Potator.xcodeproj"
  "ProSystem|ProSystem/ProSystem.xcodeproj"
  "SNES9x|SNES9x/SNES9x.xcodeproj"
  "Stella|Stella/Stella.xcodeproj"
  "VecXGL|VecXGL/VecXGL.xcodeproj"
  "VirtualJaguar|VirtualJaguar/VirtualJaguar.xcodeproj"
  "blueMSX|blueMSX/blueMSX.xcodeproj"
  "mGBA|mGBA/mGBA.xcodeproj"
  "Picodrive|picodrive/Picodrive.xcodeproj"
  "PPSSPP|PPSSPP/PPSSPP-Core/PPSSPP.xcodeproj"
)

TOTAL=${#CORES[@]}
IDX=0
BUILT=0
FAILED=()

# ── 4. Build each core ────────────────────────────────────────────────────────
for entry in "${CORES[@]}"; do
  IDX=$((IDX+1))

  # Parse entry: SchemeName | ProjectPath [| PluginName]
  SCHEME="${entry%%|*}"
  rest="${entry#*|}"
  PROJ_REL="${rest%%|*}"
  PLUGIN_NAME_FIELD="${rest#*|}"
  # If no 3rd field, PLUGIN_NAME_FIELD == PROJ_REL (no second | was present)
  if [ "$PLUGIN_NAME_FIELD" = "$rest" ]; then
    PLUGIN_NAME="$SCHEME"
  else
    PLUGIN_NAME="$PLUGIN_NAME_FIELD"
  fi

  PROJ="$REPO_ROOT/$PROJ_REL"

  echo "━━━ [$IDX/$TOTAL] Building $SCHEME ━━━"

  if [ ! -d "$PROJ" ]; then
    echo "  SKIP: project not found at $PROJ"
    FAILED+=("$SCHEME (project missing)")
    continue
  fi

  if xcodebuild \
      -project "$PROJ" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination "$DESTINATION" \
      ONLY_ACTIVE_ARCH=YES \
      FRAMEWORK_SEARCH_PATHS="$DERIVED_RELEASE" \
      build \
      2>&1 | tail -5; then
    BUILT=$((BUILT+1))
  else
    echo "  FAILED: $SCHEME build failed"
    FAILED+=("$SCHEME (build error)")
    continue
  fi

  # Find the built plugin — look in the shared DerivedData Release dir first,
  # then do a broader search as fallback
  PLUGIN=$(find "$DERIVED_RELEASE" -maxdepth 1 -name "${PLUGIN_NAME}.oecoreplugin" 2>/dev/null | head -1)
  if [ -z "$PLUGIN" ]; then
    PLUGIN=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
      -name "${PLUGIN_NAME}.oecoreplugin" \
      -not -path "*.dSYM*" \
      -not -path "*/Index.noindex/*" \
      2>/dev/null | sort | tail -1)
  fi

  if [ -z "$PLUGIN" ]; then
    echo "  WARNING: built but .oecoreplugin not found for $PLUGIN_NAME"
    FAILED+=("$SCHEME (plugin not found after build)")
    continue
  fi

  echo "  Staging: $PLUGIN → Cores/"
  rm -rf "$CORES_DIR/${PLUGIN_NAME}.oecoreplugin"
  cp -R "$PLUGIN" "$CORES_DIR/"

  # Sign the staged core with Developer ID + hardened runtime
  if [ -n "$SIGN_ID" ]; then
    echo "  Signing: $PLUGIN_NAME"
    if codesign --force --sign "$SIGN_ID" \
        --options runtime --timestamp \
        "$CORES_DIR/${PLUGIN_NAME}.oecoreplugin" 2>&1; then
      echo "  Signed OK"
    else
      echo "  WARNING: codesign failed for $PLUGIN_NAME"
      FAILED+=("$SCHEME (codesign failed)")
    fi
  else
    echo "  Skipping signing (CODE_SIGN_IDENTITY is empty)"
  fi

  echo ""
done

# ── 5. Re-sign the main app to incorporate new bundle contents ────────────────
if [ -n "$SIGN_ID" ]; then
  echo "Re-signing app bundle to incorporate bundled cores..."
  codesign --force --sign "$SIGN_ID" \
    --options runtime --timestamp --deep \
    "$APP_IN_ARCHIVE" 2>&1
  echo "App re-signed."
  echo ""
fi

# ── 6. Summary ────────────────────────────────────────────────────────────────
echo "=============================="
echo "  Build summary"
echo "=============================="
STAGED=$(find "$CORES_DIR" -maxdepth 1 -name "*.oecoreplugin" | wc -l | tr -d ' ')
echo "  Cores staged in archive: $STAGED / $TOTAL"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "  Failed / skipped:"
  for f in "${FAILED[@]}"; do
    echo "    - $f"
  done
fi

echo ""
echo "=============================="
if [ "$STAGED" -eq 0 ]; then
  die "No cores were staged. Check build errors above."
fi

echo "Done. Archive is ready for notarization:"
echo "  $ARCHIVE"
