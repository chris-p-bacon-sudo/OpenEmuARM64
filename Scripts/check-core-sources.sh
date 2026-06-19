#!/usr/bin/env bash
# check-core-sources.sh — Guardrail against a flattened submodule dropping its
# vendored source.
#
# Background: some cores (Dolphin, Flycast) once pulled their external
# dependencies as *nested git submodules*. When those submodules were flattened
# into plain tracked files, it was possible to commit only each external's
# build-wrapper files (CMakeLists.txt / .vcxproj) while leaving the actual
# upstream source un-vendored. The Xcode build then dies on the first missing
# file — but CI never built these cores, so the break stayed invisible for
# months. (See the Dolphin Externals restoration, mid-2026.)
#
# This check catches that class of regression in seconds, with no Xcode:
# for every external listed in a core's .gitmodules whose top-level directory
# is referenced by that core's Xcode project (i.e. the project expects to
# compile or include it), assert the external's inner source directory exists
# and is non-empty.
#
# Externals that the project does NOT reference (Windows-only deps, optional
# backends, test frameworks) are allowed to be absent — they aren't compiled
# on macOS, so a missing source tree can't break the build.
#
# Wired into .github/workflows/build-check.yml as a fast PR job for changes
# touching Dolphin/** or Flycast/**. Cheap to run anywhere.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Cores with flatten history. Fields, colon-separated:
#   <name>:<gitmodules>:<source-root>:<pbxproj>:<externals-root>
# - source-root   : directory the .gitmodules paths are relative to
# - externals-root : directory under source-root that holds the externals;
#                    the "top dir" of an external is <externals-root>/<first
#                    path component after it>, which is what the pbxproj
#                    references. (Dolphin: Externals, Flycast: core/deps.)
CORES=(
  "Dolphin:Dolphin/dolphin/.gitmodules:Dolphin/dolphin:Dolphin/Dolphin.xcodeproj/project.pbxproj:Externals"
  "Flycast:Flycast/flycast/.gitmodules:Flycast/flycast:Flycast/Flycast.xcodeproj/project.pbxproj:core/deps"
)

fail=0
checked=0

for entry in "${CORES[@]}"; do
  IFS=':' read -r name gitmodules srcroot pbxproj extroot <<< "$entry"

  if [ ! -f "$gitmodules" ]; then
    echo "skip: $name — no $gitmodules" >&2
    continue
  fi
  if [ ! -f "$pbxproj" ]; then
    echo "ERROR: $name — pbxproj not found at $pbxproj" >&2
    fail=1
    continue
  fi

  # Each submodule's path (relative to srcroot), e.g. Externals/zstd/zstd
  # or core/deps/libchdr.
  while IFS= read -r relpath; do
    [ -z "$relpath" ] && continue

    # Top-level external dir the project references:
    #   <extroot>/<first component after extroot>
    rest="${relpath#"$extroot"/}"        # strip leading "Externals/" etc.
    firstcomp="${rest%%/*}"              # first remaining path component
    topdir="$extroot/$firstcomp"

    # Is this external referenced by the Xcode project? If not, it isn't
    # compiled/included on macOS and is allowed to be absent.
    if ! grep -q "$topdir" "$pbxproj"; then
      continue
    fi

    checked=$((checked + 1))
    inner="$srcroot/$relpath"
    if [ ! -d "$inner" ] || [ -z "$(ls -A "$inner" 2>/dev/null)" ]; then
      echo "ERROR: [$name] external '$topdir' is referenced by the Xcode project" >&2
      echo "       but its source tree '$inner' is missing or empty." >&2
      echo "       The flattened submodule was committed without its upstream source." >&2
      echo "       Re-vendor it as plain files at the pinned commit (see .gitmodules / upstream)." >&2
      fail=1
    fi
  done < <(grep 'path = ' "$gitmodules" | sed -E 's/.*path = //')
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "OK: all Xcode-referenced core externals have non-empty source trees ($checked checked)."
