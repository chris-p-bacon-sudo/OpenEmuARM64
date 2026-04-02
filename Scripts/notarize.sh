#!/usr/bin/env bash
# notarize.sh — Re-sign, audit, and notarize OpenEmu from an existing .xcarchive
#
# Usage:
#   ./Scripts/notarize.sh                          # uses latest xcarchive
#   ./Scripts/notarize.sh "path/to/archive.xcarchive"

IDENTITY="Developer ID Application"
PROFILE_NAME="OpenEmu"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENTITLEMENTS="$REPO_ROOT/OpenEmu/OpenEmu.entitlements"
HELPER_ENTITLEMENTS="$REPO_ROOT/OpenEmu/OpenEmuHelperApp/OpenEmuHelperApp.entitlements"

die() { echo "ERROR: $*" >&2; [ -n "${WORK_DIR:-}" ] && rm -rf "$WORK_DIR"; exit 1; }

# ── 1. Find archive ──────────────────────────────────────────────────────────
if [ $# -ge 1 ]; then
  ARCHIVE="$1"
else
  ARCHIVE=$(find "$HOME/Library/Developer/Xcode/Archives" -maxdepth 2 \
    -name "*.xcarchive" -print0 \
    | xargs -0 ls -d 2>/dev/null \
    | sort | tail -1)
fi

[ -d "$ARCHIVE" ] || die "No .xcarchive found. Pass a path or run an Xcode archive first."
echo "Using archive: $ARCHIVE"

# ── 2. Extract app ───────────────────────────────────────────────────────────
APP_SRC=$(find "$ARCHIVE/Products" -name "OpenEmu.app" -maxdepth 4 | head -1)
[ -n "$APP_SRC" ] || die "OpenEmu.app not found in archive."

WORK_DIR=$(mktemp -d)
APP="$WORK_DIR/OpenEmu.app"
echo "Copying app to temp dir..."
cp -R "$APP_SRC" "$APP" || die "Failed to copy app."

# ── 3. Credential check ──────────────────────────────────────────────────────
echo ""
echo "=== Credential check ==="
if ! xcrun notarytool history --keychain-profile "$PROFILE_NAME" &>/dev/null; then
  echo ""
  echo "ERROR: No keychain profile '$PROFILE_NAME' found."
  echo "Run this once in Terminal: xcrun notarytool store-credentials OpenEmu"
  echo "  Apple ID:              nick.r.blackmon@gmail.com"
  echo "  App-specific password: from appleid.apple.com → Security → App-Specific Passwords"
  echo "  Team ID:               AJC82Q6789"
  rm -rf "$WORK_DIR"; exit 1
fi
echo "Credentials OK."

# ── 4. Re-sign inside-out ────────────────────────────────────────────────────
echo ""
echo "=== Re-signing all binaries with Developer ID + hardened runtime ==="

sign() {
  local item="$1"; shift
  [ -e "$item" ] || return 0
  echo "  signing: $(basename "$item")"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$@" "$item" \
    || die "codesign failed on: $item"
}

# Step 1: Sign all standalone Mach-O binaries (executables/dylibs not inside bundles)
# OpenEmuHelperApp is signed with its own entitlements (disable-library-validation
# + allow-jit) so it can load core plugins and run dynarec emulation cores.
echo "-- standalone binaries --"
while IFS= read -r f; do
  if ! file "$f" 2>/dev/null | grep -q "Mach-O"; then
    continue
  fi
  if [[ "$(basename "$f")" == "OpenEmuHelperApp" ]]; then
    echo "  signing: OpenEmuHelperApp (with entitlements)"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
      --entitlements "$HELPER_ENTITLEMENTS" "$f" \
      || die "codesign failed on: $f"
  else
    sign "$f"
  fi
done < <(find "$APP" -type f \( -perm +111 -o -name "*.dylib" \) 2>/dev/null)

# Step 2: Sign all nested bundles inside-out (deepest path first)
# Covers: .framework, .xpc, .app, .appex, .qlgenerator, .oesystemplugin, .bundle
echo "-- bundles (inside-out) --"
while IFS= read -r bundle; do
  [ "$bundle" = "$APP" ] && continue  # skip the main app — signed last
  sign "$bundle"
done < <(
  find "$APP" -mindepth 1 \( \
    -name "*.framework" -o -name "*.xpc" -o -name "*.app" \
    -o -name "*.appex" -o -name "*.qlgenerator" \
    -o -name "*.oesystemplugin" -o -name "*.bundle" \
    -o -name "*.oecoreplugin" \
  \) -prune 2>/dev/null \
  | awk -F/ '{ print NF, $0 }' | sort -rn | awk '{ $1=""; sub(/^ /,""); print }'
)

# Step 3: Main app — must be last, must include entitlements
echo "  signing: OpenEmu.app (with entitlements)"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" "$APP" \
  || die "codesign failed on main app."

echo "Re-signing complete."

# ── 5. Signing audit ─────────────────────────────────────────────────────────
echo ""
echo "=== Signing audit ==="
FAIL=0

while IFS= read -r binary; do
  INFO=$(codesign -dvv "$binary" 2>&1)

  if ! echo "$INFO" | grep -q "Authority=Developer ID Application"; then
    echo "FAIL [no Developer ID]: $binary"
    FAIL=1
  fi

  if ! echo "$INFO" | grep -q "flags=.*runtime"; then
    echo "FAIL [no hardened runtime]: $binary"
    FAIL=1
  fi

  if ! echo "$INFO" | grep -q "Timestamp="; then
    echo "FAIL [no secure timestamp]: $binary"
    FAIL=1
  fi
done < <(find "$APP" -type f -perm +111 -print \
  | while read -r f; do file "$f" 2>/dev/null | grep -q "Mach-O" && echo "$f"; done)

# Dylibs (not executable bit)
while IFS= read -r f; do
  INFO=$(codesign -dvv "$f" 2>&1)
  if ! echo "$INFO" | grep -q "Authority=Developer ID Application"; then
    echo "FAIL [no Developer ID]: $f"; FAIL=1
  fi
  if ! echo "$INFO" | grep -q "flags=.*runtime"; then
    echo "FAIL [no hardened runtime]: $f"; FAIL=1
  fi
  if ! echo "$INFO" | grep -q "Timestamp="; then
    echo "FAIL [no secure timestamp]: $f"; FAIL=1
  fi
done < <(find "$APP" -name "*.dylib" 2>/dev/null)

# Main app entitlements
ENT=$(codesign -d --entitlements - "$APP" 2>&1 || true)
if ! echo "$ENT" | grep -q "com.apple.security.cs.disable-library-validation"; then
  echo "FAIL [missing disable-library-validation]: OpenEmu.app"
  FAIL=1
else
  echo "OK: disable-library-validation entitlement present on OpenEmu.app"
fi

# HelperApp entitlements — must have disable-library-validation and allow-jit
HELPER_BIN=$(find "$APP" -name "OpenEmuHelperApp" -type f 2>/dev/null | head -1)
if [ -n "$HELPER_BIN" ]; then
  HENT=$(codesign -d --entitlements - "$HELPER_BIN" 2>&1 || true)
  if ! echo "$HENT" | grep -q "com.apple.security.cs.disable-library-validation"; then
    echo "FAIL [missing disable-library-validation]: OpenEmuHelperApp"
    FAIL=1
  else
    echo "OK: disable-library-validation entitlement present on OpenEmuHelperApp"
  fi
  if ! echo "$HENT" | grep -q "com.apple.security.cs.allow-jit"; then
    echo "FAIL [missing allow-jit]: OpenEmuHelperApp"
    FAIL=1
  else
    echo "OK: allow-jit entitlement present on OpenEmuHelperApp"
  fi
else
  echo "WARN: OpenEmuHelperApp not found in bundle — skipping entitlements audit"
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Signing audit FAILED. See failures above."
  rm -rf "$WORK_DIR"; exit 1
fi
echo "All binaries pass notarization signing requirements."

# ── 6. Deep verify ───────────────────────────────────────────────────────────
echo ""
echo "=== Deep signature verify ==="
codesign --verify --deep --strict "$APP" || die "Deep signature verify failed."
echo "Signature chain OK."

# ── 7. Zip and notarize ───────────────────────────────────────────────────────
echo ""
echo "=== Submitting for notarization (may take a few minutes) ==="
ZIP="$WORK_DIR/OpenEmu-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP" || die "Failed to create zip."

NOTARIZE_LOG="$WORK_DIR/notarize.log"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE_NAME" \
  --wait 2>&1 | tee "$NOTARIZE_LOG"

if grep -q "status: Accepted" "$NOTARIZE_LOG"; then
  echo ""
  echo "=== Notarization accepted! Stapling... ==="
  xcrun stapler staple "$APP" || die "Stapling failed."

  # ── 8. Create DMG ───────────────────────────────────────────────────────
  DMG="$REPO_ROOT/Releases/OpenEmu-Silicon.dmg"
  mkdir -p "$REPO_ROOT/Releases"
  echo ""
  echo "=== Creating DMG ==="
  hdiutil create \
    -volname "OpenEmu-Silicon" \
    -srcfolder "$APP" \
    -ov -format UDZO \
    "$DMG" || die "hdiutil failed."

  echo "Notarizing DMG..."
  DMG_NOTARIZE_LOG="$WORK_DIR/notarize-dmg.log"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$PROFILE_NAME" \
    --wait 2>&1 | tee "$DMG_NOTARIZE_LOG"
  grep -q "status: Accepted" "$DMG_NOTARIZE_LOG" || die "DMG notarization was not accepted."
  xcrun stapler staple "$DMG" || die "DMG stapling failed."

  echo ""
  echo "=============================="
  echo "  SUCCESS"
  echo "=============================="
  echo "  DMG: $DMG"
  echo ""
  echo "Gatekeeper check:"
  spctl -a -vv "$APP" 2>&1 || true

  echo ""
  echo "=== Appcast values (update appcast.xml) ==="
  echo "  DMG size (bytes): $(stat -f%z "$DMG")"
  echo "  EdDSA signature:  run './bin/sign_update $DMG'"
else
  # Get submission ID from log for manual retrieval
  SUBID=$(grep " *id: " "$NOTARIZE_LOG" | head -1 | awk '{print $2}')
  echo ""
  echo "=== Notarization was NOT accepted. ==="
  if [ -n "$SUBID" ]; then
    echo "Fetching rejection log for $SUBID ..."
    xcrun notarytool log "$SUBID" --keychain-profile "$PROFILE_NAME" || true
  fi
  rm -rf "$WORK_DIR"; exit 1
fi

rm -rf "$WORK_DIR"
