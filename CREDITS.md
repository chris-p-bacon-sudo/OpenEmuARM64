# Credits

OpenEmu-Silicon stands on the shoulders of a lot of excellent work. This file honors everyone who has contributed to the project — from the original OpenEmu team to the illustrators who made the controller artwork.

---

## Original OpenEmu Project

The original OpenEmu application was built by the OpenEmu Team — a group of developers who created one of the best pieces of Mac software ever made.

- **OpenEmu/OpenEmu** — https://github.com/OpenEmu/OpenEmu

The full contributor history for the original project is preserved in that repository.

---

## ARM64 Port Foundation

The foundational work of porting all emulation cores to build natively on Apple Silicon was done by bazley82.

- **bazley82/OpenEmuARM64** — https://github.com/bazley82/OpenEmuARM64
  - Systematic ARM64 port of all 25 emulation cores
  - App update via GitHub (Sparkle) and Per-Core Revert feature
  - Core Preferences UI refactor
  - VirtualC64 core for Commodore 64
  - Appcast infrastructure

Earlier foundational work in the same lineage by **Barrie Sanders**:
  - Google Drive Save Sync Manager (ARM64 native)
  - Initial ARM64 port finalization, Cloud Sync scaffolding, and localization

---

## Emulator Core Sources

The emulation cores in this repo are derived from the following upstream projects. Wrapper code (OEGameCore subclasses, Xcode project files) originates from OpenEmu's core repositories.

| Core | Upstream Project |
|------|----------------|
| Gambatte, FCEU, Nestopia, SNES9x, Mupen64Plus, mGBA, GenesisPlus, Mednafen, Stella, Atari800, Bliss, JollyCV, O2EM, PokeMini, Potator, ProSystem, VecXGL, VirtualJaguar, CrabEmu, blueMSX, 4DO, picodrive, Reicast/Flycast, BSNES | OpenEmu core repositories — https://github.com/OpenEmu |
| PPSSPP | OpenEmu/PPSSPP-Core wrapper — https://github.com/OpenEmu/PPSSPP-Core, against PPSSPP 1.14.4 source. Prebuilt FFmpeg libs from hrydgard/ppsspp-ffmpeg — https://github.com/hrydgard/ppsspp-ffmpeg |
| Dolphin (GameCube/Wii) | dolphin-emu/dolphin — https://github.com/dolphin-emu/dolphin, pinned to the 2603 release. OpenEmu Metal backend integration layer written for this project. |

---

## OpenEmu-Silicon

Continued development, macOS compatibility updates, and community infrastructure for this repository.

- **nickybmon** — https://github.com/nickybmon

---

## Contributors to This Repository

- **pystIC** — https://github.com/pystIC
  Review of [pystIC/OpenEmuARM64-metal4-shaders-core-updates](https://github.com/pystIC/OpenEmuARM64-metal4-shaders-core-updates) identified the Metal 4 shader version crash fix and fast math optimization landed in [PR #44](https://github.com/nickybmon/OpenEmu-Silicon/pull/44), and flagged the mGBA and SNES9x upstream version gaps tracked in [#42](https://github.com/nickybmon/OpenEmu-Silicon/issues/42) and [#43](https://github.com/nickybmon/OpenEmu-Silicon/issues/43).

<!-- Contributors: your name and GitHub profile link will be added here as PRs are merged. -->

If you've contributed a fix, feature, or improvement to this repository and your name isn't listed here, please open a PR to add it.

---

## App Icon

- **hectorlizard** — App icon design, sourced from [macosicons.com](https://macosicons.com/u/hectorlizard)

---

## Controller Illustrations

OpenEmu has detailed controller illustrations in OpenEmu > Preferences… > Controls. Here's who made them.

| System | Credit | Twitter |
|-----------------------|---------------------------|----------------------------------------------|
| 32X | David McLeod | [@Mucx][Mucx] |
| 3DO | David Everly | [@selfproclaim][selfproclaim] |
| Atari 2600 | Ricky Romero | [@RickyRomero][RickyRomero] |
| Atari 5200 | Ricky Romero | [@RickyRomero][RickyRomero] |
| Atari 7800 | Salvo Zummo | [@noisymemories][noisymemories] |
| Atari Lynx | Salvo Zummo | [@noisymemories][noisymemories] |
| ColecoVision | Kate Schroeder | [@medgno][medgno] |
| Dreamcast | Craig Erskine | [@qrayg][qrayg] |
| Famicom Disk System | David McLeod | [@Mucx][Mucx] |
| Game Boy | David McLeod | [@Mucx][Mucx] |
| Game Boy Advance | David McLeod | [@Mucx][Mucx] |
| Game Gear | David McLeod | [@Mucx][Mucx] |
| GameCube | Craig Erskine | [@qrayg][qrayg] |
| Intellivision | Ricky Romero | [@RickyRomero][RickyRomero] |
| Master System | David McLeod | [@Mucx][Mucx] |
| Neo Geo Pocket | Craig Erskine, Ricky Romero | [@qrayg][qrayg], [@RickyRomero][RickyRomero] |
| NES/Famicom | David McLeod | [@Mucx][Mucx] |
| Nintendo 64 | Ricky Romero | [@RickyRomero][RickyRomero] |
| Nintendo DS | Ricky Romero | [@RickyRomero][RickyRomero] |
| Odyssey² | Ricky Romero | [@RickyRomero][RickyRomero] |
| PC Engine | Craig Erskine | [@qrayg][qrayg] |
| PC Engine CD | Craig Erskine | [@qrayg][qrayg] |
| PC-FX | Salvo Zummo | [@noisymemories][noisymemories] |
| PlayStation | Ricky Romero | [@RickyRomero][RickyRomero] |
| PlayStation 2 | Ricky Romero | [@RickyRomero][RickyRomero] |
| PSP | Ricky Romero | [@RickyRomero][RickyRomero] |
| Sega CD | David McLeod | [@Mucx][Mucx] |
| Sega Genesis/Mega Drive | David McLeod | [@Mucx][Mucx] |
| Sega Saturn | Ricky Romero | [@RickyRomero][RickyRomero] |
| SG-1000 | Ricky Romero | [@RickyRomero][RickyRomero] |
| SNES/Super Famicom | David McLeod | [@Mucx][Mucx] |
| TurboGrafx-16 | Craig Erskine | [@qrayg][qrayg] |
| Vectrex | Ricky Romero | [@RickyRomero][RickyRomero] |
| Virtual Boy | Ricky Romero | [@RickyRomero][RickyRomero] |
| WonderSwan | Salvo Zummo | [@noisymemories][noisymemories] |

[medgno]: https://twitter.com/medgno/
[Mucx]: https://twitter.com/Mucx/
[noisymemories]: https://twitter.com/noisymemories/
[qrayg]: https://twitter.com/qrayg/
[RickyRomero]: https://twitter.com/RickyRomero/
[selfproclaim]: https://twitter.com/selfproclaim/

---

*The complete commit history for the upstream projects lives in their respective repositories linked above. This file acknowledges the lineage this project descends from.*
