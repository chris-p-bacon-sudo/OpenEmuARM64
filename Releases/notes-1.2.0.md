## What's New in 1.2.0

- **Nintendo DS** — OpenEmu now includes a native DeSmuME core for Nintendo DS. DS games run natively on Apple Silicon with full dual-screen support, save states, and controller input. Import your .nds files and they'll appear in a new Nintendo DS library automatically.
- **Arcade (experimental)** — A native MAME core is now bundled for Arcade games. Sprite-based classics like Donkey Kong, Pac-Man, and Street Fighter II work well. Polygonal 3D hardware (Sega Model 1/2/3) has known rendering limitations — tracked in [#551](https://github.com/nickybmon/OpenEmu-Silicon/issues/551).
- **RetroAchievements UI** — The in-game achievements experience is substantially improved. An achievement list panel shows your progress mid-session, gameplay event indicators appear on-screen when achievements unlock or are close to triggering, and online/offline status is shown at a glance. Games not recognized by RetroAchievements now surface a clear explanation rather than silently doing nothing.
- **Core updates (cores-v1.3.3)** — All RetroAchievements-capable cores were rebuilt and updated. Cores that previously needed the RA token before launch now initialize correctly on the first try.

## Bug Fixes

- Fixed a RetroAchievements token race on app launch that could prevent achievement tracking from starting until the app was restarted.
- Fixed a hang when creating or loading save states that could occur when the Core Data save was dispatched synchronously on the game thread.
- Fixed the "retry with another core" flow for Arcade ROMs — after a failed launch, retrying with a different core now works correctly instead of getting stuck in a broken state.
- Fixed keychain prompts appearing after the credential migration from the old macOS Keychain store to the encrypted file store.
- Fixed a duplicate core list startup error that appeared in the console on first launch.
- Fixed DeSmuME display layout switching — toggling between stacked and side-by-side screen arrangements no longer leaves a gap or misaligns the touch screen.
- Fixed 3DO video rendering in Release builds (4DO core) — games no longer show a black screen on release-config launches.
- Fixed 3DO libretro import path issue that prevented some 3DO ROMs from loading via the libretro bridge.
- Fixed app hang reports (AppHang in Sentry) caused by VGDB sync and RetroAchievements core scanning running on the main thread — both are now dispatched asynchronously.
- Fixed an en-GB partial localization causing string fallback issues on systems set to British English.

## Known Limitations

- **MAME polygonal 3D** — Games relying on Sega Model 1/2/3 or other polygonal 3D hardware have rendering and audio issues. Tracked in [#551](https://github.com/nickybmon/OpenEmu-Silicon/issues/551).
