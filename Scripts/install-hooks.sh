#!/usr/bin/env bash
# Scripts/install-hooks.sh — wire this clone's git hooks to the tracked .githooks/ directory.
#
# Usage:  ./Scripts/install-hooks.sh
#
# Run once per fresh clone or worktree. Re-running is safe (idempotent).
# To uninstall:  git config --unset core.hooksPath

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -d .githooks ]; then
  echo "error: .githooks directory not found at $REPO_ROOT" >&2
  exit 1
fi

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "Hooks installed:"
echo "  core.hooksPath = $(git config core.hooksPath)"
echo ""
echo "Active hooks:"
for h in .githooks/*; do
  [ -f "$h" ] && echo "  - $(basename "$h")"
done
echo ""
echo "Bypass a hook for one push:  git push --no-verify"
echo "Disable hooks for this clone: git config --unset core.hooksPath"
