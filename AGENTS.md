# AGENTS.md — OpenEmu-Silicon

Instructions for AI coding agents (Claude Code, Cursor, Copilot, etc.) working in this repository.

---

## Read First

Before doing any work, read this file fully. It is the authoritative source for how this project is structured and how changes should be made.

---

## About This Project

OpenEmu-Silicon is a community-maintained fork of OpenEmu, rebuilt to run natively on Apple Silicon (arm64) without Rosetta. It descends from:

- [OpenEmu/OpenEmu](https://github.com/OpenEmu/OpenEmu) — the original project
- [bazley82/OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64) — the foundational ARM64 port

The goal is to honor the original OpenEmu spirit — a beautifully designed, first-class native macOS game emulation frontend — while making it work reliably on M-series Macs with modern macOS and Swift.

**The maintainer is not a professional developer.** If you are writing explanations, commit messages, or comments, please use plain language. Avoid jargon where a plain word works just as well.

---

## Ground Rules

1. **Never commit directly to `main`.** All work goes through feature branches → PRs → `main`.
2. **Branch from `main`, open PRs against `main`.** There is no staging branch.
3. **Build before committing.** Run an `xcodebuild` check on any Swift/ObjC changes before staging a commit.
4. **Don't rewrite files wholesale.** This is a large, complex Xcode project. Make surgical changes. Rewriting `.pbxproj` or large ObjC files without understanding them will break the build.
5. **Respect the flattened architecture.** Submodule directories (`Nestopia/`, `BSNES/`, etc.) are regular directories — do not attempt to re-initialize them as git submodules.
6. **Do not commit build artifacts.** No `.o` files, derived data, `.app` bundles, build logs, or compiled executables.
7. **Note AI assistance in commit messages.** If a commit was written or significantly assisted by an AI tool (Claude, Cursor, Copilot, etc.), say so in the commit message. Example: `fix: resolve VICE dlopen crash (assisted by Claude Code)`.

---

## Language and Tooling

- **Swift 6.2.4** — strict concurrency is enforced. Use `@MainActor`, `Sendable`, and structured concurrency correctly.
- **Objective-C** — many core files are ObjC. Bridge headers are in place. Don't break them.
- **Xcode 26.3** — use `xcodebuild` for CLI builds. The primary workspace is `OpenEmu-metal.xcworkspace`.
- **No package manager** — no SPM, no CocoaPods, no Carthage. Dependencies are vendored or flattened submodules.

---

## Build Command

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30
```

A clean build is the definition of "passing." Run this before every commit touching source files.

---

## File Organization

| What you're touching | Where it lives |
|----------------------|---------------|
| Main app logic | `OpenEmu/*.swift` and `OpenEmu/*.m` |
| Shared protocols/types | `OpenEmu-SDK/` |
| UI components | `OpenEmuKit/` |
| Metal shaders | `OpenEmu-Shaders/` |
| Emulator cores | `[CoreName]/` (top-level dirs) |
| Build and utility scripts | `Scripts/` |
| Xcode project | `OpenEmu/OpenEmu.xcodeproj/` |

---

## Supported Cores (as of 2026)

| System | Core |
|--------|------|
| Atari 2600 | Stella |
| Atari 5200 | Atari800 |
| Atari 7800 | ProSystem |
| Atari Lynx | Mednafen |
| ColecoVision | JollyCV |
| Commodore 64 | VICE |
| Famicom Disk System | Nestopia |
| Game Boy / GBC | Gambatte |
| Game Boy Advance | mGBA |
| Game Gear | Genesis Plus GX |
| Intellivision | Bliss |
| Nintendo (NES) | Nestopia, FCEU |
| Nintendo 64 | Mupen64Plus |
| Nintendo DS | DeSmuME |
| Odyssey² / Videopac+ | O2EM |
| Pokémon Mini | PokeMini |
| Sega 32X | picodrive |
| Sega CD / Mega CD | Genesis Plus GX |
| Sega Dreamcast | Flycast |
| Sega Genesis / Mega Drive | Genesis Plus GX |
| Sega Master System | Genesis Plus GX |
| Sega Saturn | Mednafen |
| Sony PlayStation | Mednafen |
| Super Nintendo (SNES) | BSNES, Snes9x |
| Vectrex | VecXGL |
| WonderSwan | Mednafen |
| 3DO | 4DO |

---

## Branch and PR Rules

These rules exist because AI-assisted sessions have previously created orphaned branches, duplicate issues, and commits without PRs. Follow them exactly.

**Branches:**

| Rule | Why |
|------|-----|
| Always branch from `main` | Prevents tangled history |
| One branch = one concern | Keeps PRs focused and reviewable |
| Never reuse a merged branch | New commits on a merged branch have no PR — invisible |
| Branch name must match content | If scope changes, start a new branch |
| Delete local branch after merge | `git branch -d` immediately after syncing main |

**PRs:**

- **Target branch:** `main` on `nickybmon/OpenEmu-Silicon`
- **Push and open a PR in the same step — never push without immediately opening a PR**
- **PR title format:** `fix: description` / `feat: description` / `chore: description`
- **Use the PR template** — `.github/PULL_REQUEST_TEMPLATE.md` auto-populates. Fill every section.
- Each PR addresses one issue or one logical change — no bundled unrelated fixes
- Reference the issue with `Fixes #N` in the commit body (auto-closes on merge) or `Related to #N` (soft link)
- For core-specific fixes, note which systems are affected

**Every PR description must include a "How to test locally" section** with exact copy-paste commands.

**If the PR only touches main app code** (`OpenEmu/`, `OpenEmuKit/`, `OpenEmu-SDK/`):

```
## How to test locally

# 1. Check out this PR
gh pr checkout <N> --repo nickybmon/OpenEmu-Silicon

# 2. Build
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20

# 3. Launch
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app
```

**If the PR touches a core plugin** (anything inside `Dolphin/`, `Flycast/`, etc.):

```
## How to test locally

# 1. Check out this PR
gh pr checkout <N> --repo nickybmon/OpenEmu-Silicon

# 2. Build the core scheme (the main OpenEmu scheme does not build core plugins)
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme <CoreName> \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20

# 3. Install the core (quits OpenEmu automatically, then copies binary + Info.plist)
./Scripts/install-core.sh <CoreName>

# 4. Launch
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app
```

**Never use `cp -Rf` to install a core plugin.** macOS merges bundle directories rather than replacing them — old files silently stay in place. Always use `./Scripts/install-core.sh` or `cp -f` on individual files. Always quit OpenEmu before installing — the helper process holds the binary open while running.

Replace `<N>` with the actual PR number and `<CoreName>` with the scheme name (e.g. `Dolphin`, `Flycast`). Add any PR-specific setup steps below — which ROM or system to test, any BIOS files required, any permissions to revoke first, or specific behaviors to verify from the QA spec.

---

## Issue Tracker

The issue tracker at `nickybmon/OpenEmu-Silicon` is the primary place for bug reports, feature requests, core integration work, and release checklists.

**Issue templates** — always use the appropriate template:

| Template | Use when |
|----------|----------|
| `bug_report` | Runtime crash, wrong behavior |
| `feature_request` | New core, new capability |
| `core_integration` | Core fails to build, missing from workspace, needs ARM64 porting |
| `checklist` | Release milestone tracking — one open checklist per milestone max |

**Issue hygiene rules (non-negotiable):**

1. **Search before opening.** Run `gh issue list --repo nickybmon/OpenEmu-Silicon --state open` first. If the problem is already tracked, comment — don't open a duplicate.
2. **No type prefixes in titles.** Never write `note:`, `fix:`, `feat:`, `bug:` in the issue title. Labels carry the type. The title describes the problem.
   - Good: `PokeMini — OpenEmuBase header missing in standalone build`
   - Bad: `note: PokeMini — needs workspace integration`
3. **One issue per concern.** Same root cause + same fix = one issue covering both.
4. **Close resolved issues immediately.** The moment a fix is committed, run: `gh issue close #N --repo nickybmon/OpenEmu-Silicon --comment "Resolved in <sha>."` Do not leave issues open for a later cleanup pass.
5. **Close superseded issues immediately.** If you open a more comprehensive issue that replaces an older one, close the old one in the same session.
6. **Only one checklist per milestone.** If one is already open, update it.

---

## What NOT to Do

- Do not modify `project.pbxproj` manually unless you know exactly what you're changing — it's a large generated file and merge conflicts are painful
- Do not add new dependencies without discussion — the project intentionally has no package manager
- Do not remove or rename existing core directories — they are referenced by the Xcode project
- Do not commit the `build_*.log` files that exist at root — they are legacy artifacts
- Do not change `MACOSX_DEPLOYMENT_TARGET` below `11.0` — this is the ARM64 baseline
- Do not commit `OEGoogleDriveSecrets.swift` — it is gitignored for a reason; it holds real OAuth credentials
- Do not add debug `+load` / `+initialize` methods that write to `/tmp` or hardcode local paths
- Do not commit large binaries (`.zip`, `.tar.gz`, compiled executables) — these belong in GitHub Releases
- Do not commit directly to `main` under any circumstances

---

## License Rules

The main app is **BSD 2-Clause**. Emulator cores are mostly **GPL v2**. Key rules:

1. **Preserve all copyright headers** — never strip or modify the license block at the top of any file
2. **Add a header to new files** you create in `OpenEmu/`, `OpenEmu-SDK/`, or `OpenEmuKit/`:
   ```
   // Copyright (c) 2026, OpenEmu Team
   //
   // Redistribution and use in source and binary forms, with or without
   // modification, are permitted provided that the following conditions are met:
   // ...
   ```
3. **picodrive is non-commercial** — never charge for a build that includes it
4. **No CLA** — your contributions are covered by the license of the files you touch

---

## Testing PRs Locally Before Merging

Before merging any PR, check it out locally, build, and verify the behaviors described in the PR's test plan.

**When reviewing a PR, always provide:**
1. The exact `gh pr checkout` command for that PR number
2. Any PR-specific setup (e.g. BIOS files needed, permissions to revoke first)
3. The specific behaviors to verify from the PR's test plan

### Check out a PR branch

```bash
# gh looks up the branch name automatically
gh pr checkout <PR_NUMBER> --repo nickybmon/OpenEmu-Silicon

# Example
gh pr checkout 54 --repo nickybmon/OpenEmu-Silicon
```

### Build

For main app changes:

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30
```

For core plugin changes, use the core's own scheme (e.g. `Dolphin`, `Flycast`):

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme Dolphin \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30
```

The main `OpenEmu` scheme does not build core plugins. Building the wrong scheme means you're testing old code.

### Install a core plugin after building

Use the install script — it quits OpenEmu first and copies files correctly:

```bash
./Scripts/install-core.sh Dolphin
```

**Never use `cp -Rf` to install a core plugin.** macOS merges bundle directories rather than replacing them, so old files silently stay in place. Always use the script or `cp -f` on individual files. Always quit OpenEmu before installing — the helper process holds the binary open while running and `cp` will silently fail to replace it.

### Launch the built app

```bash
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app
```

Or launch from Spotlight — after a Debug build the app is registered and findable by name.

### Test multiple PRs in isolation (worktrees)

```bash
# Create an isolated copy of the repo on a PR branch
git worktree add ../openemu-pr54 fix/flycast-input-crash

# Build and run from that directory
cd ../openemu-pr54
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build

# Clean up when done
git worktree remove ../openemu-pr54
```

### Return to main

```bash
git checkout main
```

---

## Quick Reference

```bash
# Open in Xcode
open OpenEmu-metal.xcworkspace

# --- Start of every new piece of work ---
git checkout main
git fetch origin && git merge origin/main

# Create a feature branch
git checkout -b fix/your-description

# Build check before committing
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -10

# Stage and commit (note AI tools used if applicable)
git add -p
git commit -m "fix: description (assisted by Claude Code)"

# Push and open a PR — always in the same step, never one without the other
git push -u origin fix/your-description
gh pr create --repo nickybmon/OpenEmu-Silicon --base main --title "fix: your-description" --body "..."
```
