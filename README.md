# OpenEmuARM64 — Native Apple Silicon Port

<p align="center">
  <img src="docs/images/openemu-icon.png" width="128" alt="OpenEmu"/>
</p>

<p align="center">
  <img src="docs/images/library-screenshot.png" width="800" alt="OpenEmu library running natively on Apple Silicon"/>
</p>

---

## Current Status

**Actively maintained. Running natively on Apple Silicon (no Rosetta required).**

This is a community-maintained fork of OpenEmu, rebuilt to run natively on M-series Macs. All 25 emulation cores have been ported to ARM64. The app runs on macOS 11.0+ and has been tested on macOS Sequoia and macOS 26 (Tahoe).

> **Note:** Code signing and notarization are not yet fully sorted. On first launch, right-click the app and choose Open to bypass Gatekeeper.

---

## Download

Get the latest build from the **[Releases](https://github.com/chris-p-bacon-sudo/OpenEmuARM64/releases)** page.

---

## What Works

| System | Core | Status |
|--------|------|--------|
| Atari 2600 | [Stella](https://github.com/stella-emu/stella) | Working |
| Atari 5200 | [Atari800](https://github.com/atari800/atari800) | Working |
| Atari 7800 | [ProSystem](https://gitlab.com/jgemu/prosystem) | Working |
| Atari Lynx | [Mednafen](https://mednafen.github.io) | Working |
| ColecoVision | [JollyCV](https://github.com/OpenEmu/JollyCV-Core) | Working |
| Commodore 64 | VICE | Working |
| Famicom Disk System | [Nestopia](https://gitlab.com/jgemu/nestopia) | Working |
| Game Boy / GBC | [Gambatte](https://gitlab.com/jgemu/gambatte) | Working |
| Game Boy Advance | [mGBA](https://github.com/mgba-emu/mgba) | Working |
| Game Gear | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | Working |
| Intellivision | [Bliss](https://github.com/jeremiah-sypult/BlissEmu) | Working |
| Nintendo (NES) | [Nestopia](https://gitlab.com/jgemu/nestopia), [FCEU](https://github.com/TASEmulators/fceux) | Working |
| Nintendo 64 | [Mupen64Plus](https://github.com/mupen64plus) | Working |
| Nintendo DS | [DeSmuME](https://github.com/TASEmulators/desmume) | Working |
| Odyssey² / Videopac+ | [O2EM](https://sourceforge.net/projects/o2em/) | Working |
| Pokémon Mini | [PokeMini](https://github.com/pokerazor/pokemini) | Working |
| Sega 32X | [picodrive](https://github.com/notaz/picodrive) | Working |
| Sega CD / Mega CD | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | Working |
| Sega Genesis / Mega Drive | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | Working |
| Sega Master System | [Genesis Plus GX](https://github.com/ekeeke/Genesis-Plus-GX) | Working |
| Sega Saturn | [Mednafen](https://mednafen.github.io) | Working |
| Sony PlayStation | [Mednafen](https://mednafen.github.io) | Working |
| Super Nintendo (SNES) | [BSNES](https://github.com/bsnes-emu/bsnes), [Snes9x](https://github.com/snes9xgit/snes9x) | Working |
| Vectrex | [VecXGL](https://github.com/james7780/VecXGL) | Working |
| WonderSwan | [Mednafen](https://mednafen.github.io) | Working |
| 3DO | [4DO](https://github.com/fourdo/fourdo) | Working |

**Also working:** controller mapping and detection, save states, Google Drive sync for saves.

---

## Known Issues

- Code signing / notarization not yet sorted — right-click > Open on first launch
- A few cores have quirks on Apple Silicon still being investigated
- Input Monitoring permission may need to be granted manually in System Settings → Privacy & Security

---

## Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)

---

## About This Project

OpenEmu is one of the best pieces of Mac software ever made — a beautifully designed, first-class game emulation frontend that brought together dozens of emulation cores under a single native macOS UI. The original project went quiet around 2022.

This fork started from [bazley82's OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64), which did the foundational work of porting all 25 cores to build natively on Apple Silicon. When that repo also went quiet, independent development continued here — fixing macOS 26 compatibility issues, hardening the build, and setting up community infrastructure to keep the project alive.

**Lineage:**
- [OpenEmu/OpenEmu](https://github.com/OpenEmu/OpenEmu) — the original project, built by the OpenEmu team
- [bazley82/OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64) — the ARM64 port that this fork is built on
- **This repo** — continued development and maintenance by [@chris-p-bacon-sudo](https://github.com/chris-p-bacon-sudo)

---

## A Note on AI-Assisted Development

I'm not a professional developer. I work on this project using Cursor and Claude as development assistants — they help me write and debug code I couldn't write alone. I review every change, test everything, and make all the calls about direction and quality.

I'm transparent about this because honesty with the community matters more than maintaining an illusion of expertise I don't have. The goal is to keep something good alive and make it genuinely usable for players.

---

## Contributing

Issues, PRs, and testing feedback are all welcome. If something breaks for you, open an issue and describe your Mac model, macOS version, and which system/game you were running. That context is the most valuable thing you can provide.

If you want to contribute code, check the open issues for good starting points. A simple PR with a clear description of what it fixes is the best kind of contribution.

---

## License

The main OpenEmu app and SDK are licensed under the **BSD 2-Clause License**. Individual emulation cores carry their own licenses (GPL v2, MPL 2.0, LGPL 2.1, and others) — see each core's directory for details.

Note: [picodrive](https://github.com/notaz/picodrive) includes a non-commercial clause. This project is and will remain free.
