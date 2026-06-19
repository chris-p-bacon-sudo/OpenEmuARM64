## What's New in 1.2.4

- **RetroAchievements hardcore is now fully supported.** OpenEmu-Silicon now reports its version correctly to RetroAchievements — it previously sent "unknown," which RetroAchievements rejected and which blocked hardcore unlocks. Fast-forward is now allowed during hardcore sessions (rewind, slow-motion, and frame-step stay disabled, as RetroAchievements requires).
- The import dialog now accepts more Atari 8-bit formats — `.xex`, `.car`, and `.atr` (thanks @cwscws, #581).

## Bug Fixes

- Atari 5200 games now render video correctly on the bundled Atari800 core (thanks @CamberwelK, #432).
- Fixed a crash that could occur when connecting a controller during Nintendo 64 games.
- Virtual Boy games that rely on render-time effects (such as Golf) now display correctly.
- The Add Cheat dialog now shows the right format guidance per system, and Nintendo 64 cheat codes in unsupported formats are flagged instead of being silently rejected.
- The game library grid scrolls more smoothly.
- The Settings window no longer stays on top of other windows.
- Game Boy and Game Boy Color preferences are now labeled correctly.
