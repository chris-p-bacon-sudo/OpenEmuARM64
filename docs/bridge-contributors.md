# Contributing to the Libretro Bridge

The libretro bridge (`feat/libretro-bridge`) is developed on its own long-running integration branch, separate from `main`. If your change touches bridge code, follow the rules below — the standard "branch from `main`" workflow in `CONTRIBUTING.md` does not apply here.

## Branch rules

| Rule | Why |
|------|-----|
| Branch from `feat/libretro-bridge`, not `main` | `main` and `feat/libretro-bridge` diverged at `35581e7e`. Branching from `main` pulls in ~30 unrelated commits and makes your diff unreadable. |
| Open your PR against `feat/libretro-bridge` | PRs against `main` will be closed — bridge work lands on `main` in one batch when the bridge ships. |
| Keep PRs scoped to one concern | The bridge is already a large diff; unfocused PRs make review harder. |

## What counts as "bridge code"

- `OELibretroCoreTranslator.m` and its header
- `OELibretroGameCore.m` and its header
- Anything under `OpenEmu-SDK/OpenEmuBase/` that uses `libretro.h` types
- The `OELibretroGameCoreHelper` protocol and related broker/IPC plumbing

If your change only touches a standalone emulator core (e.g. Flycast, mGBA) and doesn't touch the translator or core protocol, branch from `main` as normal.

## Workflow

```bash
# 1. Sync the bridge branch
git fetch origin
git checkout feat/libretro-bridge
git merge origin/feat/libretro-bridge

# 2. Create your branch from the bridge branch
git checkout -b feat/your-description

# 3. Make your change, build, commit
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
git add -p
git commit -m "feat: your description"

# 4. Push and open a PR targeting feat/libretro-bridge
git push -u origin feat/your-description
gh pr create --repo nickybmon/OpenEmu-Silicon \
  --base feat/libretro-bridge \
  --title "feat: your description" \
  --body "..."
```

## Recovering from a wrong base branch

If you branched from `main` by mistake and your PR shows thousands of changed files:

1. Find the commits that contain only your actual changes: `git log feat/libretro-bridge..HEAD`
2. Note those commit SHAs
3. Close the current PR
4. Create a new branch from `feat/libretro-bridge`
5. Cherry-pick your commits: `git cherry-pick <sha1> <sha2> ...`
6. Push the new branch and open a fresh PR against `feat/libretro-bridge`
