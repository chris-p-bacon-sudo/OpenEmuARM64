#!/bin/bash
#
# install-core.sh — install a built core plugin into the OE cores directory
#
# Usage:
#   ./Scripts/install-core.sh <CoreName> [--debug|--release]
#
# Examples:
#   ./Scripts/install-core.sh Dolphin                # default: install the Debug build
#   ./Scripts/install-core.sh FCEU --release         # install the Release build (use when
#                                                    # reproducing a Release-only bug)
#
# Why this script exists:
#   - cp -Rf on an existing .oecoreplugin bundle silently skips files that
#     already exist at the destination — the old binary stays in place.
#   - If OpenEmu is running, the helper process holds the binary open and
#     cp will silently fail to replace it.
#   This script quits OpenEmu first, then copies the binary and Info.plist
#   individually with -f so the destination is always fully updated.
#
#   At the end the source and installed MD5 hashes are printed side by side
#   so a stale install (e.g. wrong configuration, OpenEmu still holding the
#   binary open, copy silently failed) jumps off the screen.

set -euo pipefail

CORE=""
CONFIG="Debug"

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)   CONFIG="Debug";   shift ;;
    --release) CONFIG="Release"; shift ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0 ;;
    -*)
      echo "error: unknown flag: $1" >&2
      exit 2 ;;
    *)
      if [ -z "$CORE" ]; then
        CORE="$1"
      else
        echo "error: unexpected positional argument: $1" >&2
        exit 2
      fi
      shift ;;
  esac
done

if [ -z "$CORE" ]; then
  echo "Usage: $0 <CoreName> [--debug|--release]" >&2
  exit 2
fi

DEST="$HOME/Library/Application Support/OpenEmu/Cores/${CORE}.oecoreplugin"

# Look in two places, in this order, and pick the most recently built:
#   1. ~/Builds/openemu/<branch>/  — worktree mode build path, used by verify.sh
#                                    when run inside a git worktree
#   2. ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/  — standard build path
#
# Picking the most recent is critical: if a stale build exists in DerivedData,
# we must not silently install it instead of the worktree build the user just
# made (or vice versa). This is the failure mode the FCEU grey-screen session
# spent hours debugging — see issue #214.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKTREE_BUILD=""
if [ -f "$REPO_ROOT/.git" ]; then
  BRANCH=$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null | sed 's|/|-|g')
  if [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ]; then
    CANDIDATE="$HOME/Builds/openemu/$BRANCH/Build/Products/${CONFIG}/${CORE}.oecoreplugin"
    [ -e "$CANDIDATE/Contents/MacOS/${CORE}" ] && WORKTREE_BUILD="$CANDIDATE"
  fi
fi

DERIVED_BUILD=$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenEmu-metal-"*/Build/Products/${CONFIG}/"${CORE}.oecoreplugin" 2>/dev/null | head -1 || true)

# Choose whichever candidate has the more recently modified binary.
DERIVED=""
if [ -n "$WORKTREE_BUILD" ] && [ -n "$DERIVED_BUILD" ]; then
  WT_MTIME=$(stat -f "%m" "$WORKTREE_BUILD/Contents/MacOS/${CORE}" 2>/dev/null || echo 0)
  DD_MTIME=$(stat -f "%m" "$DERIVED_BUILD/Contents/MacOS/${CORE}" 2>/dev/null || echo 0)
  if [ "$WT_MTIME" -ge "$DD_MTIME" ]; then
    DERIVED="$WORKTREE_BUILD"
  else
    DERIVED="$DERIVED_BUILD"
  fi
elif [ -n "$WORKTREE_BUILD" ]; then
  DERIVED="$WORKTREE_BUILD"
elif [ -n "$DERIVED_BUILD" ]; then
  DERIVED="$DERIVED_BUILD"
fi

if [ -z "$DERIVED" ]; then
  echo "error: ${CORE}.oecoreplugin not found in any known build location (${CONFIG})."
  echo "       Looked in:"
  echo "         ~/Builds/openemu/<branch>/Build/Products/${CONFIG}/"
  echo "         ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/${CONFIG}/"
  echo "       Build the '${CORE}' scheme first:"
  echo "       xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme \"OpenEmu + ${CORE}\" \\"
  echo "         -configuration ${CONFIG} -destination 'platform=macOS,arch=arm64' build"
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

if [ ! -d "$DEST" ]; then
  echo "First-time install: creating ${DEST}"
  mkdir -p "$(dirname "$DEST")"
  cp -R "${DERIVED}" "${DEST}"
else
  echo "Installing ${CORE}.oecoreplugin (${CONFIG}) from:"
  echo "  ${DERIVED}"
  cp -f "${DERIVED}/Contents/MacOS/${CORE}" "${DEST}/Contents/MacOS/${CORE}"
  cp -f "${DERIVED}/Contents/Info.plist"    "${DEST}/Contents/Info.plist"
fi

SRC_MD5=$(md5 -q "${DERIVED}/Contents/MacOS/${CORE}")
DST_MD5=$(md5 -q "${DEST}/Contents/MacOS/${CORE}")
SRC_DATE=$(stat -f "%Sm" -t "%b %d %H:%M:%S" "${DERIVED}/Contents/MacOS/${CORE}")
DST_DATE=$(stat -f "%Sm" -t "%b %d %H:%M:%S" "${DEST}/Contents/MacOS/${CORE}")

echo ""
echo "Source     ${SRC_MD5}   built  ${SRC_DATE}"
echo "Installed  ${DST_MD5}   active ${DST_DATE}"

if [ "${SRC_MD5}" = "${DST_MD5}" ]; then
  echo ""
  echo "OK — installed binary matches source."
else
  echo ""
  echo "WARNING — installed binary does NOT match source. The copy may have"
  echo "          failed silently (OpenEmu still holding the binary open?)."
  echo "          Quit OpenEmu fully and re-run."
  exit 1
fi
