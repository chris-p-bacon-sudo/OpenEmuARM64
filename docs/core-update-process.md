# Core Update Process — OpenEmu-Silicon

_Last updated: 2026-04-17_

This document explains how core updates work in this project: where binaries come from, how to evaluate whether a given build is safe to ship, and how to publish an update.

There are two kinds of core updates, and they use different processes:

| Type | Cores | Process |
|------|-------|---------|
| **In-repo built** | Flycast, Dolphin, 4DO, DeSmuME, and other cores whose source lives in this repo | Use the `/release-core` command (see `.claude/commands/release-core.md`) |
| **Buildbot-sourced** | mGBA, Nestopia, Genesis Plus GX, Mednafen, SNES9x, and other cores pulled as pre-built binaries | Follow the process in this document |

The rest of this document covers **buildbot-sourced cores only**.

---

## Philosophy

OpenEmu-Silicon ships **curated, tested core binaries** — not live feeds from an external server. This means:

- Users always get a version the maintainer has personally verified.
- A bad upstream nightly never reaches users automatically.
- If something breaks, it can be rolled back by reverting a release.

This is a deliberate design choice. The libretro buildbot produces new ARM64 dylibs every day, but "built today" does not mean "tested today." Sourcing from the buildbot is fine — shipping whatever the buildbot produced this morning directly to users is not.

---

## Where Core Binaries Come From

This project does **not** build cores from source as part of the release process. That would require maintaining 20+ individual build environments and tracking ARM64 patches for each core.

Instead, cores are sourced from the **libretro buildbot** for macOS ARM64:

```
https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/
```

The buildbot compiles cores daily from the upstream source repos. The binaries are produced by the same teams that write the core code. For stable, mature cores (mGBA, Nestopia, Genesis Plus GX), the main branch rarely has regressions. For more active cores (Flycast, PPSSPP), more caution is warranted.

**Important:** The buildbot only exposes a `/latest/` directory. There is no `/stable/` channel for macOS ARM64 and no dated archive — once a new build replaces the old one, the previous version is gone. This is why we re-host binaries on GitHub Releases rather than pointing users directly at the buildbot.

---

## How to Evaluate a Build Before Adopting It

There is no automatic signal that tells you a build is safe. Use these checks:

### 1. Review upstream commits

Every core has a public GitHub repo. Before downloading a build, check what has been committed recently:

| Core | Upstream Repo |
|------|--------------|
| Flycast | https://github.com/flyinghead/flycast |
| mGBA | https://github.com/mgba-emu/mgba |
| Genesis Plus GX | https://github.com/ekeeke/Genesis-Plus-GX |
| Nestopia | https://github.com/rdanbrook/nestopia |
| SNES9x | https://github.com/snes9xgit/snes9x |
| Gambatte | https://github.com/sinamas/gambatte |
| Mupen64Plus-Next | https://github.com/libretro/mupen64plus-next |
| Mednafen (Beetle) | https://github.com/libretro/beetle-saturn-libretro (and siblings) |
| PPSSPP | https://github.com/hrydgard/ppsspp |
| PicoDrive | https://github.com/notaz/picodrive |

**Green flags:**
- Last commit was more than a week ago
- Recent commits are small fixes, not large refactors
- No open issues mentioning "crash" or "regression" in the last two weeks

**Yellow flags:**
- Active commits in the last 2-3 days
- A large merge or "WIP" commit recently landed

**Red flags:**
- An issue or commit explicitly mentioning a crash or regression in the last week
- A major version bump or architectural rewrite recently merged

### 2. Let the build age a few days

The buildbot timestamps tell you exactly when each core was compiled. A core built three days ago with no new upstream commits since is meaningfully safer than one built this morning. Regressions in nightly builds typically surface on the RetroArch forums or GitHub issues within 24-48 hours.

### 3. Check the community

