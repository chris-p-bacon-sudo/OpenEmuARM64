#!/usr/bin/env bash
# One-shot batch core release for cores-v1.2.0
# Builds, signs, zips, uploads, and updates appcasts for all updated cores.
set -euo pipefail

REPO="/Users/nickblackmon/Documents/Cursor/Open Emu"
WORKSPACE="$REPO/OpenEmu-metal.xcworkspace"
SIGN_ID="Developer ID Application"
CORES_TAG="cores-v1.2.0"
TMP_DIR="$(mktemp -d)"
DESTINATION='platform=macOS,arch=arm64'

echo "╔══════════════════════════════════════╗"
echo "║  Batch Core Release — $CORES_TAG  ║"
echo "╚══════════════════════════════════════╝"
echo "  Staging dir: $TMP_DIR"
echo ""

# ── Core list: "SchemeName|xcodeproj_rel_path|plugin_name|new_version|appcast" ─
CORES=(
  "mGBA|mGBA/mGBA.xcodeproj|mGBA|0.10.6|Appcasts/mgba.xml"
  "GenesisPlus|GenesisPlus/GenesisPlus.xcodeproj|GenesisPlus|1.7.5.2|Appcasts/genesisplus.xml"
  "FCEU|FCEU/FCEU.xcodeproj|FCEU|2.6.7|Appcasts/fceu.xml"
  "SNES9x|SNES9x/SNES9x.xcodeproj|SNES9x|1.63.1|Appcasts/snes9x.xml"
  "Build & Install BSNES|BSNES/BSNES.xcodeproj|BSNES|115.1|Appcasts/bsnes.xml"
  "Gambatte|Gambatte/Gambatte.xcodeproj|Gambatte|0.5.2|Appcasts/gambatte.xml"
  "Nestopia|Nestopia/Nestopia.xcodeproj|Nestopia|1.52.1|Appcasts/nestopia.xml"
  "Mednafen|Mednafen/Mednafen.xcodeproj|Mednafen|1.26.2|Appcasts/mednafen.xml"
  "Mupen64Plus|Mupen64Plus/Mupen64Plus.xcodeproj|Mupen64Plus|2.5.11|Appcasts/mupen64plus.xml"
  "Build & Install 4DO|4DO/4DO.xcodeproj|4DO|2.3.1|Appcasts/4do.xml"
)

# ── Step 1: Build main workspace (Release) for framework dependencies ─────────
echo "━━━ [1/4] Building OpenEmu workspace (Release) for frameworks ━━━"
xcodebuild build \
  -workspace "$WORKSPACE" \
  -scheme OpenEmu \
  -configuration Release \
  -destination "$DESTINATION" \
  CODE_SIGN_IDENTITY="$SIGN_ID" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=AJC82Q6789 \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
echo ""

DERIVED_RELEASE=$(find "$HOME/Library/Developer/Xcode/DerivedData/OpenEmu-metal-"* \
  -maxdepth 3 -name "Release" -path "*/Build/Products/Release" 2>/dev/null | head -1)
[ -n "$DERIVED_RELEASE" ] || { echo "ERROR: could not find Release build products"; exit 1; }
echo "  Frameworks at: $DERIVED_RELEASE"
echo ""

# ── Step 2: Build, sign, and zip each core ────────────────────────────────────
echo "━━━ [2/4] Building cores ━━━"
ZIPS=()
FAILED=()

