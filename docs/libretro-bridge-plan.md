# Libretro Bridge — Architecture Plan

_Last updated: 2026-04-14_

This document captures the full analysis, rationale, and implementation plan for introducing a libretro translation bridge into OpenEmu-Silicon. It exists so that anyone working on this effort (including future sessions) has the complete picture of what was decided and why.

**Origin:** [PR #177](https://github.com/nickybmon/OpenEmu-Silicon/pull/177) by pystIC, which proposed a comprehensive libretro integration including a translation bridge, buildbot delivery pipeline, and core option system. The PR was too large to merge as-is, but the core ideas are sound. This plan describes how to extract, validate, and land the work incrementally.

**Related docs:**
- [Core Update Process](core-update-process.md) — how curated core binaries are sourced, tested, and published
- [Supported Systems & Core Status](cores.md) — current state of every core in the project

---

## Table of Contents

1. [The Problem This Solves](#the-problem-this-solves)
2. [How Cores Work Today](#how-cores-work-today)
3. [What the Bridge Changes](#what-the-bridge-changes)
4. [The Three Interconnected Systems](#the-three-interconnected-systems)
5. [What Changes for Users](#what-changes-for-users)
6. [What Changes for Maintainers](#what-changes-for-maintainers)
7. [What the Bridge Does NOT Do Well (Yet)](#what-the-bridge-does-not-do-well-yet)
8. [Recommendation: Hybrid Approach](#recommendation-hybrid-approach)
9. [Implementation Plan](#implementation-plan)
10. [Decision Log](#decision-log)

---

## The Problem This Solves

OpenEmu-Silicon currently maintains ~25 emulator cores by compiling each one from source as part of the Xcode workspace. Each core has:

- A full copy of the emulator's C/C++ source tree (often 50-300MB)
- An Xcode project that compiles that source for ARM64
- A hand-written Objective-C++ wrapper that bridges the emulator's internal APIs to OpenEmu's `OEGameCore` protocol
- Undocumented ARM64-specific patches mixed into the source

This approach has real costs:

| Cost | Impact |
|------|--------|
| Adding a new system | Weeks to months of porting, wrapper writing, and testing |
| Updating an existing core | Manual diffing against upstream, risk of overwriting ARM64 patches |
| Repo size | Hundreds of megabytes of third-party source code |
| Build time | Every core compiles from source in the workspace |
| Maintainer burden | One person maintaining 25 separate build environments |

Systems like MAME, Commodore 64 (VICE), and others sit at "no core" status because the bring-up cost is too high for a solo maintainer.

---

## How Cores Work Today

Every core is a `.oecoreplugin` bundle installed at `~/Library/Application Support/OpenEmu/Cores/`. Here's what one looks like internally:

```
Gambatte.oecoreplugin/
└── Contents/
    ├── Info.plist
    └── MacOS/
        └── Gambatte        ← Mach-O bundle compiled from source
```

The binary inside (`Gambatte`) is a macOS bundle that contains an Objective-C class (e.g., `GBGameCore`) which subclasses `OEGameCore`. The `Info.plist` tells OpenEmu which class to instantiate:

```xml
<key>OEGameCoreClass</key>
<string>GBGameCore</string>
```

When you launch a Game Boy game, OpenEmu:
1. Reads the plugin's `Info.plist` to find `GBGameCore`
2. Instantiates `GBGameCore` (which is compiled into the bundle)
3. Calls `loadFileAtPath:` with the ROM path
4. Calls `executeFrame` 60 times per second
5. Reads video, audio, and input through `OEGameCore` protocol methods

The wrapper class (`GBGameCore`) is **deeply coupled** to the emulator's internals. For example, `FlycastGameCore.mm` directly `#include`s Flycast's internal headers (`emulator.h`, `hw/maple/maple_cfg.h`, `audio/audiostream.h`) and calls private C++ functions (`emu.init()`, `emu.render()`). It even defines a custom C++ class that inherits from Flycast's internal `AudioBackend`. This wrapper only works for Flycast and would need to be rewritten from scratch for any other core.

---

## What the Bridge Changes

The libretro ecosystem has a standardized C API (`libretro.h`) that all RetroArch-compatible cores implement. Every libretro core exports the same set of functions:

```c
retro_init()              // Initialize the core
retro_load_game()         // Load a ROM
retro_run()               // Execute one frame
retro_serialize()         // Save state to buffer
retro_unserialize()       // Load state from buffer
retro_set_environment()   // Core tells host what it needs
retro_set_video_refresh() // Host provides video callback
retro_set_audio_sample()  // Host provides audio callback
retro_set_input_state()   // Host provides input callback
// ... etc.
```

The libretro buildbot (https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/) compiles these cores daily for ARM64 macOS and publishes them as `.dylib` shared libraries. These dylibs are ~1-4MB each and export only the standard libretro API. They are not macOS bundles, don't contain Objective-C classes, and know nothing about OpenEmu.

**The translation bridge** (`OELibretroCoreTranslator`) is a single Objective-C class that:
- Subclasses `OEGameCore` (so OpenEmu treats it as a normal core)
- Uses `dlopen()` to load a libretro `.dylib` at runtime
- Uses `dlsym()` to find the standard libretro functions
- Registers C callback functions that translate libretro's output into OpenEmu's format
- Maps all `OEGameCore` protocol methods to their libretro equivalents

A bridge-based plugin looks like this on disk:

```
Gambatte.oecoreplugin/
└── Contents/
    ├── Info.plist          ← OEGameCoreClass = "OELibretroCoreTranslator"
    │                          OELibretroCorePath = "gambatte_libretro.dylib"
    └── MacOS/
        └── gambatte_libretro.dylib   ← Pre-built from buildbot (3.8MB)
```

The key difference: the `Info.plist` points to `OELibretroCoreTranslator` (which lives in the SDK, shared by all bridge cores) instead of a core-specific class. The translator reads `OELibretroCorePath` to find the dylib, loads it, and handles all translation.

**From OpenEmu's perspective, nothing changes.** It still loads a `.oecoreplugin`, finds an `OEGameCore` subclass, and calls its methods. It doesn't know or care that the real work is being delegated to a dynamically loaded library through a translation layer.

---

## The Three Interconnected Systems

This effort involves three distinct pieces that need to work together:

### 1. The Translation Bridge

**What it is:** `OELibretroCoreTranslator` — a single ~1,270-line Objective-C class in `OpenEmu-SDK/OpenEmuBase/`.

**What it does:**
- `dlopen()` / `dlsym()` to load and resolve libretro symbols
- Video: receives pixel data via callback, converts pixel formats (0RGB1555, RGB565, XRGB8888) to OpenEmu's BGRA format with NEON-optimized paths
- Audio: receives samples via callback, writes to OpenEmu's ring buffer
- Input: maintains a state table that the libretro core polls each frame
- Hardware rendering: negotiates OpenGL context with OpenEmu's renderer for cores that need GPU access (Flycast, Mupen64Plus)
- Environment callbacks: provides BIOS paths, save directories, core options, pixel format negotiation

**Status in PR #177:** Substantially complete. Handles video, audio, input, hardware rendering, and environment callbacks. Missing save state support (`retro_serialize` / `retro_unserialize` not wired up).

### 2. The Delivery Pipeline

**What it is:** The process by which pre-built dylibs get from the libretro buildbot to users.

**How it works (per [core-update-process.md](core-update-process.md)):**
1. Maintainer reviews upstream commits for a core to assess stability
2. Downloads the ARM64 macOS `.dylib` from the buildbot
3. Tests it locally through the bridge
4. Wraps it as a `.oecoreplugin` and uploads to a GitHub Release
5. Updates the Sparkle appcast so users receive the update

**Why curated re-hosting instead of direct buildbot access:**
- The buildbot only has a `/latest/` endpoint — no stable channel, no version history
- If a bad build ships, it can't be rolled back (the previous binary is gone)
- The maintainer can't verify what users received after the fact
- For a project with one person doing QA, this is too much exposure

**Status:** The process is documented. The existing Sparkle infrastructure supports it. No new code is needed for the delivery pipeline itself — it uses GitHub Releases and appcast XML files that already exist.

### 3. The Coexistence Strategy

**What it is:** How bridge-based cores and native-source cores live together in the same app.

**The decision:** Use a **hybrid approach** (see [Recommendation](#recommendation-hybrid-approach) below). Native cores are not replaced unless the bridge version is proven equal or better. Bridge cores are used primarily for new systems and for cases where the native maintenance burden is unsustainable.

**How it works technically:** OpenEmu doesn't care whether a plugin's `OEGameCoreClass` is `GBGameCore` or `OELibretroCoreTranslator`. Both subclass `OEGameCore`. Both produce video, audio, and accept input through the same protocol. The app treats them identically. There is no conflict — the two types can coexist indefinitely.

---

## What Changes for Users

**Nothing visible.** The bridge is an internal implementation detail. Users will see:

- The same library UI
- The same controller configuration in system preferences
- The same save state / screenshot management
- The same "Open With: [Core Name]" menu
- The same Sparkle update notifications

Input mapping continues to work through OpenEmu's system responder protocols. The user configures "A button = X on my controller" in preferences. The system responder translates that to the system-specific button ID. The bridge then maps that to the corresponding libretro button ID. This adds one translation step, but it's invisible to the user.

**This is fundamentally different from EmulationStation or RetroArch.** Those are launchers that open separate emulator apps. OpenEmu embeds the core inside its own process and controls the entire UI. The bridge doesn't change that — it's still an embedded core, just loaded differently.

---

## What Changes for Maintainers

| Task | Native model | Bridge model |
|------|-------------|--------------|
| Add a new system | Port source, write Xcode project, write custom wrapper (weeks) | Download dylib, write Info.plist, test (hours) |
| Update a core | Diff upstream, merge ARM64 patches, rebuild (hours, error-prone) | Download new dylib, test, replace (minutes) |
| Fix a core-specific bug | Edit the core's source or wrapper | Wait for upstream fix, or fall back to native build |
| Repo size per core | 50-300MB of source | 1-4MB dylib |
| Build time | Compile from source | No compilation (dylib is pre-built) |
| Debug a crash in a core | Full source available, can step through in Xcode | Binary only — limited to libretro API-level debugging |

The trade-off is clear: the bridge dramatically lowers the barrier to adding and updating cores, but you lose the ability to patch core internals directly. For most cores this is fine (you rarely need to patch mGBA or Nestopia). For complex cores with known issues (PPSSPP, Flycast), having the source available is valuable.

---

## What the Bridge Does NOT Do Well (Yet)

These are known gaps that need to be addressed before the bridge is production-ready:

### Save states (critical)

PR #177's bridge does not resolve `retro_serialize`, `retro_unserialize`, or `retro_serialize_size`. Save states are a daily-use feature for NES, SNES, GBA, and others. This is a hard blocker for any core where users expect save states.

**Fix:** Add the three symbols to the `RESOLVE()` block and implement the `OEGameCore` save state methods by calling through to them. Most mature libretro cores support serialization.

### Rewind and cheat codes

`retro_cheat_reset` and `retro_cheat_set` are exported by most cores but not wired up in the bridge. Rewind depends on save state serialization working first.

### Input mapping edge cases

The system responder modifications in PR #177 need careful review. Each system's button enum must be correctly mapped to libretro's generic button IDs. An incorrect mapping would cause "A button does B's action" for a specific system — subtle, hard to catch without testing every system.

### Debugging limitations

With native cores, a crash in the emulator can be debugged with full source and Xcode's debugger. With bridge cores, a crash inside the dylib produces a stack trace with no source context. For stable cores this rarely matters. For actively developed or problematic cores, it's a real limitation.

---

## Recommendation: Hybrid Approach

Do not replace all native cores with bridge cores. Use each approach where it's strongest:

### Use the bridge for:
- **New systems that don't exist yet** — MAME/Arcade, Commodore 64 (VICE), and other cores at "no core" status. The bridge makes these feasible for a solo maintainer.
- **Cores where source-level maintenance is unsustainable** — if updating a core from source is too painful, switching to the bridge dylib is a pragmatic choice.
- **Getting a working version shipped quickly** — the bridge can have a core running in hours. Optimize later.

### Keep native wrappers for:
- **Cores that already work well** — mGBA, Nestopia, Genesis Plus GX, Gambatte, and others that are stable and rarely need updating. If it isn't broken, don't fix it.
- **Cores with significant ARM64 patch investment** — the custom patches in Flycast, Mupen64Plus, etc. represent real work that the buildbot binaries may not include.
- **Cases where deep integration matters** — custom audio backends, hardware rendering quirks, platform-specific optimizations that go beyond the libretro API.

### The transition path:
1. Validate the bridge with simple cores (Phase 1 below)
2. Use it to add new systems that don't currently exist
3. Over time, evaluate whether stable native cores would benefit from switching to bridge (lower maintenance, easier updates) on a case-by-case basis
4. Never force a migration — a native core is only replaced when the bridge version is proven equal or better

---

## Implementation Plan

### Phase 1 — Proof of Concept with Gambatte (Game Boy)

**Goal:** Validate that the bridge works end-to-end for a simple, stable core.

**Why Gambatte:**
- Software-rendered (no OpenGL complexity)
- One of the most mature and stable libretro cores
- The buildbot dylib exports `retro_serialize` / `retro_unserialize` (save states testable)
- Game Boy games are simple to test (boot, play, save, load)
- A working native Gambatte already exists for direct comparison

**Steps:**
1. Extract `OELibretroCoreTranslator.h`, `OELibretroCoreTranslator.m`, `OELibretroInputReceiver.h`, and `libretro.h` from PR #177 into `OpenEmu-SDK/OpenEmuBase/`
2. Add save state support — wire up `retro_serialize_size`, `retro_serialize`, `retro_unserialize`
3. Add the translator files to the SDK's Xcode project
4. Download `gambatte_libretro.dylib` from the buildbot
5. Build a test `Gambatte-Bridge.oecoreplugin` with an Info.plist pointing to the translator class and the dylib
6. Install alongside the existing native Gambatte (using a different bundle ID like `org.openemu.Gambatte-Bridge`)
7. Test: ROM boot, video output, audio output, input response, save states, load states
8. Compare output quality and behavior against the native Gambatte

**Success criteria:**
- Game boots and renders correctly
- Audio plays without glitches
- Controller input works through OpenEmu's preferences (not hardcoded)
- Save state round-trips work (save → quit → reopen → load)
- No crashes or hangs during 30 minutes of play

**If it fails:** Document what broke and why. The native Gambatte is unaffected. Determine whether the issue is fixable in the bridge or fundamental.

### Phase 2 — Validate Hardware Rendering with Flycast (Dreamcast)

**Goal:** Prove the bridge handles the hardest case — a core that needs GPU access, BIOS files, and complex input (analog sticks, triggers).

**Why Flycast:**
- Requires hardware rendering (OpenGL context negotiation through the bridge)
- Requires BIOS files (dc_boot.bin, dc_flash.bin) — tests the environment callback path
- Has analog input (joysticks, triggers) — tests more than just digital buttons
- It's a core you've been actively working on, so you know its behavior well
- If Flycast works through the bridge, everything simpler is implicitly validated

**Steps:**
1. Download `flycast_libretro.dylib` from the buildbot
2. Build a test `Flycast-Bridge.oecoreplugin`
3. Test: Dreamcast game boot with BIOS, video rendering (3D games), audio, analog input, save states
4. Compare against the native Flycast build

**Success criteria:**
- 3D games render correctly (Sonic Adventure, Jet Set Radio)
- Audio is correct (no crackling, correct speed)
- Analog sticks and triggers work through OpenEmu's Dreamcast input preferences
- Save states work
- No OpenGL crashes or context errors

**If it fails:** This is expected to be harder than Gambatte. Document the specific failure (context negotiation? BIOS path? input mapping?) and determine if it's a bridge issue or a buildbot binary issue.

### Phase 3 — Add a New System via Bridge

**Goal:** Use the validated bridge to add a system that doesn't currently exist in the app.

**Candidates (in order of likely feasibility):**
1. **Commodore 64 via VICE** — the system plugin already exists in the app, there's just no core. A bridge-loaded VICE dylib could fill this gap quickly.
2. **MAME/Arcade** — system plugin exists, spike tracked in [#136](https://github.com/nickybmon/OpenEmu-Silicon/issues/136). MAME is a complex core but the bridge would avoid the enormous build system challenge.

**Steps:**
1. Download the relevant dylib from the buildbot
2. Create a new `.oecoreplugin` with Info.plist pointing to the translator
3. Ensure the existing system plugin's responder protocol has correct libretro button mappings
4. Test with known-good ROMs
5. If successful, curate the dylib (per [core-update-process.md](core-update-process.md)) and ship it

**This is where the bridge pays for itself.** A new system in hours instead of weeks.

### Phase 4 — Evaluate Native-to-Bridge Migration

**Goal:** For each existing native core, determine whether switching to a bridge-based dylib is worthwhile.

**Criteria for migration:**
- The bridge version must match or exceed the native version in all user-facing features (rendering, audio, input, save states)
- The core must be stable enough in its libretro build that frequent updates aren't needed
- The maintenance burden of the native version must be high enough to justify the switch

**Cores most likely to benefit from migration:**
- Cores with large source trees that rarely change (Stella, ProSystem, O2EM, Potator)
- Cores where the native build has known issues that upstream has fixed but are too complex to merge

**Cores that should stay native indefinitely (unless circumstances change):**
- Cores with significant custom ARM64 patches (Flycast, Mupen64Plus)
- Cores where the native build is working perfectly and the source is small

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-14 | Adopt hybrid approach (bridge for new cores, native for existing) | Maximizes benefit (new systems feasible) while minimizing risk (working cores untouched) |
| 2026-04-14 | Start proof of concept with Gambatte, not Flycast | Simplest possible test case — software rendering, mature libretro core, easy to compare against native |
| 2026-04-14 | Curated re-hosting instead of direct buildbot access | Buildbot has no stable channel, no version history, no rollback. Curation layer provides QA gate. |
| 2026-04-14 | Save state support is a hard requirement before any bridge core ships | Save states are a daily feature for most systems. A bridge core without them is a regression. |
| 2026-04-14 | Do not delete native core source until bridge replacement is proven equal or better | Native cores are the fallback. Source stays in the repo until it's definitively not needed. |

---

## Appendix: Key Files

| File | Location | Purpose |
|------|----------|---------|
| `OELibretroCoreTranslator.h` | `OpenEmu-SDK/OpenEmuBase/` (from PR #177) | Bridge class header |
| `OELibretroCoreTranslator.m` | `OpenEmu-SDK/OpenEmuBase/` (from PR #177) | Bridge implementation (~1,270 lines) |
| `OELibretroInputReceiver.h` | `OpenEmu-SDK/OpenEmuBase/` (from PR #177) | Input protocol for bridge cores |
| `libretro.h` | `OpenEmu-SDK/OpenEmuBase/` (from PR #177) | Libretro API type definitions |
| `OEGameCore.h/.m` | `OpenEmu-SDK/OpenEmuBase/` | Base class that both native and bridge cores subclass |
| `CoreUpdater.swift` | `OpenEmu/` | Handles core downloads and updates via Sparkle |
| System responder files | `OpenEmu/SystemPlugins/*/` | Per-system input mapping — need libretro button ID mappings added |

## Appendix: Buildbot Reference

The libretro buildbot for macOS ARM64 is at:
```
https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/
```

Core dylibs are named `{corename}_libretro.dylib.zip`. Key ones for this project:

| Core | Filename | Systems |
|------|----------|---------|
| Gambatte | `gambatte_libretro.dylib.zip` | Game Boy, Game Boy Color |
| mGBA | `mgba_libretro.dylib.zip` | GBA, GB, GBC |
| Nestopia | `nestopia_libretro.dylib.zip` | NES, Famicom Disk System |
| Flycast | `flycast_libretro.dylib.zip` | Dreamcast |
| Genesis Plus GX | `genesis_plus_gx_libretro.dylib.zip` | Genesis, Master System, Game Gear, SG-1000, Sega CD |
| Snes9x | `snes9x_libretro.dylib.zip` | SNES |
| Mupen64Plus-Next | `mupen64plus_next_libretro.dylib.zip` | N64 |
| Mednafen (multi) | `mednafen_{system}_libretro.dylib.zip` | PSX, Saturn, PCE, Lynx, VB, WSWAN, NGP, PCFX |
| MAME 2003+ | `mame2003_plus_libretro.dylib.zip` | Arcade |
| VICE x64 | `vice_x64_libretro.dylib.zip` | Commodore 64 |
