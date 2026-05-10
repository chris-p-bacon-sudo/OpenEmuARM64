# OpenEmu-Silicon — Native Apple Silicon Port

<p align="center">
  <img width="301" height="91" alt="logo" src="https://github.com/user-attachments/assets/e4c7ee8d-b526-4fa7-bf61-153dc1594372" />
</p>

<p align="center">
  <img width="2276" height="1550" alt="OpenEmu Library" src="https://github.com/user-attachments/assets/3797ba95-3e8c-49f6-9d3d-ab1cca6e70b9" />
</p>

---

## Current Status

**Actively maintained. Runs natively on Apple Silicon (no Rosetta required).**

This is a community-maintained fork of OpenEmu for M-series Macs. The app runs on macOS 11.0+ and has been tested on macOS Sequoia and macOS 26 (Tahoe).

> **Download:** Get the latest signed DMG from the **[Releases](https://github.com/nickybmon/OpenEmu-Silicon/releases)** page. The app is notarized — no Gatekeeper workaround needed.

---

## What this fork is (and isn't)

OpenEmu is the work of an exceptional team of developers who built one of the finest pieces of Mac software ever made — and kept improving it for over a decade.

[**stuartcarnie**](https://github.com/stuartcarnie) added Metal rendering in 2019, replacing OpenGL across the entire app and delivering a significant improvement to frame pacing, battery life, and display quality. [**MaddTheSane**](https://github.com/MaddTheSane) (C.W. Betts) did the ARM64 porting work across the emulation cores starting in January 2021 — removing x86-only architecture restrictions, updating static libraries, adding ARM64 linkage support, and making architecture-specific CPU code conditional. The top contributors by commit count — [**cyco**](https://github.com/cyco), [**clobber**](https://github.com/clobber), [**J-rg**](https://github.com/J-rg), and others — built the app, the plugin architecture, and the library experience that makes OpenEmu what it is. None of that work originated here.

What never happened is a release. The ARM64 core work landed in the repos and stayed there. The last official binary (OpenEmu 2.4.1, December 2023) was Intel-only — explicitly stated in its release notes. [**bazley82**](https://github.com/bazley82) was the first to assemble those ARM64-capable cores into a downloadable build in early 2026. This fork continued from there.

**What this fork provides:**
- **A downloadable, notarized, native ARM64 binary** — the original project's ARM64 work was never published as a release.
- **Active maintenance** — macOS 26 (Tahoe) compatibility, updated cores, and ongoing bug fixes.
- **New features not in the original** — RetroAchievements, ScreenScraper cover art, RetroArch Core Support, Google Drive save sync (being verified by Google), and several new or restored systems, such as Dolphin, PPSSPP (RetroArch), and Flycast.

**On Rosetta 2:** Apple has confirmed that starting with macOS 26.4, the OS will notify users each time they launch a Rosetta-dependent app. If you want to stay ahead of that, this fork is a drop-in replacement. ([full details on the wiki](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Why-Native-ARM64-Matters))

---

## Download

Get the latest build from the **[Releases](https://github.com/nickybmon/OpenEmu-Silicon/releases)** page.

### Install via Homebrew

```bash
brew tap nickybmon/OpenEmu-Silicon https://github.com/nickybmon/OpenEmu-Silicon
brew install --cask openemu-silicon
```

---

## What's New in v1.1.0

### Libretro Bridge — run RetroArch cores inside OpenEmu *(Experimental)*

OpenEmu Silicon now ships a **Libretro Bridge** (built with [pystIC](https://github.com/pystIC)) — a translation layer that lets you load RetroArch / libretro cores directly, without per-core ports. Working in 1.1.0: PSP via PPSSPP-libretro, Atari 2600, and Commodore 64 via VICE. Hardware-rendered cores (Dolphin, melonDS) and Dreamcast via Flycast-libretro are not yet supported — use the native Flycast core for Dreamcast.

→ [Setup guide and supported cores list](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Using-RetroArch-Cores)

### RetroAchievements — Phase 2

Two more system families earn achievements: **Nintendo 64** (Mupen64Plus) and **PlayStation, PC Engine, Lynx, and Neo Geo Pocket** (Mednafen). Log in once in Preferences → Achievements. Full supported list: GBA, GB/GBC, SNES, NES, Genesis/Mega Drive/CD, Master System/Game Gear, N64, PSX, PC Engine, Lynx, NGP.

### Core update pipeline fixed

If you've seen "Update Available" loop without anything changing, or cores felt stuck on old versions — 1.1.0 fixes that. The update feed was pointing at stale upstream sources instead of this fork's own. Existing installations migrate automatically on first launch.

### Other improvements

- **Cheats persist** — User-added cheat codes are saved and re-applied automatically on game load.
- **ScreenScraper maps 16 more systems** — Covers and metadata now fetch for systems that were previously missing.
- **Window resize artifacts fixed** — Maximising or resizing no longer leaves ghost content layers.
- **Dreamcast fixes** — JIT re-enabled (fixes 27fps / half-speed issue); black screen on second launch fixed; PSX multi-disc games no longer require a manual `.m3u` file.
- **Input Monitoring detection fixed** — If permission was already granted before launch, the prompt no longer re-appears and controllers respond immediately.

**Earlier highlights:**
- **RetroAchievements Phase 1** — NES, SNES, GB/GBC, GBA, Genesis family.
- **Nintendo 64** — Mupen64Plus revived and working.
- **Sega Dreamcast** — Migrated from Reicast to Flycast.
- **GameCube / Wii** — Dolphin core integrated.
- **ScreenScraper cover art** — Automatic box art via [ScreenScraper](https://www.screenscraper.fr).

---

## Supported Systems

> **Full details — working status, known issues, in-progress cores, and what's planned — are on the [Supported Systems](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Supported-Systems) wiki page.**

Quick summary: 30+ systems work today, including NES, SNES, Game Boy, GBA, N64, PlayStation, Dreamcast, and more. A handful have known issues (PSP, Saturn, Game Boy Color categorization). GameCube/Wii (Dolphin) and Nintendo DS (melonDS) are actively in progress. PS2 has no core yet.

---

## Known Issues

- **Save state compatibility** — Save states from certain older cores are incompatible with current ARM64 builds and will crash if loaded. On launch, the app detects these and shows a warning dialog. **Back up your save states before your first launch** — see [Migrating from OpenEmu](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Migrating-from-OpenEmu) for the full list and instructions.
- Input Monitoring permission may need to be granted manually in System Settings → Privacy & Security.
- A few cores have quirks on Apple Silicon still being investigated (see open issues).

---

## Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)

---

## About This Project

The original OpenEmu is still an amazing piece of Mac software. [stuartcarnie](https://github.com/stuartcarnie) brought Metal rendering to the app in 2019. [MaddTheSane](https://github.com/MaddTheSane) ported the emulation cores to ARM64 starting in 2021. [cyco](https://github.com/cyco), [clobber](https://github.com/clobber), [J-rg](https://github.com/J-rg), and the rest of the OpenEmu team built the application, the plugin architecture, and the library experience over more than a decade. That work is the foundation everything here stands on.

The original project went quiet around 2024 after the last release. By that time, the original team had already done significant work on the ARM64 cores. The ARM64 core work was real and substantial, but it was never assembled into a release — the last official binary (December 2023) was stated as Intel-only. [bazley82](https://github.com/bazley82) published a downloadable ARM64 build in early 2026, pulling together the ARM64-capable core submodules the original team had prepared into a single repo and release. This fork continued from there: RetroAchievements shipped across 9+ cores; a Libretro Bridge was built to load RetroArch cores directly inside OpenEmu; ScreenScraper cover art was integrated; Dreamcast was migrated from Reicast to Flycast; save persistence, system detection, and the core update pipeline were all fixed; and the app was hardened for macOS 26 (Tahoe).

**Lineage:**
- [OpenEmu/OpenEmu](https://github.com/OpenEmu/OpenEmu) — the original project
- [bazley82/OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64) — ARM64 build, built on the original team's core work and what I started building upon
- **This repo** — continued development and maintenance by [@nickybmon](https://github.com/nickybmon) and others.

---

## A Note on AI-Assisted Development

I work on this project with AI assisted development practices — they help me write and debug code I couldn't write alone. I review every change, test everything, and make all the calls about direction and quality. I'm transparent about this because honesty with the community matters more than maintaining an illusion of expertise I don't have. The goal is to keep something good alive and make it genuinely usable for players.

---

## Documentation

| Doc | What's in it |
|-----|-------------|
| [Wiki](https://github.com/nickybmon/OpenEmu-Silicon/wiki) | User guides: getting started, BIOS files, importing, CD games, controllers, troubleshooting |
| [Migrating from OpenEmu](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Migrating-from-OpenEmu) | Switching from the original OpenEmu: what carries over, what doesn't, and how to back up |
| [Supported Systems](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Supported-Systems) | Every system: working status, known issues, in-progress cores, what's planned, and BIOS requirements |
| [The Libretro Bridge](https://github.com/nickybmon/OpenEmu-Silicon/wiki/The-Libretro-Bridge) | What the libretro bridge is, what it changes for you as a player, and why this fork uses it |
| [`CREDITS.md`](.github/CREDITS.md) | Everyone who contributed — original OpenEmu team, ARM64 port, core sources, illustrators, and this repo's contributors |

---

## Contributing

Issues, PRs, and testing feedback are all welcome. If something breaks for you, open an issue and describe your Mac model, macOS version, and which system/game you were running. That context is the most valuable thing you can provide.

If you want to contribute code, check the open issues for good starting points. A clear PR description of what it fixes is the best kind of contribution.

---

## License

The main OpenEmu app and SDK are licensed under the **BSD 2-Clause License**. Individual emulation cores carry their own licenses (GPL v2, MPL 2.0, LGPL 2.1, and others) — see each core's directory for details.

Note: [picodrive](https://github.com/notaz/picodrive) includes a non-commercial clause. This project is and will remain free.
