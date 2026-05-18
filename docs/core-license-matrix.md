# Core License Matrix

This matrix tracks bundled emulator cores and major distribution constraints for OpenEmu-Silicon. It supports the RetroAchievements submission-readiness work in #438.

Status meanings:

- **Confirmed** — license file or explicit license text was found in this repository.
- **Needs confirmation** — upstream/project URL exists, but a clear top-level license file was not found in this checkout during this pass.
- **Not shipped as native plugin** — code may exist in-tree, but no current native `.oecoreplugin` Info.plist was found in the expected location during this pass.

This document is evidence, not legal advice.

---

## Distribution-level notes

- OpenEmu-Silicon itself is BSD 2-Clause. See [`LICENSE`](../LICENSE).
- Several emulator cores are GPL/LGPL/MPL/non-commercial licensed. Binary distribution must preserve each core's license obligations.
- **Picodrive is non-commercial.** `picodrive/COPYING` states redistributions may not be sold or used in a commercial product or activity.
- OpenEmu-Silicon currently has no in-app purchases, subscriptions, ads, or paid unlocks documented in [`retroachievements-submission-evidence.md`](retroachievements-submission-evidence.md).

---

## Native plugin/core matrix

| Core/plugin | System(s) | Upstream/project URL | License evidence in repo | Status | Distribution notes |
| --- | --- | --- | --- | --- | --- |
| 4DO | 3DO | `http://www.fourdo.com/` | `4DO/libcue-1.4.0/COPYING` for bundled libcue; no single top-level 4DO license found in this pass | Needs confirmation | Confirm 4DO core license before release/package evidence is considered complete. |
| Bliss | Intellivision | `https://github.com/jeremiah-sypult/BlissEmu` | `Bliss/Bliss/LICENSE.txt` | Confirmed | License file present. |
| BSNES | SNES | `https://byuu.org/bsnes` | `BSNES/bsnes/LICENSE.txt` | Confirmed | bsnes text states GPLv3-only; bundled helper libraries include permissive terms. |
| CrabEmu | ColecoVision | `http://crabemu.sourceforge.net/` | `CrabEmu/sound/nes_apu/COPYING` only found in this pass | Needs confirmation | Confirm main CrabEmu license. |
| Dolphin | GameCube, Wii | `https://dolphin-emu.org/` | `Dolphin/dolphin/COPYING`, `Dolphin/dolphin/Externals/licenses.md` | Confirmed | GPL-family obligations apply; externals have separate licenses. |
| FCEU | NES / Famicom | `https://github.com/TASEmulators/fceux` | GPLv2-or-later notices found in source headers such as `FCEU/src/ines.h`, `FCEU/src/unif.h`, and `FCEU/src/sound.h` | Confirmed | GPL source/binary obligations apply; add a top-level copied license file if packaging lacks one. |
| Flycast | Dreamcast | `https://github.com/flyinghead/flycast` | `Flycast/flycast/LICENSE` plus dependency licenses under `Flycast/flycast/core/deps/` | Confirmed | Review dependency licenses for binary distribution. |
| Gambatte | Game Boy / Game Boy Color | `https://gitlab.com/jgemu/gambatte` | `Gambatte/COPYING` | Confirmed | GPLv2 text present. |
| Genesis Plus GX | Genesis, Master System, Game Gear, SG-1000, Sega CD | `https://github.com/ekeeke/Genesis-Plus-GX` | Non-commercial redistribution terms found in source headers such as `GenesisPlus/genplusgx_source/loadrom.c`, `membnk.c`, and `vdp_render.h`; dependency licenses under `GenesisPlus/genplusgx_source/` | Confirmed | **Non-commercial. Do not sell or use in commercial product/activity.** Complete source redistribution required for modified binaries. |
| JollyCV | ColecoVision | `https://gitlab.com/jgemu/jollycv` | `JollyCV/LICENSE`, `JollyCV/src/z80/LICENSE` | Confirmed | License files present. |
| Mednafen | PSX, PC Engine, PCE-CD, PC-FX, Saturn, Virtual Boy, Lynx, Neo Geo Pocket, WonderSwan | `http://mednafen.sourceforge.net/` | GPL notices found in source headers under `Mednafen/mednafen/`; dependency/license files include `lynx/license.txt`, `sms/docs/license`, `snes/src/data/license.html`, `mpcdec/COPYING`, `tremor/COPYING` | Confirmed | GPL-family obligations apply; keep per-module/dependency license evidence in release source package. |
| mGBA | Game Boy Advance, Game Boy, Game Boy Color | `https://mgba.io/` | `mGBA/LICENSE` | Confirmed | MPL 2.0 text present. |
| Mupen64Plus | Nintendo 64 | `https://github.com/mupen64plus` | `Mupen64Plus/mupen64plus-core/LICENSES`, `Mupen64Plus/mupen64plus-core/doc/gpl-license`, `Mupen64Plus/mupen64plus-core/doc/lgpl-license`, plugin/dependency license files | Confirmed | Mixed GPL/LGPL/component obligations; keep component license files with source distribution. |
| Nestopia | NES, FDS | `https://gitlab.com/jgemu/nestopia` | No top-level license file found in `Nestopia/` during this pass | Needs confirmation | Confirm Nestopia license from upstream. |
| O2EM | Odyssey² / Videopac+ | `http://sourceforge.net/projects/o2em/` | `O2EM/clean/src/COPYING` | Confirmed | License file present. |
| Picodrive | 32X, Sega CD | `https://github.com/notaz/picodrive` | `picodrive/COPYING` | Confirmed | **Non-commercial. Do not sell or use in commercial product/activity.** |
| Potator | Supervision | `http://potator.sourceforge.net` | No clear top-level license file found in `Potator-Core/` during this pass | Needs confirmation | Confirm license before claiming matrix complete. |
| PPSSPP | PSP | `http://www.ppsspp.org/` | `PPSSPP/PPSSPP-Core/ppsspp/LICENSE.TXT` plus external licenses | Confirmed | GPL-family project; review external licenses for binary packaging. |
| ProSystem | Atari 7800 | `https://gitlab.com/jgemu/prosystem` | `ProSystem/LICENSE` | Confirmed | License file present. |
| SNES9x | SNES | `https://github.com/snes9xgit/snes9x` | `SNES9x/src/LICENSE` | Confirmed | Contains non-commercial language: “Under no circumstances will commercial rights be given.” |
| Stella | Atari 2600 | `http://sourceforge.net/projects/stella/` | BSD-style notices found in OpenEmu wrapper/stub files; LGPL notices found for NTSC filter files under `Stella/Core/src/common/tv_filters/`; no single top-level Stella license file found in this pass | Needs confirmation | Confirm main Stella core license and add exact license file/source obligation evidence. |

