#!/bin/bash
#
# verify-core-installed.sh — sub-second preflight: does the installed core
# plugin match the latest build? Run this before declaring a core test result.
#
# Usage:
#   ./Scripts/verify-core-installed.sh <CoreName> [--debug|--release]
#
# Examples:
#   ./Scripts/verify-core-installed.sh FCEU
#   ./Scripts/verify-core-installed.sh FCEU --release
#
# Why this script exists:
#   OpenEmu loads cores from ~/Library/Application Support/OpenEmu/Cores/,
#   not from the build directory. Building a core does not affect what
#   OpenEmu loads. This script catches the very common failure mode where
#   you've built a core but forgotten (or silently failed) to install it,
#   and are about to claim a test result against the stale installed copy.
#
# Exit codes:
#   0  — installed plugin matches the latest build
#   1  — installed plugin does NOT match the latest build (stale install)
#   2  — bad usage (missing or unknown args)
#   3  — no installed plugin found (run OpenEmu once to install, or copy manually)
#   4  — no built artifact found (build the core scheme first)

set -uo pipefail

CORE=""
CONFIG="Debug"

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)   CONFIG="Debug";   shift ;;
    --release) CONFIG="Release"; shift ;;
    -h|--help)
      sed -n '2,28p' "$0"
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

INSTALLED="$HOME/Library/Application Support/OpenEmu/Cores/${CORE}.oecoreplugin"

# Look in both possible build locations and pick the most recent. Same logic
# as install-core.sh — see comment there for rationale.
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

LOCAL_CORE_BUILD="$REPO_ROOT/${CORE}/build/XcodeDerived/Build/Products/${CONFIG}/${CORE}.oecoreplugin"
[ -e "$LOCAL_CORE_BUILD/Contents/MacOS/${CORE}" ] || LOCAL_CORE_BUILD=""
DERIVED_BUILD=$(ls -dt "$HOME/Library/Developer/Xcode/DerivedData/OpenEmu-metal-"*/Build/Products/${CONFIG}/"${CORE}.oecoreplugin" 2>/dev/null | head -1 || true)

BUILT=""
BUILT_MTIME=0
for CANDIDATE in "$WORKTREE_BUILD" "$LOCAL_CORE_BUILD" "$DERIVED_BUILD"; do
  [ -n "$CANDIDATE" ] || continue
  CANDIDATE_MTIME=$(stat -f "%m" "$CANDIDATE/Contents/MacOS/${CORE}" 2>/dev/null || echo 0)
  if [ "$CANDIDATE_MTIME" -ge "$BUILT_MTIME" ]; then
    BUILT="$CANDIDATE"
    BUILT_MTIME="$CANDIDATE_MTIME"
  fi
done

if [ ! -e "${INSTALLED}/Contents/MacOS/${CORE}" ]; then
  echo "FAIL — no installed plugin found for ${CORE}." >&2
  echo "       Expected at: ${INSTALLED}" >&2
  echo "       Launch OpenEmu once so it installs the plugin, or copy manually." >&2
  exit 3
fi

if [ -z "${BUILT}" ] || [ ! -e "${BUILT}/Contents/MacOS/${CORE}" ]; then
  echo "FAIL — no ${CONFIG} build of ${CORE} found in any known build location." >&2
  echo "       Build the core scheme first:" >&2
  echo "       xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme \"OpenEmu + ${CORE}\" \\" >&2
  echo "         -configuration ${CONFIG} -destination 'platform=macOS,arch=arm64' build" >&2
  exit 4
fi

bundle_digest() {
  python3 - "$1" <<'PY'
import hashlib
import os
import sys

root = sys.argv[1]
entries = []
for dirpath, _, filenames in os.walk(root):
    for filename in filenames:
        if filename == ".DS_Store" or filename.startswith("._"):
            continue
        path = os.path.join(dirpath, filename)
        rel = os.path.relpath(path, root)
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        entries.append((rel, h.hexdigest()))

overall = hashlib.sha256()
for rel, digest in sorted(entries):
    overall.update(rel.encode("utf-8"))
    overall.update(b"\0")
    overall.update(digest.encode("ascii"))
    overall.update(b"\0")
print(overall.hexdigest())
PY
}

INSTALLED_BIN="${INSTALLED}/Contents/MacOS/${CORE}"
BUILT_BIN="${BUILT}/Contents/MacOS/${CORE}"

INSTALLED_MD5=$(md5 -q "${INSTALLED_BIN}")
BUILT_MD5=$(md5 -q "${BUILT_BIN}")
INSTALLED_DIGEST=$(bundle_digest "${INSTALLED}")
BUILT_DIGEST=$(bundle_digest "${BUILT}")

if [ "${INSTALLED_MD5}" = "${BUILT_MD5}" ] && [ "${INSTALLED_DIGEST}" = "${BUILT_DIGEST}" ]; then
  INSTALLED_DATE=$(stat -f "%Sm" -t "%b %d %H:%M:%S" "${INSTALLED_BIN}")
  echo "OK — installed ${CORE} (${CONFIG}) matches latest build."
  echo "     binary md5: ${INSTALLED_MD5}   active ${INSTALLED_DATE}"
  echo "     bundle sha256: ${INSTALLED_DIGEST}"
  exit 0
fi

INSTALLED_DATE=$(stat -f "%Sm" -t "%b %d %H:%M:%S" "${INSTALLED_BIN}")
BUILT_DATE=$(stat -f "%Sm" -t "%b %d %H:%M:%S" "${BUILT_BIN}")

echo "FAIL — installed ${CORE} plugin does not match latest ${CONFIG} build." >&2
echo "" >&2
echo "Built:      ${BUILT_DATE}   binary md5: ${BUILT_MD5}" >&2
echo "            bundle sha256: ${BUILT_DIGEST}" >&2
echo "            ${BUILT}" >&2
echo "" >&2
echo "Installed:  ${INSTALLED_DATE}   binary md5: ${INSTALLED_MD5}" >&2
echo "            bundle sha256: ${INSTALLED_DIGEST}" >&2
echo "            ${INSTALLED}" >&2
echo "" >&2
echo "To fix: ./Scripts/install-core.sh ${CORE}$([ "${CONFIG}" = "Release" ] && echo " --release")" >&2
exit 1
