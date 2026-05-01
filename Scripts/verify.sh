#!/usr/bin/env bash
# verify.sh — Autonomous verification floor for OpenEmu-Silicon
#
# Usage:
#   ./Scripts/verify.sh                        # build + analyze + plist + codesign on the main app
#   ./Scripts/verify.sh --launch               # above, plus 5s smoke launch with log + crash check
#   ./Scripts/verify.sh --test                 # above, plus run OpenEmuTests unit test target
#   ./Scripts/verify.sh --core <CoreName>      # build a core scheme + install + verify the installed plugin
#   ./Scripts/verify.sh --core <CoreName> --launch
#
# Exit code is the number of failing checks. 0 means everything passed.
# Each check prints a single PASS/FAIL line so the summary is greppable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

WORKSPACE="OpenEmu-metal.xcworkspace"
APP_PLIST="OpenEmu/OpenEmu-Info.plist"
APP_ENTITLEMENTS="OpenEmu/OpenEmu.entitlements"
INSTALLED_APP_DEFAULT="$HOME/Library/Application Support/OpenEmu"

LAUNCH=0
CORE=""
RUN_TESTS=0
FAILURES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --launch) LAUNCH=1; shift ;;
    --core) CORE="${2:-}"; shift 2 ;;
    --test) RUN_TESTS=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILURES=$((FAILURES+1)); }
info() { echo "----  $1"; }

# --- Build ---------------------------------------------------------------

if [ -n "$CORE" ]; then
  SCHEME="$CORE"
  info "Building core scheme: $SCHEME"
else
  SCHEME="OpenEmu"
  info "Building main app scheme: $SCHEME"
fi

BUILD_LOG=$(mktemp -t verify_build.XXXXXX)
if xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
     -configuration Debug -destination 'platform=macOS,arch=arm64' \
     build > "$BUILD_LOG" 2>&1; then
  pass "build ($SCHEME)"
else
  fail "build ($SCHEME) — see $BUILD_LOG (last 30 lines below)"
  tail -30 "$BUILD_LOG"
fi

# Surface warnings even on a passing build — these are technical debt accumulating silently.
WARN_COUNT=$(grep -cE ': (warning|error):' "$BUILD_LOG" 2>/dev/null || true)
if [ "${WARN_COUNT:-0}" -gt 0 ]; then
  info "$WARN_COUNT warning/error lines in build log — first 10:"
  grep -E ': (warning|error):' "$BUILD_LOG" | head -10
fi

# --- Static analyzer (main app only — core schemes don't all support analyze) ---

if [ -z "$CORE" ]; then
  ANALYZE_LOG=$(mktemp -t verify_analyze.XXXXXX)
  if xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" \
       -configuration Debug -destination 'platform=macOS,arch=arm64' \
       analyze > "$ANALYZE_LOG" 2>&1; then
    pass "analyze ($SCHEME)"
  else
    fail "analyze ($SCHEME) — see $ANALYZE_LOG"
    tail -20 "$ANALYZE_LOG"
  fi
fi

# --- Plist lint ----------------------------------------------------------

if [ -z "$CORE" ]; then
  PLISTS=("$APP_PLIST" "$APP_ENTITLEMENTS")
else
  # Each core has its own Info.plist somewhere in its directory.
  mapfile -t PLISTS < <(find "$CORE" -maxdepth 3 -name 'Info.plist' 2>/dev/null)
fi

for p in "${PLISTS[@]:-}"; do
  [ -z "$p" ] && continue
  if [ ! -f "$p" ]; then
    info "skipping (missing): $p"
    continue
  fi
  if plutil -lint "$p" >/dev/null 2>&1; then
    pass "plutil $p"
  else
    fail "plutil $p"
    plutil -lint "$p" || true
  fi
done

# --- Locate the built artifact and codesign verify ---------------------------

DERIVED_BASE="$HOME/Library/Developer/Xcode/DerivedData"

if [ -z "$CORE" ]; then
  ARTIFACT=$(find "$DERIVED_BASE" -maxdepth 5 -path '*OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app' -print -quit 2>/dev/null)
else
  ARTIFACT=$(find "$DERIVED_BASE" -maxdepth 5 -path "*OpenEmu-metal-*/Build/Products/Debug/${CORE}.oecoreplugin" -print -quit 2>/dev/null)
