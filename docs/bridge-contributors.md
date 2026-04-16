# Libretro Bridge — Contributor Guide

_Last updated: 2026-04-16_

This document governs how nickybmon and pystIC divide work on the libretro bridge without creating merge conflicts. Read it before starting any bridge work.

---

## 1. Purpose and Scope

The libretro bridge is the layer that lets OpenEmu-Silicon load standard libretro `.dylib` cores without building each one from source. It lives on the `feat/libretro-bridge` integration branch until all validation phases complete, then merges to `main` in one shot.

Phase 1 (Gambatte — Game Boy) is complete and merged into `feat/libretro-bridge`. Phase 2 (Flycast — Dreamcast) is in PR review. Phase 3 (VICE — Commodore 64) is scaffolded. This doc covers the remaining work to get all three phases production-ready and merged.

---

## 2. Branch Rules

| Rule | Detail |
|------|--------|
| Always branch from `feat/libretro-bridge` | Not `main` — the bridge adds SDK types and the translator; branching from `main` misses them |
| Branch naming | `feat/libretro-bridge-[system]` or `fix/bridge-[description]` |
| PRs always target `feat/libretro-bridge` | Never open a bridge PR directly to `main` |
| `feat/libretro-bridge` → `main` | Single merge by nickybmon when all phases validate |
| Rebase before starting new work | `git fetch origin && git rebase origin/feat/libretro-bridge` — keep your branch current |

---

## 3. File Ownership

| File / Area | Primary owner | Notes |
|-------------|---------------|-------|
| `OpenEmu-SDK/OpenEmuBase/OEGameCore.h/.m` | pystIC leads, nickybmon reviews | Coordinate in a PR comment **before** touching — this file affects all 25 cores |
| `OpenEmu-SDK/OpenEmuBase/OELibretroCoreTranslator.h/.m` | pystIC | Core bridge implementation |
| `OpenEmu-SDK/OpenEmuBase/libretro.h` | pystIC | Libretro API type definitions — update when adding new `RETRO_ENVIRONMENT_*` constants |
| `OpenEmu/SystemPlugins/*/` (system responders) | nickybmon | Per-system button mapping in the main app |
| `[System]-Bridge/` plugin scaffolds | nickybmon | Plugin bundle structure, `Info.plist`, `.gitignore` |
| `Appcasts/` | nickybmon | Release delivery — never edit during active bridge dev |
| `docs/libretro-bridge-plan.md` | nickybmon | Architecture plan |
| `docs/core-update-process.md` | nickybmon | Delivery pipeline |
| `docs/bridge-contributors.md` | nickybmon | This file |

### Conflict avoidance rules

- **pystIC**: SDK-only (`OELibretroCoreTranslator`, `libretro.h`, `OEGameCore`). Never touch `OpenEmu/`, plugin scaffolds, `Appcasts/`, or system plugin directories. If a system responder needs a new protocol method, file an issue and describe what you need — nickybmon will add it.
- **nickybmon**: Integration-only (system responders, plugin scaffolds, appcast). File issues for translator changes rather than editing `OELibretroCoreTranslator.m` directly.
- **Before either person touches `OEGameCore.h/.m`**: coordinate in a PR comment first. This is the highest-conflict-risk file in the repo — it's the base class for all 25 native cores.

---

## 4. Remaining Work Items

Items are ordered by dependency. Do not start an item until all its dependencies are complete.

