# CLAUDE.md — OpenEmu-Silicon

This file is read at the start of every Claude Code session for this project. Follow everything here before doing any work.

---

## Project Overview

**OpenEmu-Silicon** is a native Apple Silicon port of [OpenEmu](https://openemu.org), the beloved macOS multi-system emulator. It was originally derived from `bazley82/OpenEmuARM64`, which did the foundational work of porting all 25 emulation cores to ARM64. This project has since diverged into its own independent line of development.

**This repo:** `nickybmon/OpenEmu-Silicon` (primary, standalone)
**Primary workspace:** `OpenEmu-metal.xcworkspace` (Metal renderer — use this, not the legacy `.xcworkspace`)

**Lineage note:** Built on `bazley82/OpenEmuARM64` (Metal renderer, macOS 26 fixes) over `Azyzraissi/OpenEmu` (OpenGL, no UI changes). This project has diverged and is independently maintained.

---

## Never Do This

- Never commit directly to `main` or `master` **unless** the direct-commit rule below applies
- Never push a branch without opening a PR in the same step — a branch with no PR looks like abandoned work
- Never reuse a merged branch — new commits on a merged branch have no PR and are invisible to reviewers
- Never force-push to `main`
- Never open a duplicate issue — run `gh issue list` first; if the problem is tracked, comment on it
- Never write type prefixes (`fix:`, `feat:`, `note:`, `bug:`) in issue titles — labels carry the type
- Never leave a resolved issue open — close immediately with `gh issue close #N` and a commit reference
- Never commit `OEGoogleDriveSecrets.swift` or any file containing OAuth credentials, API keys, or tokens
- Never test a core change without reinstalling the plugin and re-signing it — DerivedData changes are silently shadowed by the installed core in `~/Library/Application Support/OpenEmu/Cores/`
- Never modify `project.pbxproj` manually unless you know exactly what you're changing — it's a large generated file and merge conflicts are painful
- Never rewrite large files wholesale — make surgical changes; this applies especially to `.pbxproj` and large ObjC files
- Never attempt to re-initialize core directories as git submodules — they are flattened regular directories, not active submodules
- Never add dependencies without discussion — the project intentionally has no package manager
- Never remove or rename existing core directories — they are referenced by the Xcode project
- Never commit build log files — they are noise; `.gitignore` is already updated
- Never commit large binaries (`.zip`, `.tar.gz`, executables) — these belong in GitHub Releases
- Never change `MACOSX_DEPLOYMENT_TARGET` below `11.0` — this is the ARM64 baseline

---

## Tech Stack

- **Language:** Swift 6.2.4 + Objective-C (mixed codebase)
- **Build system:** Xcode 26.3 (xcodebuild)
- **Renderer:** Metal (primary), OpenGL (legacy)
- **Architecture target:** ARM64 (Apple Silicon native)
- **Deployment target:** macOS 11.0+
- **Dependency management:** Git submodules (flattened to regular dirs — no active submodule tracking)

---

## Repo Structure

```
OpenEmu-Silicon/
├── OpenEmu/                  # Main app — 143 Swift files + ObjC, XIBs, assets
├── OpenEmu-metal.xcworkspace # PRIMARY workspace (use this)
├── OpenEmu.xcworkspace       # Legacy workspace (avoid)
├── OpenEmu-SDK/              # Core SDK (shared types, protocols)
├── OpenEmuKit/               # UI kit / shared components
├── OpenEmu-Shaders/          # Metal shader library
├── Vendor/                   # XADMaster, UniversalDetector
│
├── [25 emulator core directories]   # One folder per system (NES, SNES, N64, GBA, PSX, etc.)
│                                    # Run `ls -d */` to enumerate
│
├── Scripts/                  # Build/utility scripts
├── Releases/                 # Release artifacts
└── [build_*.log files]       # Legacy build logs — candidates for removal
```

---

## Build Instructions

Open the workspace in Xcode:
```bash
open OpenEmu-metal.xcworkspace
```

Or build from the command line:
```bash
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

---

## Git Workflow

**Branch strategy:**
- `main` — default branch. All PRs target `main`. Direct commits allowed only per the rule below.
- `master` — mirrors upstream (`bazley82/OpenEmuARM64`) only. Never commit here.
- Feature/fix branches: `fix/description`, `feat/description`, `chore/description`
- One branch per concern → one PR per branch

**Direct commit to `main` — when it's OK:**

Direct commits (no PR) are allowed when **all three** conditions are met:
1. The change is CI/workflow files, config, or docs only — no Swift, ObjC, or build system code
2. It's a single focused fix (not bundling multiple concerns)
3. It's actively unblocking an in-progress task (e.g. iterating on a failing workflow run)

Branch + PR is required for everything else: any app code change, build system edits, security/entitlement config, or anything worth a review record.

**The full loop — every time, no exceptions:**

```bash
# 1. Sync before starting any new work
git checkout main
git fetch origin && git merge origin/main

# 2. New branch — one per concern, always from main
git checkout -b fix/your-description

# 3. Do the work, commit — include Fixes #N in body when resolving an issue
git add -p
git commit -m "fix: short description

Fixes #N"

# 4. Push AND open a PR in the same step — never one without the other
git push -u origin fix/your-description
gh pr create --repo nickybmon/OpenEmu-Silicon \
  --base main \
  --title "fix: your-description" \
  --body "..."

# 5. After PR merges — sync and delete local branch
# (origin branch auto-deletes on merge — repo setting is already enabled)
git checkout main
git fetch origin && git merge origin/main
git branch -d fix/your-description
```

**Branch rules (non-negotiable for agents and humans):**

| Rule | Why |
|------|-----|
| Always branch from `main` | Prevents tangled history |
| One branch = one concern | Keeps PRs reviewable and focused |
| Never reuse a merged branch | New commits on a merged branch have no PR — invisible to reviewer |
| Push and open a PR in the same step | A branch with no PR looks like abandoned work |
| Branch name must match its content | If scope changes mid-work, start a new branch |
| Delete local branch after merge | Run `git branch -d` immediately after syncing |
| Never force-push to `main` | Destructive; breaks history |

**Commit message format:** `<type>: <description>`

| Type | When |
|------|------|
| `fix:` | Bug fix |
| `feat:` | New feature |
| `chore:` | Cleanup, tooling, config |
| `docs:` | Documentation only |
| `refactor:` | Restructure with no behavior change |

**Linking issues:**
- `Fixes #N` in commit body — auto-closes issue on merge to `main`
- `Related to #N` — soft link, issue stays open

**Labels (apply directly — you own this repo):**

| Change type | Label |
|-------------|-------|
| Bug fix | `bug` |
| New feature | `enhancement` |
| Docs only | `documentation` |
| Needs discussion | `question` |

**Automation in place:**
- `.git/hooks/pre-push` — blocks accidental direct pushes to `upstream master`
- `.git/hooks/prepare-commit-msg` — warns if on `main`, injects commit format guide
- `.github/PULL_REQUEST_TEMPLATE.md` — pre-fills PR structure and checklist
- GitHub repo setting: branches auto-delete after PR merge

**If you re-clone:** git hooks are not committed. Recreate them or ask Claude to restore them from this file.

---

## Session Start Convention

**Every coding session must start on a dedicated branch — never work directly on `main`.**

Run `/start` at the beginning of each session. It will:
1. Sync `main` from origin
2. Pull the live issue list and project board so you have full context
3. Create the correct branch for the work at hand

If you already know the task before running `/start`, name the branch accordingly. If not, `/start` will ask.

The only exception is the narrow "direct commit to `main`" rule documented in the Git Workflow section — CI/config/docs-only, single-concern, actively unblocking.

---

## Slash Commands

Custom commands live in `.claude/commands/`. Invoke with `/command-name`.

| Command | What it does |
|---------|--------------|
| `/start` | Session kickoff: sync main, pull live issue/board state, create working branch |
| `/ship` | Full git loop: sync main, create branch, commit with correct format, push, open PR, update project board |
| `/review <PR_NUMBER>` | PR review flow: gh pr checkout, build check, list test behaviors from the PR description, report results |
| `/new-issue` | Guided issue creation: search for duplicates first, select template, enforce title rules, apply labels |
| `/triage-issue <N>` | Review a bug report or feature request: check completeness, post a comment asking for missing details/screenshots, apply labels |
| `/prep-release [X.Y.Z]` | Full release prep: bump version, build check, commit, check release notes, run pre-flight, hand off release script command |

---

## Release Process

Releases are built and signed **locally** using `Scripts/release.sh`. There is no CI release workflow — it was removed in April 2026 because it was slower than local builds and introduced signing bugs (missing entitlements, Sparkle signature mismatches).

### Before running the release script

1. Bump the version in Xcode: `OpenEmu` target → General → Version (e.g. `1.0.4`) and Build Number
2. Ensure your notarytool credentials are stored: `xcrun notarytool store-credentials OpenEmu`
3. Ensure `gh` is authenticated: `gh auth status`

### Run the release

```bash
# Minimal — appcast entry will have a placeholder description
./Scripts/release.sh 1.0.4

# With release notes (markdown file → converted to HTML in appcast)
./Scripts/release.sh 1.0.4 Releases/notes-1.0.4.md
```

The script does everything in one shot:
1. `xcodebuild archive` (Release config, Developer ID signed, hardened runtime)
2. Re-signs all binaries inside-out with entitlements, notarizes, staples
3. Creates the DMG from the stapled `.app`
4. Runs `sign_update` on that exact DMG to get the EdDSA signature
5. Prepends a new entry to `appcast.xml` with the correct signature and length
6. Creates a **draft** GitHub Release and uploads the DMG
7. Updates `Casks/openemu-silicon.rb` with the new version and DMG SHA256
8. Commits and pushes the updated `appcast.xml` and Homebrew cask together

### After the script finishes

- Review the draft release on GitHub
- Edit release notes if the script used a placeholder
- When ready: `gh release edit vX.Y.Z --draft=false --repo nickybmon/OpenEmu-Silicon`

### Never do this manually

- Never hand-edit the `sparkle:edSignature` or `length` in `appcast.xml` — always let `sign_update` generate them from the actual DMG that was uploaded
- Never publish a GitHub Release without confirming the appcast is committed and pushed — the update will fail if the appcast hasn't been updated yet

---

## Testing PRs Locally Before Merging

Always test PRs locally before merging. The standard flow:

### 1. Check out the PR branch

```bash
# Preferred — gh looks up the branch name for you
gh pr checkout <PR_NUMBER> --repo nickybmon/OpenEmu-Silicon

# Example
gh pr checkout 54 --repo nickybmon/OpenEmu-Silicon
```

This fetches the branch if needed and checks it out. `git branch` will confirm you're on it.

### 2. Build from terminal

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30
```

A clean build with no errors is the minimum bar before testing.

### 3. Run the app from terminal

```bash
open ~/Library/Developer/Xcode/DerivedData/OpenEmu-*/Build/Products/Debug/OpenEmu.app
```

Or use Spotlight / your app launcher — after a Debug build, the app lives in DerivedData and can be launched like any app.

### 4. Test multiple PRs in isolation (worktrees)

To test two branches side by side without switching back and forth:

```bash
git worktree add ../openemu-pr54 fix/flycast-input-crash
cd ../openemu-pr54
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Each worktree is a separate directory with its own build — no stashing needed.

### 5. Return to main when done

```bash
git checkout main

# If you used a worktree, clean it up
git worktree remove ../openemu-pr54
```

### Core plugin builds (Flycast and others)

Building the main `OpenEmu` scheme does **not** update emulator cores in
`~/Library/Application Support/OpenEmu/Cores/`. Cores are loaded from there
at runtime and **will silently shadow any changes in DerivedData**.

After changing code in a core (e.g. Flycast), you must:

1. Build the core-specific scheme (e.g. `OpenEmu + Flycast`)
2. Manually replace the installed plugin and re-sign it:

```bash
DERIVED=$(find ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/Flycast.oecoreplugin -maxdepth 0 | head -1)
DEST=~/Library/Application\ Support/OpenEmu/Cores/Flycast.oecoreplugin
rm -rf "$DEST"
cp -R "$DERIVED" "$DEST"
codesign --force --sign - "$DEST"
```

Substitute the core name as needed. Without this step, the app always runs
the previously installed (stale) core binary regardless of what was just built.

### When Claude reviews a PR, it should always provide

1. The exact `gh pr checkout` command for that PR number
2. Any PR-specific build steps (e.g. BIOS files needed, core reinstall required)
3. The specific behaviors to verify from the PR's test plan

---

## Project Board

**OpenEmu-Silicon Project** — https://github.com/users/nickybmon/projects/3

Tracks the seven major open work items. Status rules:
- When starting work on a board item → set status to `In Progress`
- When closing an issue that's on the board → set status to `Done`

```bash
# Update a board item's status
gh project item-edit --id <PVTI_...> --project-id PVT_kwHODZJ49M4BSxR1 \
  --field-id PVTSSF_lAHODZJ49M4BSxR1zhANP7Q \
  --single-select-option-id <option-id>
# Option IDs: Todo=f75ad846  In Progress=47fc9ee4  Done=98236657
```

To get item IDs: `gh project item-list 3 --owner nickybmon --format json`

---

## Issue Tracker Usage

**Primary tracker** (`nickybmon/OpenEmu-Silicon/issues`) — the project's main issue tracker for bugs, build fixes, core integration work, feature requests, and release checklists.

**Issue templates** (`.github/ISSUE_TEMPLATE/`):

| Template | Use when |
|----------|----------|
| `bug_report` | Runtime crash, wrong behavior, build failure at runtime |
| `feature_request` | New core, new capability, meaningful improvement |
| `core_integration` | Core fails to build, missing from workspace, needs ARM64 porting |
| `checklist` | Release checklist or multi-step milestone — one per milestone max |

**Labels:**
- `in-progress` — actively working on it
- `needs-testing` — fix done, needs verification
- `ready-to-pr` — work ready for PR review
- `core: NES/C64/Atari/SNES/N64/Sega/other` — which system
- `ui / shaders / cloud-sync / arm64` — which area

---

## Issue Hygiene Rules (for agents and humans)

These rules exist because previous AI-assisted sessions created messy, duplicate, and mislabeled issues. Follow them exactly.

### Before opening an issue

1. **Search first.** Run `gh issue list --repo nickybmon/OpenEmu-Silicon --state open` and check if the problem is already tracked. If it is, add a comment — do not open a duplicate.
2. **One issue per concern.** If two cores have the same root cause and fix, open one issue covering both. Do not open one issue per core.
3. **Only one checklist per milestone.** If a release checklist is already open, update it — never open a second one.

### Titles

- **No type prefixes in titles.** Never write `note:`, `fix:`, `feat:`, `bug:` etc. in the issue title. Labels carry the type. The title describes the problem.
- Good: `PokeMini — OpenEmuBase header missing in standalone build`
- Bad: `note: PokeMini — needs workspace integration for OpenEmuBase headers`

### Closing issues

- **Close resolved issues immediately.** The moment a fix is committed, close the issue with `gh issue close #N --repo nickybmon/OpenEmu-Silicon --comment "Resolved in commit <sha>. <one line summary>."` — do not leave it open for a later cleanup pass.
- **Use closing keywords in commit messages.** Every commit that resolves an issue must include `Fixes #N` or `Closes #N` in the commit body (not just the subject line):
  ```
  fix: add Mupen64Plus to workspace and fix ARM64 dynarec build

  Fixes #11
  ```
- **Close superseded issues immediately.** If you create a more comprehensive issue that replaces an older one, close the old one in the same session with a comment referencing the new issue number.

### What does NOT belong as an issue

- Observations or open questions that aren't actionable yet → put in a PR comment or a comment on a related issue
- Things already documented in CLAUDE.md
- Ephemeral session notes

---

## Pre-Commit Checks

Before every commit on Swift/ObjC changes:
```bash
# Build check (catches compile errors)
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -20
```

There is no lint/format CI configured yet — this is a contribution opportunity.

---

## Verification

**Before marking any task complete, verify your work. Verification is not optional.**

For every change, run the build check and confirm it passes:
```bash
xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -20
```

For core changes, you must also reinstall and re-sign the plugin before testing:
```bash
DERIVED=$(find ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/[CoreName].oecoreplugin -maxdepth 0 | head -1)
DEST=~/Library/Application\ Support/OpenEmu/Cores/[CoreName].oecoreplugin
rm -rf "$DEST" && cp -R "$DERIVED" "$DEST" && codesign --force --sign - "$DEST"
```
Substitute the actual core name. Without this, the app always runs the previously installed binary.

Before stating that a task is done, report:
1. Build result — passed / failed / warnings
2. Whether the plugin was reinstalled (for core changes)
3. What was manually verified in the running app, or why manual verification was not possible

If the build fails, fix it before closing the task. Do not hand off a broken build.

---

## Key Files in the Main App

| File | Purpose |
|------|---------|
| `OpenEmu/AppDelegate.swift` | App entry point |
| `OpenEmu/GameDocument.swift` | Core game session management |
| `OpenEmu/OEGameViewController.swift` | Game view controller |
| `OpenEmu/LibraryController.swift` | Main library UI |
| `OpenEmu/OECorePlugin.swift` | Core plugin loading |
| `OpenEmu/OEGameCore.swift` | Base game core protocol |
| `OpenEmu/broker/` | Core broker process (sandboxing) |

---

## Current Work State

Do not rely on a static snapshot in this file. At the start of any work session, pull live state:

```bash
# Open issues
gh issue list --repo nickybmon/OpenEmu-Silicon --state open

# Project board
gh project item-list 3 --owner nickybmon --format json
```

Read the output before deciding what to work on. The board and issue tracker are the source of truth — this file is not.

---

## macOS 26 (Tahoe) Compatibility

All known macOS 26 compatibility fixes are applied in this repo (XIB binding crash, missing entitlement, core signing). If you install cores that predate the signing fix, sign them manually:
```bash
codesign --force --sign - ~/Library/Application\ Support/OpenEmu/Cores/*.oecoreplugin
```
Cores installed after the fix are signed automatically by `CoreUpdater`.

---

## Security Notes

- `OEGoogleDriveSecrets.swift` is gitignored — never commit it. The template is `OEGoogleDriveSecrets.template.swift`.
- `OEGoogleDriveConfig.swift` uses `"YOUR_CLIENT_ID_HERE"` placeholders — safe to commit.
- `fast_relink.sh`, `apply_icon.sh`, `process_icon.swift` are utility scripts that use env vars / CLI args — no hardcoded paths remain.
- Do not commit any file containing real OAuth credentials, API keys, or tokens.

---

## License Summary

**Main app** (`OpenEmu/`, `OpenEmu-SDK/`, `OpenEmuKit/`, `OpenEmu-Shaders/`): **BSD 2-Clause**
- Contribute freely; preserve copyright headers on all files you touch
- Add this header to any new files: `// Copyright (c) 2026, OpenEmu Team` + standard BSD text

**Emulator cores**: mixed open source licenses

| Core(s) | License |
|---------|---------|
| mGBA | MPL 2.0 — file-level copyleft, compatible with BSD |
| Gambatte, DeSmuME, Mupen64Plus, SNES9x, Reicast, picodrive | GPL v2 — modifications must stay GPL v2 |
| Bliss, XADMaster | LGPL 2.1 |
| JollyCV | BSD 2-Clause |

**Critical:** `picodrive` has a **non-commercial clause** — the project cannot be sold or used in a commercial product. This is already satisfied (free community project), but never charge for a build that includes picodrive.

No CLA exists. Contributions are covered by the license of the files you touch.

---

## Context

This is a community revival project. The original OpenEmu project went dormant. This ARM64 fork represents significant work to bring it back to life on modern Apple Silicon Macs. Contributions should be made with that spirit in mind — pragmatic, incremental, and focused on making the app actually usable for players.