Before pinning a build for a complex core (Flycast, PPSSPP, Mupen64Plus), spend 5 minutes searching:
- [RetroArch forums](https://forums.libretro.com) for the core name + "broken" or "regression"
- The core's GitHub Issues for anything opened in the last two weeks

### 4. Test it yourself

Download the `.dylib.zip`, place it in a test build, and run a game you know well for that system for 20-30 minutes. Check for:
- Boot and load without crash
- Audio and video look correct
- Save and load a save state
- Basic input works

This is the minimum bar. For a first release of a core, test more thoroughly.

---

## Picking the Right Build Date

Since the buildbot only exposes `latest`, the process is:

1. Check the upstream commit history — find the last date when the repo was quiet (no risky commits).
2. On that date, the buildbot would have compiled a clean build. You can't retrieve it now, but if today looks quiet, today's build is effectively from that quiet period.
3. If the last few days have been active, wait for things to settle before grabbing a build.

In practice: **check upstream commits first, then download if it looks safe.** Don't download and then check — you'll be tempted to use what you already have.

---

## How to Publish a Core Update

Once you have a binary you're confident in:

### Step 1 — Note the source

Record what you grabbed and when:
```
Core: Flycast
Buildbot date: 2026-04-10
Upstream repo: https://github.com/flyinghead/flycast
Last upstream commit reviewed: abc1234 (2026-04-08) — "fix: dreamcast bios path on macOS"
Tested on: macOS 15.4, M4 MacBook Pro
Test games: Sonic Adventure (NTSC), Jet Set Radio
Save states: verified working
```

### Step 2 — Package it

The binary from the buildbot is a raw `.dylib` inside a `.zip`. It needs to be wrapped as a `.oecoreplugin` bundle to be distributed. Use the existing plugin structure for the relevant core in this repo as a template — copy the `Info.plist`, update the version string, and replace the binary.

Zip the resulting `.oecoreplugin` as `CoreName.oecoreplugin.zip`.

### Step 3 — Publish to GitHub Releases

Upload the zip to a GitHub Release tagged `cores-vX.Y.Z` (or add to an existing cores release).

Use a release note like:
```
Flycast — buildbot snapshot 2026-04-10
Upstream: flyinghead/flycast @ abc1234
```

### Step 4 — Update the appcast

Edit `Appcasts/flycast.xml` (or the relevant file) to point to the new release URL and update the `sparkle:version` and `length` fields.

### Step 5 — Update docs/cores.md

Update the version entry for the core and the last-updated date.

### Step 6 — Open a PR

Title: `chore: update Flycast to buildbot snapshot 2026-04-10`

Include in the PR description:
- The upstream commit reviewed
- What you tested
- A link to the new GitHub Release

---

## How Often to Update

There's no fixed schedule. Update a core when:

- A known bug affecting users has been fixed upstream
- A significant compatibility improvement has landed
- The current version has a crash or regression you've confirmed

For stable cores (mGBA, Nestopia, Genesis Plus GX), once or twice a year is reasonable. For actively developed cores (Flycast, PPSSPP), more frequently as needed.

Do **not** update cores on a fixed schedule just to stay "current." Every update is a potential regression and should be justified by a specific improvement.

---

## What NOT to Do

- **Do not point users directly at the buildbot.** A live feed from an external server means users get whatever was compiled this morning, with no testing and no rollback.
- **Do not update a core without testing.** Even a minor-looking upstream change can break a specific game or system.
- **Do not batch multiple core updates into one PR.** If something breaks, you need to be able to isolate which core caused it.
- **Do not delete or replace a working core without a verified replacement ready.** A broken core is worse than an old one.

---

## Release Infrastructure Reference

This section applies to all core updates regardless of type.

### How the update pipeline works

```
oecores.xml (in repo, on main)
  └── lists each core with an appcastURL
        └── Appcasts/<corename>.xml (in repo, on main)
              └── enclosure url → GitHub Release asset (.oecoreplugin.zip)
```

The app fetches `oecores.xml` to discover cores, then fetches each core's appcast to check for updates. The appcast's `sparkle:version` is compared against the installed core's `CFBundleVersion`. If the appcast version is higher, an update is offered.

**Key point:** The appcast goes live the moment the PR merges to `main`. The GitHub Release asset must already exist before the PR merges — you upload the binary first, then update the appcast to point at it.

### Appcast format

Each `Appcasts/<corename>.xml` is a minimal RSS feed. Keep all previous items — do not delete old ones. New items go at the top. Sparkle reads top-to-bottom and uses the first item whose `sparkle:version` is higher than what's installed.

```xml
<item>
  <title>CoreName X.Y</title>
  <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://github.com/nickybmon/OpenEmu-Silicon/releases/download/cores-vX.Y.Z/CoreName.oecoreplugin.zip"
    sparkle:version="X.Y"
    sparkle:shortVersionString="X.Y"
    length="<byte count of zip>"
    type="application/octet-stream" />
</item>
```

The `length` field must be exact — get it with `wc -c < CoreName.oecoreplugin.zip | tr -d ' '`.

### GitHub Release conventions

- Core releases use the tag format `cores-vX.Y.Z`
- They are always created as `--prerelease` — this hides them from the main releases page while keeping the asset URLs accessible to the appcast
- One release can contain multiple core zips if updating several cores at once
- Patch bumps (`cores-v1.0.0` → `cores-v1.0.1`) for single-core hotfixes; minor bumps (`cores-v1.1.0` → `cores-v1.2.0`) for batch updates with new cores or significant changes

### Version numbers

Core `CFBundleVersion` values are simple decimals (e.g. `2.3`, `2.4`). They do not need to match the upstream core's version — they just need to increase monotonically so Sparkle knows there's something newer. When in doubt, increment the minor number.

### Rollback

If a core update causes a regression, rollback is straightforward:
1. Add a new appcast item pointing back at the previous release asset with a higher `sparkle:version`
2. Users will receive it on their next update check and the older binary will be re-installed

You do not need to delete the bad release or change any previously shipped version numbers.
