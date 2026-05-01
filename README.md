# OpenEmu-Silicon — Native Apple Silicon Port

<p align="center">
  <img width="301" height="91" alt="logo" src="https://github.com/user-attachments/assets/e4c7ee8d-b526-4fa7-bf61-153dc1594372" />
</p>

<p align="center">
  <img src="docs/images/library-screenshot.png" width="800" alt="OpenEmu library running natively on Apple Silicon"/>
</p>

---

## Current Status

**Actively maintained. Running natively on Apple Silicon (no Rosetta required).**

This is a community-maintained fork of OpenEmu, rebuilt to run natively on M-series Macs. All emulation cores have been ported to ARM64. The app runs on macOS 11.0+ and has been tested on macOS Sequoia and macOS 26 (Tahoe).

> **Download:** Get the latest signed DMG from the **[Releases](https://github.com/nickybmon/OpenEmu-Silicon/releases)** page. The app is notarized — no Gatekeeper workaround needed.

---

## Why this exists if original OpenEmu already works on your M-series Mac

It probably does work — Rosetta 2 is genuinely impressive at hiding the fact that you're running an Intel app on Apple Silicon. Here's what's actually happening and why it matters.

**What the original OpenEmu does on Apple Silicon**
The original project was built for Intel Macs and hasn't had a release for some time. When you run it on an M-series Mac, macOS silently runs it through Rosetta 2 — Apple's x86-to-ARM translation layer. Rosetta is remarkably good, which is why many people never notice.

**What this build does differently**
- **Native ARM64** — every emulation core runs directly on the Apple Silicon chip, no translation layer
- **Metal renderer** — Apple deprecated OpenGL; this build uses Metal, the native macOS graphics API
- **Active maintenance** — updated cores, macOS 26 (Tahoe) compatibility fixes, and new systems added

**When you might notice a real difference**
For lighter systems (NES, SNES, GBA), you probably won't. For heavier cores — N64, PlayStation, Dreamcast, PSP — native execution means lower CPU overhead, better frame pacing, and less fan activity during long sessions.

**Rosetta 2 has a confirmed end of life**
Starting with macOS 26.4, Apple will show a notification every time you launch an app that still requires Rosetta — alerting users to find native alternatives. Starting with macOS 28 (expected Fall 2027), Rosetta 2 will be largely discontinued. When that happens, the original OpenEmu stops working entirely. This build won't be affected.

If original OpenEmu meets your needs today, there's no urgency. But if you've had a core feel sluggish, noticed audio issues, or want to be ahead of the Rosetta end-of-life, this is a build you can switch to now or someday. ([full details on the wiki](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Why-Native-ARM64-Matters))

---

## Download

Get the latest build from the **[Releases](https://github.com/nickybmon/OpenEmu-Silicon/releases)** page.

### Install via Homebrew

```bash
brew tap nickybmon/OpenEmu-Silicon https://github.com/nickybmon/OpenEmu-Silicon
brew install --cask openemu-silicon
```

---

## What's New in v1.0.7

- **RetroAchievements — Phase 1** — Earn achievements automatically as you play across 9 cores and 7 systems: NES (FCEU, Nestopia), SNES (SNES9x, BSNES), Game Boy / GBC (Gambatte, mGBA), Game Boy Advance (mGBA), and Genesis / Master System / Game Gear / Sega CD / SG-1000 (Genesis Plus GX). Log in once in Preferences → Achievements. See the [RetroAchievements wiki page](https://github.com/nickybmon/OpenEmu-Silicon/wiki/RetroAchievements) for setup.
- **Play With… core selection** — Right-click any game in your library and choose **Play With…** to pick which core to use for that session, without changing your default.
- **3DO now works out of the box** — A bundle identifier bug was silently dropping the 3DO system at launch. Fixed — 3DO appears in your console list automatically with no extra steps.
- **SNES rewind fixed** — Rewinding no longer produces a blank screen.
- **PSX black bar fixed** — PlayStation games no longer show a black bar on the right side of the screen.
- **N64 GameShark cheats fixed** — Cheat codes now apply correctly in Mupen64Plus.
- **Dreamcast speed and audio fixed** — Flycast no longer runs faster than real-time on high-refresh-rate displays, and the distorted audio that came with it is gone.
- **NES color palette restored** — FCEU was rendering all NES games with a washed-out grey palette due to a regression. Fixed.

**Earlier highlights:**
- **Sony PSP** — PPSSPP-Core rebuilt and integrated.
- **Nintendo 64** — Mupen64Plus revived and working.
- **Sega Dreamcast** — Migrated from Reicast to Flycast for a significantly more stable experience.
- **GameCube / Wii** — Dolphin core integrated and working.
- **ScreenScraper cover art** — Automatic box art via [ScreenScraper](https://www.screenscraper.fr). Enter credentials in Preferences → Cover Art.
- **macOS 26 (Tahoe) compatibility** — Full support verified.

---

## Supported Systems

> **Full details — working status, known issues, in-progress cores, and what’s planned — are on the [Supported Systems](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Supported-Systems) wiki page.**

Quick summary: 30+ systems work today, including NES, SNES, Game Boy, GBA, N64, PlayStation, Dreamcast, and more. A handful have known issues (PSP, Saturn registration, Game Boy Color categorization). GameCube/Wii (Dolphin) and a new Nintendo DS core (melonDS) are actively in progress. Commodore 64, Arcade/MAME, and PS2 have no core yet.

**Also working:** controller mapping and detection, save states, Google Drive sync for saves, ScreenScraper cover art.

---

## Known Issues

- **Save state compatibility** — Save states from certain older cores are incompatible with the current ARM64 builds and will crash if loaded. On launch, the app detects these and shows a warning dialog listing the affected cores and count. You can delete them immediately or keep them and back up first. **We strongly recommend backing up your save states before your first launch** — see [Migrating from OpenEmu](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Migrating-from-OpenEmu) for instructions and the full list of affected cores.
- A few cores have quirks on Apple Silicon still being investigated (see open issues)
- Input Monitoring permission may need to be granted manually in System Settings → Privacy & Security

---

## Requirements

- macOS 11.0 (Big Sur) or later
- Apple Silicon Mac (M1 / M2 / M3 / M4)

---

## About This Project

OpenEmu is one of the best pieces of Mac software ever made — a beautifully designed, first-class game emulation frontend that brought together dozens of emulation cores under a single native macOS UI. The original project went quiet around 2022.

This fork started from [bazley82's OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64), which did the foundational work of porting all 25 cores to build natively on Apple Silicon. Since then this project has diverged significantly: Nintendo 64 and Pokémon Mini were rebuilt from scratch and brought back online; PPSSPP was fully re-integrated to add PSP emulation on Apple Silicon; Dreamcast was migrated from the stale Reicast codebase to Flycast for a much more stable experience; ScreenScraper cover art was integrated to bring the library back to life; RetroAchievements support shipped across 9 cores; core updates shipped (SNES9x 1.63.1, mGBA 0.10.6, Mupen64Plus 2.5.11); and the entire app was hardened for macOS 26 (Tahoe) compatibility. The goal is to make OpenEmu genuinely great on modern Macs again — not just technically booting, but actually usable for players.

**Lineage:**
- [OpenEmu/OpenEmu](https://github.com/OpenEmu/OpenEmu) — the original project, built by the OpenEmu team
- [bazley82/OpenEmuARM64](https://github.com/bazley82/OpenEmuARM64) — the ARM64 port that this fork is built on
- **This repo** — continued development and maintenance by [@nickybmon](https://github.com/nickybmon)

---

## A Note on AI-Assisted Development

I'm not a professional developer. I work on this project using Cursor and Claude as development assistants — they help me write and debug code I couldn't write alone. I review every change, test everything, and make all the calls about direction and quality.

I'm transparent about this because honesty with the community matters more than maintaining an illusion of expertise I don't have. The goal is to keep something good alive and make it genuinely usable for players.

---

## Documentation

| Doc | What's in it |
|-----|-------------|
| [Wiki](https://github.com/nickybmon/OpenEmu-Silicon/wiki) | User guides: getting started, BIOS files, importing, CD games, controllers, troubleshooting |
| [Migrating from OpenEmu](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Migrating-from-OpenEmu) | Switching from the original OpenEmu: what carries over, what doesn't, and how to back up |
| [Supported Systems](https://github.com/nickybmon/OpenEmu-Silicon/wiki/Supported-Systems) | Every system: working status, known issues, in-progress cores, what's planned, and BIOS requirements |
| [The Libretro Bridge](https://github.com/nickybmon/OpenEmu-Silicon/wiki/The-Libretro-Bridge) | What the libretro bridge is, what it changes for you as a player, and why this fork uses it |
| [`CREDITS.md`](CREDITS.md) | Everyone who contributed — original OpenEmu team, ARM64 port, core sources, illustrators, and this repo's contributors |

---

## Contributing

Issues, PRs, and testing feedback are all welcome. If something breaks for you, open an issue and describe your Mac model, macOS version, and which system/game you were running. That context is the most valuable thing you can provide.

If you want to contribute code, check the open issues for good starting points. A simple PR with a clear description of what it fixes is the best kind of contribution.

---

## License

The main OpenEmu app and SDK are licensed under the **BSD 2-Clause License**. Individual emulation cores carry their own licenses (GPL v2, MPL 2.0, LGPL 2.1, and others) — see each core's directory for details.

Note: [picodrive](https://github.com/notaz/picodrive) includes a non-commercial clause. This project is and will remain free.
