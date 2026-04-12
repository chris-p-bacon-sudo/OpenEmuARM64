# Supported Systems & Core Status — OpenEmu-Silicon

_Last updated: 2026-04-12_

This page is the single source of truth for what works, what's broken, and what's coming.

---

## Status key

| Symbol | Meaning |
|--------|---------|
| ✅ Working | Builds, installs, and plays games |
| ⚠️ Partial | Builds and installs but has known issues |
| 🔧 In progress | Active development — not ready for general use |
| ❌ No core | System plugin exists in the UI; no emulator core yet |

---

## Working systems

| System | Core | Notes |
|--------|------|-------|
| Atari 2600 | [Stella](https://github.com/stella-emu/stella) 3.9.3 | ✅ |
| Atari 5200 | [Atari800](https://github.com/atari800/atari800) 3.1.0 | ✅ |
| Atari 7800 | [ProSystem](https://gitlab.com/jgemu/prosystem) 1.5.2 | ✅ |
| Atari 8-bit | [Atari800](https://github.com/atari800/atari800) 3.1.0 | ✅ |
| Atari Jaguar | [VirtualJaguar](https://github.com/OpenEmu/VirtualJaguar-Core) | ✅ |
| Atari Lynx | [Mednafen](https://mednafen.github.io) | ✅ |
| ColecoVision | [JollyCV](https://github.com/OpenEmu/JollyCV-Core) 1.0.1 / [blueMSX](https://github.com/OpenEmu/blueMSX-Core) 2.8.3 | ✅ |
| Famicom Disk System | [Nestopia](https://gitlab.com/jgemu/nestopia) | ✅ |
| Game Boy | [Gambatte](https://gitlab.com/jgemu/gambatte) 0.5.1 | ✅ |
| Game Boy Advance | [mGBA](https://github.com/mgba-emu/mgba) 0.10.5 | ✅ |
| Game Boy Color | [Gambatte](https://gitlab.com/jgemu/gambatte) / [mGBA](https://github.com/mgba-emu/mgba) | ⚠️ Games run but GBC is not declared as a separate system in the core plists — no dedicated GBC library category |
| Game Gear | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) / [CrabEmu](https://github.com/OpenEmu/CrabEmu-Core) | ✅ |
| Intellivision | [Bliss](https://github.com/jeremiah-sypult/BlissEmu) | ✅ |
| MSX | [blueMSX](https://github.com/OpenEmu/blueMSX-Core) 2.8.3 | ✅ |
| Neo Geo Pocket | [Mednafen](https://mednafen.github.io) | ✅ |
| Nintendo (NES) | [Nestopia](https://gitlab.com/jgemu/nestopia) / [FCEU](https://github.com/TASEmulators/fceux) | ✅ |
| Nintendo 64 | [Mupen64Plus](https://github.com/mupen64plus) 2.5.9 | ✅ Revived 2026-03 |
| Nintendo DS | [DeSmuME](https://desmume.org) | ✅ |
| Odyssey² / Videopac+ | [O2EM](https://sourceforge.net/projects/o2em/) 1.16 | ✅ |
| PC Engine / TurboGrafx-16 | [Mednafen](https://mednafen.github.io) | ✅ |
| PC Engine CD | [Mednafen](https://mednafen.github.io) | ✅ Requires BIOS |
| PC-FX | [Mednafen](https://mednafen.github.io) | ✅ Requires BIOS |
| PlayStation | [Mednafen](https://mednafen.github.io) | ✅ Requires BIOS |
| Pokémon Mini | [PokeMini](https://github.com/pokerazor/pokemini) 0.6.0 | ✅ |
| Sega 32X | [picodrive](https://github.com/notaz/picodrive) 1.93 | ✅ |
| Sega CD / Mega CD | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) / [picodrive](https://github.com/notaz/picodrive) | ✅ Requires BIOS |
| Sega Dreamcast | [Flycast](https://github.com/flyinghead/flycast) v2024.09.30 | ✅ Requires BIOS: dc_boot.bin, dc_flash.bin |
| Sega Genesis / Mega Drive | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | ✅ |
| Sega Master System | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) / [CrabEmu](https://github.com/OpenEmu/CrabEmu-Core) | ✅ |
| Sega Saturn | [Mednafen](https://mednafen.github.io) | ⚠️ Core builds and runs but Saturn is not registered in oecores.xml — won't appear in Settings → Cores. Requires BIOS. ([#TODO](https://github.com/nickybmon/OpenEmu-Silicon/issues)) |
| SG-1000 | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | ✅ |
| SNES | [Snes9x](https://github.com/snes9xgit/snes9x) 1.63 | ✅ |
| SNES (accuracy) | [BSNES](https://github.com/bsnes-emu/bsnes) v115 | ⚠️ Builds but not installed by default; experimental |
| Sony PSP | [PPSSPP](https://github.com/hrydgard/ppsspp) | ⚠️ Black screen on launch; error dialog appears. Core needs significant rework. ([#131](https://github.com/nickybmon/OpenEmu-Silicon/issues/131)) |
| Vectrex | [VecXGL](https://github.com/james7780/VecXGL) | ✅ |
| Virtual Boy | [Mednafen](https://mednafen.github.io) | ✅ |
| Watara Supervision | [Potator](https://github.com/alekmaul/potator) | ✅ |
| WonderSwan | [Mednafen](https://mednafen.github.io) | ✅ |
| 3DO | [4DO](https://github.com/fourdo/fourdo) | ✅ Requires BIOS |

---

## In progress

| System | Core | Status |
|--------|------|--------|
| GameCube | [Dolphin](https://dolphin-emu.org) | 🔧 Builds in workspace; audio, input, and save states still being worked on. Not in oecores.xml yet. ([#142](https://github.com/nickybmon/OpenEmu-Silicon/issues/142)) |
| Wii | [Dolphin](https://dolphin-emu.org) | 🔧 Same Dolphin core as GameCube — same status. ([#142](https://github.com/nickybmon/OpenEmu-Silicon/issues/142)) |
| Nintendo DS (melonDS) | [melonDS](https://melonds.kuribo64.net) | 🔧 DeSmuME is the current stopgap. melonDS is the long-term replacement — greenfield wrapper build required. ([#133](https://github.com/nickybmon/OpenEmu-Silicon/issues/133)) |
| Sony PSP | [PPSSPP](https://github.com/hrydgard/ppsspp) | 🔧 Core is integrated but broken — black screen on launch. Needs Metal renderer and core update. ([#131](https://github.com/nickybmon/OpenEmu-Silicon/issues/131), [#137](https://github.com/nickybmon/OpenEmu-Silicon/issues/137)) |

---

## No core (system plugin only)

These systems appear in the app UI because a system plugin (controller mappings, file type associations) exists, but there is no emulation core. Games cannot be played.

| System | Situation |
|--------|-----------|
| Arcade / MAME | System plugin fully configured. No MAME emulation core exists in the project. Spike to evaluate ARM64 build feasibility is tracked in [#136](https://github.com/nickybmon/OpenEmu-Silicon/issues/136). |
| Commodore 64 | System plugin exists. No VICE core — the two candidate directories (`VirtualC64-Core`, `Frodo-Core`) are empty. Full core integration required. |
| PlayStation 2 | System plugin exists. No PS2 emulator (PCSX2) has ever had a working OpenEmu wrapper. Very high complexity — not planned. |
| Sega VMU | System plugin exists. The VMU is a Dreamcast memory card peripheral, not a standalone console — no emulator is expected here. |

---

## Out of scope

Not planned for this fork:

| System | Reason |
|--------|--------|
| Nintendo 3DS | Citra/Lime3DS exist but have never had an OpenEmu wrapper. Significant bring-up cost. |
| PlayStation Vita | No suitable emulator with a clean embedding API. |
| Nintendo Switch | Yuzu/Ryujinx are not suitable for plugin embedding. |

---

## Developer reference

### ARM64 patch notes

The following cores had significant ARM64-specific patches applied that are not in upstream. Be careful not to overwrite these when updating:

| Core | Known ARM64 / macOS patches |
|------|---------------------------|
| BSNES | Populated from v115 source; ARM64 build fixes in Xcode project |
| Flycast | `std::result_of` → `std::invoke_result_t`, static libzip headers, TARGET_MAC support in gl_context.h, removed TARGET_IPHONE=1, macOS OpenGL 3 headers, added zip_err_str.c and network_stubs.cpp |
| Mupen64Plus | arm64 added to VALID_ARCHS in both build configurations |
| VirtualJaguar | Framebuffer hint propagated to `JaguarSetScreenBuffer` |
| DeSmuME | Pointer dereference fix in directory.cpp |
| blueMSX / Reicast | ARM64 build error fixes |

For all other cores, ARM64 patches may exist but were not separately documented — treat the entire flattened source as potentially containing undocumented modifications relative to upstream.

### Version confidence key

| Symbol | Meaning |
|--------|---------|
| ✅ Confirmed | Version string found directly in source header or ChangeLog |
| ⚠️ Estimated | Inferred from commit message, file naming, or ChangeLog top entry |
| ❓ Unknown | No version marker found; upstream comparison required |

### How to update a core

1. Find the upstream commit or tag that contains the fix
2. Diff against the version recorded here to understand the scope of changes
3. Apply the relevant changes to the flattened source (do not blindly copy the entire tree — ARM64 patches are mixed in)
4. Update this file with the new version and date
5. Commit with message: `chore: update <CoreName> to <version>`
6. Build and test before opening a PR

For new cores going forward (melonDS, Dolphin), use git submodules or subtrees so this manual tracking is not necessary.
