# Core Status — OpenEmuARM64

_Last audited: 2026-03-22_

This document tracks the status of every emulator core in the repo — whether it's installed, which systems it covers, and what's missing or broken.

---

## Installed & Working

These cores are present in `~/Library/Application Support/OpenEmu/Cores/` and cover the listed systems.

| Core | Systems Covered | Notes |
|------|----------------|-------|
| 4DO | 3DO | |
| Atari800 | Atari 5200, Atari 8-bit | |
| Bliss | Intellivision | |
| blueMSX | MSX, ColecoVision | |
| CrabEmu | ColecoVision, Game Gear, SG-1000, SMS | |
| FCEU | NES | Alternate NES core (alongside Nestopia) |
| Gambatte | Game Boy | **GBC not declared** — see Known Issues |
| GenesisPlus | Game Gear, SG-1000, SMS, SG, Sega CD | **Genesis/MD missing** — see Known Issues |
| JollyCV | ColecoVision | |
| Mednafen | Atari Lynx, Neo Geo Pocket, PC Engine/CD, PC-FX, PSX, Saturn, Virtual Boy, WonderSwan | |
| mGBA | Game Boy Advance | **GBC not declared** — see Known Issues |
| Nestopia | NES, Famicom Disk System | |
| O2EM | Odyssey² / Videopac | |
| Picodrive | Sega 32X | |
| ProSystem | Atari 7800 | |
| SNES9x | SNES | |
| Stella | Atari 2600 | |
| VecXGL | Vectrex | |
| VirtualJaguar | Atari Jaguar | |

---

## Built But Not Installed