for entry in "${CORES[@]}"; do
  IFS='|' read -r SCHEME PROJ_REL PLUGIN VERSION APPCAST <<< "$entry"
  PROJ="$REPO/$PROJ_REL"

  echo ""
  echo "  ── $SCHEME $VERSION ──"

  if [ ! -d "$PROJ" ]; then
    echo "    SKIP: project not found at $PROJ"
    FAILED+=("$SCHEME")
    continue
  fi

  # Build
  if ! xcodebuild build \
      -project "$PROJ" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination "$DESTINATION" \
      ONLY_ACTIVE_ARCH=YES \
      FRAMEWORK_SEARCH_PATHS="$DERIVED_RELEASE" \
      2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3; then
    echo "    FAILED: build error"
    FAILED+=("$SCHEME")
    continue
  fi

  # Locate plugin
  PLUGIN_PATH=$(find "$DERIVED_RELEASE" -maxdepth 1 -name "${PLUGIN}.oecoreplugin" 2>/dev/null | head -1)
  if [ -z "$PLUGIN_PATH" ]; then
    PLUGIN_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
      -name "${PLUGIN}.oecoreplugin" \
      -not -path "*.dSYM*" \
      -not -path "*/Index.noindex/*" \
      2>/dev/null | sort | tail -1)
  fi
  [ -n "$PLUGIN_PATH" ] || { echo "    FAILED: plugin not found"; FAILED+=("$SCHEME"); continue; }
  echo "    Built: $PLUGIN_PATH"

  # Sign
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$PLUGIN_PATH"
  codesign --verify -v "$PLUGIN_PATH" 2>&1 | tail -1
  echo "    Signed OK"

  # Zip
  ZIP="$TMP_DIR/${PLUGIN}.oecoreplugin.zip"
  ditto -c -k --keepParent "$PLUGIN_PATH" "$ZIP"
  SIZE=$(stat -f%z "$ZIP")
  echo "    Zipped: $SIZE bytes → $ZIP"

  ZIPS+=("$SCHEME|$PLUGIN|$VERSION|$APPCAST|$ZIP|$SIZE")
done

echo ""
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "WARNING: ${#FAILED[@]} core(s) failed to build: ${FAILED[*]}"
  echo "Proceed anyway with successful builds? (y/n)"
  read -r CONFIRM
  [[ "$CONFIRM" == "y" ]] || exit 1
fi

# ── Step 3: Create GitHub draft release and upload all zips ──────────────────
echo "━━━ [3/4] Creating GitHub draft release $CORES_TAG ━━━"
cd "$REPO"

git tag "$CORES_TAG"
git push origin "$CORES_TAG"
echo "  Tag pushed: $CORES_TAG"

gh release create "$CORES_TAG" \
  --repo nickybmon/OpenEmu-Silicon \
  --title "Core Updates $CORES_TAG" \
  --notes "Batch core update: RetroAchievements Phase 1 + bug fixes. See app release notes for details." \
  --prerelease \
  --draft
echo "  Draft release created (not yet published)"

for entry in "${ZIPS[@]}"; do
  IFS='|' read -r SCHEME PLUGIN VERSION APPCAST ZIP SIZE <<< "$entry"
  echo "  Uploading $PLUGIN $VERSION..."
  gh release upload "$CORES_TAG" "$ZIP" \
    --repo nickybmon/OpenEmu-Silicon \
    --clobber
done
echo "  All uploads complete"
echo ""

# ── Step 4: Update appcasts and commit ───────────────────────────────────────
echo "━━━ [4/4] Updating appcasts ━━━"
for entry in "${ZIPS[@]}"; do
  IFS='|' read -r SCHEME PLUGIN VERSION APPCAST ZIP SIZE <<< "$entry"
  DOWNLOAD_URL="https://github.com/nickybmon/OpenEmu-Silicon/releases/download/${CORES_TAG}/${PLUGIN}.oecoreplugin.zip"
  python3 "$REPO/Scripts/update_core_appcast.py" \
    "$REPO/$APPCAST" "$PLUGIN" "$VERSION" "$DOWNLOAD_URL" "$SIZE"
done

git add Appcasts/
git commit -m "chore: update cores to $CORES_TAG — RA Phase 1 + bug fixes

mGBA 0.10.6, GenesisPlus 1.7.5.2, FCEU 2.6.7, SNES9x 1.63.1,
BSNES 115.1, Gambatte 0.5.2, Nestopia 1.52.1, Mednafen 1.26.2,
Mupen64Plus 2.5.11, 4DO 2.3.1

Co-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"

git push origin main
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Done! Draft release ready for your review.         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "  Draft: https://github.com/nickybmon/OpenEmu-Silicon/releases/tag/$CORES_TAG"
echo "  Appcasts committed and pushed to main."
echo ""
echo "  When ready to publish:"
echo "  → gh release edit $CORES_TAG --draft=false --repo nickybmon/OpenEmu-Silicon"
echo ""
echo "  ** Do not ask Claude to run that command. Publishing is always your call. **"
rm -rf "$TMP_DIR"
