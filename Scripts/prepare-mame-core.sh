#!/usr/bin/env bash
# Prepare the MAME headless source used by MAME/MAME.xcodeproj.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
MAME_DIR="$REPO_ROOT/MAME"
DEPS_DIR="$MAME_DIR/deps"
SRC_DIR="$DEPS_DIR/mame"
PATCH_FILE="$MAME_DIR/patches/mame-headless-clang21-apple.patch"
REVISION="4fc1f9f16b0dfba6be670367330028635613b04b"
REMOTE="https://github.com/stuartcarnie/mame.git"

mkdir -p "$DEPS_DIR"

if [ ! -e "$SRC_DIR/.git" ]; then
  echo "Cloning stuartcarnie/mame into $SRC_DIR..."
  git clone --no-tags "$REMOTE" "$SRC_DIR"
fi

cd "$SRC_DIR"

git fetch --no-tags origin "$REVISION"
git checkout --detach "$REVISION"

if git apply --check "$PATCH_FILE" >/dev/null 2>&1; then
  echo "Applying Apple Silicon / Clang 21 patch..."
  git apply "$PATCH_FILE"
elif git apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
  echo "Patch already applied."
else
  echo "error: patch does not apply cleanly and is not already applied: $PATCH_FILE" >&2
  git status --short >&2 || true
  exit 1
fi

echo "MAME source ready at $SRC_DIR"