---

## In-tree cores/directories needing plugin-status confirmation

These directories exist in the repository, but no current native plugin `Info.plist` was found in the expected top-level/core path during this pass.

| Directory | System(s) / purpose | License evidence found | Follow-up |
| --- | --- | --- | --- |
| Atari800 | Atari 5200 / Atari 8-bit | Not checked in this pass | Confirm whether native plugin packaging exists and add license evidence. |
| blueMSX | MSX / ColecoVision fallback | Not checked in this pass | Confirm whether native plugin packaging exists and add license evidence. |
| DeSmuME | Nintendo DS | `DeSmuME/COPYING` plus dependency licenses | Confirm plugin/package status and license obligations. |
| PokeMini | Pokémon Mini | `PokeMini/PokeMini/pokemini-code/LICENSE` | Confirm plugin/package status and license obligations. |
| VecXGL | Vectrex | Not checked in this pass | Confirm plugin/package status and license evidence. |
| VirtualJaguar | Atari Jaguar | Not checked in this pass | Confirm plugin/package status and license evidence. |
| MAME | Arcade / experimental | Not checked in this pass | Experimental PR work; confirm if/when shipped. |

---

## Follow-up checklist

- [ ] Confirm upstream licenses for every **Needs confirmation** row.
- [ ] Confirm which in-tree core directories are actually distributed as user-facing plugin bundles.
- [ ] Add exact SPDX-style license names where possible.
- [ ] Add source/binary distribution obligations for GPL/LGPL/MPL/non-commercial cores.
- [ ] Confirm app release packaging includes or links required license text/source for each shipped binary.
- [ ] Keep Picodrive and SNES9x non-commercial constraints visible in release/submission notes.