| # | Item | Owner | Depends on |
|---|------|-------|-----------|
| 1 | Post inline review comments on #182 and #186 | nickybmon | — |
| 2 | pystIC addresses #182 review: audio buffer test on high-load core + rapid-pause runloop test + checklist clarification | pystIC | 1 |
| 3 | pystIC confirms #186 review items: serialize symbols, save state overrides, GB input, coreBundle fallback (all confirmed present) | pystIC | 1 |
| 4 | Merge #182 → `feat/libretro-bridge` | nickybmon | 2 |
| 5 | Merge #186 → `feat/libretro-bridge` (manual conflict resolution against existing translator) | nickybmon | 3, 4 |
| 6 | Fix #185 Flycast env var defaults to match native v1.0.5 fix (threaded_rendering enabled, fast_gd_rom_load enabled, dynarec disabled) | nickybmon | — |
| 7 | Merge #185 → `feat/libretro-bridge` | nickybmon | 5, 6 |
| 8 | Complete `Gambatte-Bridge/` `Info.plist`, PR scaffold → `feat/libretro-bridge` | nickybmon | 5 |
| 9 | Complete `Flycast-Bridge/` `Info.plist` with correct DC env var defaults | nickybmon | 5, 7 |
| 10 | Merge Phase 3 VICE scaffold (`feat/libretro-bridge-phase3-vice`) → `feat/libretro-bridge` | nickybmon | 5 |
| 11 | Wire `OEC64SystemResponderClient` in main app (system plugin) | nickybmon | 10 |
| 12 | Complete `VICE-Bridge/` `Info.plist` + C64 system responder | nickybmon | 11 |
| 13 | Input mapping verification: NES, Genesis, PSX, N64 | pystIC tests, nickybmon verifies | 5 |
| 14 | Keyboard forwarding — bridge side (`OELibretroCoreTranslator`) | pystIC | 10 |
| 15 | Keyboard forwarding — system plugin side (C64 `OEKeyboardResponder`) | nickybmon | 14 |
| 16 | Flycast Phase 2 freeze verification: confirm buildbot dylib behavior matches native v1.0.5 fix (issue #169 equivalent) | Both | 7 |
| 17 | Rewind / cheat code wiring in translator | pystIC | 5 |
| 18 | BIOS audit: DC, PSX, Saturn, NDS path delivery validation through bridge | nickybmon | 5 |
| 19 | VICE dylib curation, appcast entry (`Appcasts/vice-bridge.xml`), GitHub Release | nickybmon | 12 |
| 20 | Gambatte-Bridge dylib curation, appcast entry (`Appcasts/gambatte-bridge.xml`) | nickybmon | 8 |
| 21 | Flycast-Bridge dylib curation, appcast entry (`Appcasts/flycast-bridge.xml`) | nickybmon | 9, 16 |
| 22 | `feat/libretro-bridge` → `main` merge | nickybmon | All phases validated |

---

## 5. Testing Checklist for Any PR → `feat/libretro-bridge`

Every PR must pass all items before merge:

- [ ] Build passes:
  ```bash
  xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build 2>&1 | tail -20
  ```
- [ ] Native Gambatte (non-bridge) launches a GB ROM without regression
- [ ] Gambatte-Bridge launches and save/load state round-trips correctly (boot → play → save → quit → reopen → load)
- [ ] No crash on quit
- [ ] Console silent for errors:
  ```bash
  log show --predicate 'process == "OpenEmu"' --last 2m | grep -i error
  ```

For PRs touching Flycast behavior, also verify:
- [ ] Dreamcast BIOS splash renders (no black screen)
- [ ] Input registers on controller (analog stick + face buttons)
- [ ] No freeze during GD-ROM load (confirm `reicast_fast_gd_rom_load=enabled`)

---

## 6. Core Versioning Policy for Bridge Cores

Bridge cores follow the same philosophy as `docs/core-update-process.md` — curated, tested binaries, not live feeds.

### Default channel: curated stable

- Buildbot dylib reviewed against upstream commits, tested 20–30 minutes, wrapped as `.oecoreplugin`, hosted on GitHub Release, delivered via Sparkle appcast
- Version is pinned in the appcast XML — users only update when we say so
- No direct buildbot links in the app or appcast files — ever

### Appcast file naming

Bridge cores get their own appcast files, separate from their native counterparts:

| Core | Appcast file |
|------|--------------|
| Gambatte (native) | `Appcasts/gambatte.xml` |
| Gambatte-Bridge | `Appcasts/gambatte-bridge.xml` |
| Flycast (native) | `Appcasts/flycast.xml` |
| Flycast-Bridge | `Appcasts/flycast-bridge.xml` |
| VICE-Bridge (no native) | `Appcasts/vice-bridge.xml` |

### Version string convention

Use the upstream libretro core's `library_version` from `retro_get_system_info()` (e.g., `"Gambatte v0.5.0-57de956"`). If the upstream version string is a commit hash only, append the buildbot date: `"gambatte-20260410"`.

### Power user path (manual dylib replacement)

The bridge plugin structure makes it trivial for power users to run a newer buildbot dylib without waiting for a curated release:

```bash
# Replace the dylib inside the installed plugin bundle
PLUGIN=~/Library/Application\ Support/OpenEmu/Cores/Gambatte-Bridge.oecoreplugin
cp ~/Downloads/gambatte_libretro.dylib "$PLUGIN/Contents/MacOS/gambatte_libretro.dylib"
codesign --force --sign - "$PLUGIN"
```

This is documented here as the advanced path. There is no app UI for it — users who want this will find it in the docs.

**What NOT to build:** a UI toggle in the app that switches between stable/nightly. The maintenance burden and QA complexity are not worth it until we have more bridge cores shipping and a stable testing base.

---

## 7. Dolphin/dolphin Source Modification

The `Dolphin/dolphin` directory currently has a modified `Source/Core/VideoCommon/FramebufferManager.cpp` (and possibly other files). This is tracked as a dirty submodule state. **Do not include this change in any bridge PR** — it is unrelated to the libretro bridge.

Before the `feat/libretro-bridge` → `main` merge, evaluate whether the `Dolphin/dolphin` modification is:
- A WIP fix that should become its own PR against `main`
- An accidental modification that should be discarded with `git checkout -- Dolphin/dolphin`

This will be resolved before the final merge.