These cores compiled successfully (present in a core's `build/Debug/` folder) but have **not** been copied to the Cores support folder. They will not appear in the app.

| Core | System | Action Needed |
|------|--------|---------------|
| BSNES | SNES (accuracy) | Copy/sign to `~/Library/Application Support/OpenEmu/Cores/` |
| Reicast | Dreamcast | Copy/sign to `~/Library/Application Support/OpenEmu/Cores/` |

To install manually:
```bash
cp -R "/path/to/repo/BSNES/build/Debug/BSNES.oecoreplugin" \
  ~/Library/Application\ Support/OpenEmu/Cores/
codesign --force --sign - ~/Library/Application\ Support/OpenEmu/Cores/BSNES.oecoreplugin
```

---

## Source Present, Not Built

These core directories exist in the repo and have Xcode project files, but have never been built or installed.

| Core | System | Status |
|------|--------|--------|
| Mupen64Plus | Nintendo 64 | `Mupen64Plus.xcodeproj` present. Not built. Needs ARM64 build investigation. |
| PokeMini | Pokémon Mini | `PokeMini.xcodeproj` present. Not built. |
| Potator-Core | Watara Supervision | `Potator.xcodeproj` present. Not built. |

---

## Incomplete / Empty Directories

These directories exist but contain no Xcode project or build artifacts — they appear to be placeholders from the original port that were never completed.

| Core | System | Status |
|------|--------|--------|
| DeSmuME | Nintendo DS | Source files only (no xcodeproj). Core appears to have been abandoned mid-port. |
| VirtualC64-Core | Commodore 64 | **Empty directory.** No source, no xcodeproj. |
| Frodo-Core | Commodore 64 | **Empty directory.** No source, no xcodeproj. |

---

## Systems With No Core (Not in This Fork)

These systems were never supported by OpenEmu / this fork and would require integrating a new core from scratch.

| System | Core Candidate | Notes |
|--------|---------------|-------|
| Nintendo GameCube | Dolphin | Dolphin is complex to embed; no precedent in OpenEmu ecosystem |
| Nintendo DS (working) | melonDS | DeSmuME port is dead; melonDS would be the modern alternative |
| Sony PSP | PPSSPP | Never in OpenEmu; significant integration work required |
| Nintendo 64 (working) | Mupen64Plus or ParaLLEl | Mupen64Plus is in the repo (see above) but unbuilt |
| Game Boy Color (working) | mGBA or Gambatte | See Known Issues — may just be a plist identifier problem |

---

## Known Issues

### Genesis/Mega Drive missing from GenesisPlus
The installed `GenesisPlus.oecoreplugin` declares these systems in `OESystemIdentifiers`:
`sg1000`, `gg`, `sms`, `sg`, `scd`

The `genesis` / `md` system identifier is **absent**. This means Sega Genesis/Mega Drive ROMs may not be recognized. The source `Info.plist` in the repo has the same omission — this looks like it was dropped during the ARM64 port.

**Impact:** Genesis/MD ROMs likely fail to launch or are unrecognized.
**Fix needed:** Add `openemu.system.genesis` (or the correct identifier) back to `GenesisPlus/Info.plist` and rebuild.

### Game Boy Color not declared
Neither `Gambatte` nor `mGBA` declares `openemu.system.gbc` in their `OESystemIdentifiers`. Gambatte only lists `gb`; mGBA only lists `gba`.

GBC games may work at runtime if the cores handle them transparently, but they won't appear in a "Game Boy Color" system category in the library.

**Fix needed:** Verify if the app has a GBC system plugin; if so, add `openemu.system.gbc` to Gambatte's or mGBA's `Info.plist`.

### oecores.xml is empty
`oecores.xml` at the repo root (the core download manifest) contains only a comment placeholder. Users cannot install cores via the in-app "Preferences → Cores" download UI — there are no entries to download.

**Status:** PR #11 was opened upstream to restore this file. Until merged, cores must be installed manually from local builds.

---

## Summary by System (Quick Reference)

| System | Status |
|--------|--------|
| Atari 2600 | ✅ Stella |
| Atari 5200 | ✅ Atari800 |
| Atari 7800 | ✅ ProSystem |
| Atari 8-bit | ✅ Atari800 |
| Atari Jaguar | ✅ VirtualJaguar |
| Atari Lynx | ✅ Mednafen |
| ColecoVision | ✅ JollyCV / blueMSX / CrabEmu |
| Commodore 64 | ❌ No working core |
| Dreamcast | ⚠️ Reicast built, not installed |
| Famicom Disk System | ✅ Nestopia |
| Game Boy | ✅ Gambatte |
| Game Boy Advance | ✅ mGBA |
| Game Boy Color | ⚠️ Likely works via Gambatte/mGBA, not declared in plist |
| GameCube | ❌ No core exists in this fork |
| Intellivision | ✅ Bliss |
| MSX | ✅ blueMSX |
| Neo Geo Pocket | ✅ Mednafen |
| NES | ✅ Nestopia / FCEU |
| Nintendo 64 | ⚠️ Mupen64Plus in repo, not built |
| Nintendo DS | ❌ DeSmuME source only, no build |
| Odyssey² | ✅ O2EM |
| PC Engine / TurboGrafx-16 | ✅ Mednafen |
| PC-FX | ✅ Mednafen |
| PlayStation | ✅ Mednafen |
| Pokémon Mini | ⚠️ PokeMini in repo, not built |
| Saturn | ✅ Mednafen |
| Sega 32X | ✅ Picodrive |
| Sega CD / Mega CD | ✅ GenesisPlus |
| Sega Game Gear | ✅ GenesisPlus / CrabEmu |
| Sega Genesis / Mega Drive | ❌ GenesisPlus plist missing `genesis` system ID |
| Sega Master System | ✅ GenesisPlus / CrabEmu |
| SG-1000 | ✅ GenesisPlus / CrabEmu |
| SNES | ✅ SNES9x |
| SNES (accuracy) | ⚠️ BSNES built, not installed |
| Sony PSP | ❌ No core exists in this fork |
| Vectrex | ✅ VecXGL |
| Virtual Boy | ✅ Mednafen |
| Watara Supervision | ⚠️ Potator-Core in repo, not built |
| WonderSwan | ✅ Mednafen |
