#!/usr/bin/env bash
# upload-core-dsyms.sh — Build cores in Release and upload their dSYMs to Sentry.
#
# Use this to backfill dSYMs for any core whose Sentry upload was missed or skipped,
# and before every host-app release to ensure all currently-deployed core dSYMs are
# in Sentry so crashes can be symbolicated.
#
# Usage:
#   ./Scripts/upload-core-dsyms.sh                     # all cores in CORES list
#   ./Scripts/upload-core-dsyms.sh Mupen64Plus Snes9x  # specific cores only
#   ./Scripts/upload-core-dsyms.sh --dry-run            # show what would run, don't build
#
# Prerequisites:
#   - sentry-cli installed and authenticated (sentry-cli info must pass)
#   - Developer ID Application cert in keychain (for package-core.sh's sign step)
#
# NOTE: This rebuilds each core from the current working tree in Release config.
# The resulting dSYMs match the rebuilt binary — not the previously released binary
# unless the source is unchanged. Run this immediately after releasing a core batch
# so the uploaded dSYMs match what users have installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

die()  { echo ""; echo "ERROR: $*" >&2; exit 1; }
ok()   { echo "PASS  $*"; }
warn() { echo "WARN  $*"; }
step() { echo ""; echo "──── $*"; }

# All in-repo cores with Release-buildable schemes.
ALL_CORES=(
  4DO
  BSNES
  DeSmuME
  Dolphin
  FCEU
  Flycast
  Gambatte
  GenesisPlus
  mGBA
  Mednafen
  Mupen64Plus
  Nestopia
  PPSSPP
  PicoDrive
  Snes9x
  Stella
  VirtualJaguar
)

DRY_RUN=0
TARGET_CORES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--dry-run] [CoreName ...]"
      echo "  No CoreName args → runs all cores: ${ALL_CORES[*]}"
      exit 0
      ;;
    *)
      TARGET_CORES+=("$1")
      shift
      ;;
  esac
done

if [ ${#TARGET_CORES[@]} -eq 0 ]; then
  TARGET_CORES=("${ALL_CORES[@]}")
fi

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight"

command -v sentry-cli &>/dev/null \
  || die "sentry-cli not installed. Run: brew install getsentry/tools/sentry-cli"
sentry-cli info &>/dev/null \
  || die "sentry-cli not authenticated. Run: sentry-cli login (or set SENTRY_AUTH_TOKEN)"
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || die "Developer ID Application certificate not found in keychain."

ok "sentry-cli authenticated"
ok "Developer ID cert present"
echo "Cores to process: ${TARGET_CORES[*]}"
[ "$DRY_RUN" -eq 0 ] || echo "(DRY RUN — no builds or uploads)"

# ── Build host app in Release first (required by some cores) ──────────────────
if [ "$DRY_RUN" -eq 0 ]; then
  step "Building host app in Release (dependency for core builds)"
  xcodebuild \
    -workspace "$REPO_ROOT/OpenEmu-metal.xcworkspace" \
    -scheme OpenEmu \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    build 2>&1 | grep -E "^(error:|warning: |BUILD)" | tail -10
  ok "Host app Release build complete"
fi

# ── Process each core ─────────────────────────────────────────────────────────
PASSED=()
FAILED=()
SKIPPED=()

for CORE in "${TARGET_CORES[@]}"; do
  echo ""
  echo "════════════════════════════════════"
  echo "  $CORE"
  echo "════════════════════════════════════"

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "(dry run) would: build Release → package-core.sh → upload dSYM to Sentry"
    PASSED+=("$CORE")
    continue
  fi

  # Determine the current version from the plist
  PLIST=$(find "$REPO_ROOT/$CORE" -maxdepth 2 -name "Info.plist" 2>/dev/null | head -1)
  if [ -z "$PLIST" ]; then
    warn "$CORE: Info.plist not found — skipping"
    SKIPPED+=("$CORE")
    continue
  fi

  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST" 2>/dev/null || true)
  if [ -z "$VERSION" ]; then
    warn "$CORE: CFBundleVersion not found in $PLIST — skipping"
    SKIPPED+=("$CORE")
    continue
  fi
  echo "Version: $VERSION"

  # Build the core in Release
  step "Building $CORE $VERSION in Release"
  if ! xcodebuild \
    -workspace "$REPO_ROOT/OpenEmu-metal.xcworkspace" \
    -scheme "OpenEmu + $CORE" \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    ONLY_ACTIVE_ARCH=YES \
    build 2>&1 | grep -E "^(error:|BUILD)" | tail -5; then
    warn "$CORE: build failed — skipping dSYM upload"
    FAILED+=("$CORE")
    continue
  fi

  # Verify the plugin exists
  DERIVED_DATA=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 \
    -name "OpenEmu-metal-*" -type d 2>/dev/null | head -1)
  PLUGIN="$DERIVED_DATA/Build/Products/Release/${CORE}.oecoreplugin"
  if [ ! -d "$PLUGIN" ]; then
    warn "$CORE: plugin not found at $PLUGIN after build — skipping"
    FAILED+=("$CORE")
    continue
  fi

  # Upload dSYM via verify-sentry-symbols.sh (same path as package-core.sh)
  step "Uploading dSYM for $CORE to Sentry"
  if "$SCRIPT_DIR/verify-sentry-symbols.sh" \
    --upload \
    --wait-for 60 \
    --binary-root "$PLUGIN" \
    --dsym-root "$DERIVED_DATA/Build/Products/Release"; then
    ok "$CORE $VERSION — dSYM uploaded"
    PASSED+=("$CORE")
  else
    warn "$CORE: dSYM upload failed"
    FAILED+=("$CORE")
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "  Summary"
echo "════════════════════════════════════"
echo "  Passed:  ${#PASSED[@]}  — ${PASSED[*]:-none}"
echo "  Failed:  ${#FAILED[@]}  — ${FAILED[*]:-none}"
echo "  Skipped: ${#SKIPPED[@]} — ${SKIPPED[*]:-none}"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "  Some cores failed. Re-run for specific cores:"
  for c in "${FAILED[@]}"; do
    echo "    $0 $c"
  done
  exit 1
fi

echo ""
echo "All core dSYMs processed. Sentry will symbolicate crashes for the rebuilt cores."