fi

if [ -z "$ARTIFACT" ] || [ ! -e "$ARTIFACT" ]; then
  fail "locate built artifact (expected in DerivedData)"
else
  info "artifact: $ARTIFACT"
  if codesign --verify --deep --strict "$ARTIFACT" 2>/dev/null; then
    pass "codesign --verify --deep --strict"
  else
    fail "codesign --verify --deep --strict — output:"
    codesign --verify --deep --strict "$ARTIFACT" || true
  fi
fi

# --- Core install + post-install verification --------------------------------

if [ -n "$CORE" ] && [ -n "${ARTIFACT:-}" ] && [ -e "$ARTIFACT" ]; then
  INSTALL_DEST="$INSTALLED_APP_DEFAULT/Cores/${CORE}.oecoreplugin"
  if [ -x "./Scripts/install-core.sh" ]; then
    info "installing core via Scripts/install-core.sh"
    if ./Scripts/install-core.sh "$CORE" >/dev/null 2>&1; then
      pass "install-core.sh $CORE"
    else
      fail "install-core.sh $CORE"
    fi
  else
    info "Scripts/install-core.sh not executable — skipping install"
  fi

  if [ -e "$INSTALL_DEST" ]; then
    if codesign --verify --deep --strict "$INSTALL_DEST" 2>/dev/null; then
      pass "codesign installed plugin"
    else
      fail "codesign installed plugin"
    fi
  fi
fi

# --- Optional smoke launch -----------------------------------------------

if [ "$LAUNCH" -eq 1 ] && [ -z "$CORE" ] && [ -n "${ARTIFACT:-}" ] && [ -e "$ARTIFACT" ]; then
  if pgrep -x OpenEmu >/dev/null 2>&1; then
    info "OpenEmu is already running — skipping smoke launch (would clobber user state)"
  else
    info "smoke launching for 5s and capturing logs"
    LAUNCH_START=$(date +"%Y-%m-%d %H:%M:%S")
    open -g "$ARTIFACT"
    sleep 5

    if pgrep -x OpenEmu >/dev/null 2>&1; then
      pass "process alive after 5s"
      pkill -x OpenEmu 2>/dev/null || true
    else
      fail "process died within 5s of launch"
    fi

    # Log scan for OpenEmu-related faults/errors during the launch window
    LOG_OUT=$(log show --predicate 'process == "OpenEmu"' \
               --start "$LAUNCH_START" --style compact 2>/dev/null \
               | grep -iE '(fault|error|exception|crash|abort)' \
               | head -20 || true)
    if [ -n "$LOG_OUT" ]; then
      info "log scan found suspicious lines:"
      echo "$LOG_OUT"
    else
      pass "log scan clean"
    fi

    # Crash report check — DiagnosticReports written within the last minute
    CRASH_NEW=$(find "$HOME/Library/Logs/DiagnosticReports" -name 'OpenEmu*' -mmin -1 2>/dev/null)
    if [ -n "$CRASH_NEW" ]; then
      fail "new crash report(s) written:"
      echo "$CRASH_NEW"
    else
      pass "no new crash reports"
    fi
  fi
fi

# --- Optional unit tests (OpenEmuTests target) ---------------------------

if [ "$RUN_TESTS" -eq 1 ] && [ -z "$CORE" ]; then
  info "running OpenEmuTests (xcodebuild test)"
  TEST_LOG=$(mktemp -t verify_test.XXXXXX)
  if xcodebuild test \
       -workspace "$WORKSPACE" \
       -scheme OpenEmu \
       -configuration Debug \
       -destination 'platform=macOS,arch=arm64' \
       > "$TEST_LOG" 2>&1; then
    PASS_COUNT=$(grep -c 'passed' "$TEST_LOG" 2>/dev/null || true)
    pass "OpenEmuTests ($PASS_COUNT tests passed)"
  else
    fail "OpenEmuTests — see $TEST_LOG (last 30 lines below)"
    tail -30 "$TEST_LOG"
  fi
fi

# --- Summary -------------------------------------------------------------

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "===================="
  echo "verify.sh: ALL PASS"
  echo "===================="
  exit 0
else
  echo "===================="
  echo "verify.sh: $FAILURES FAILED"
  echo "===================="
  exit "$FAILURES"
fi
