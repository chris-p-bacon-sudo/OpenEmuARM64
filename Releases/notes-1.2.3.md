## What's New in 1.2.3

- Cheats can now be edited and removed without leaving the game — tap the cheat menu in the controls bar to modify existing codes on the fly (#591)
- RetroAchievements: Hardcore mode progress is now preserved across sessions, achievements earned offline are queued and submitted when connectivity returns, and slow motion is now correctly blocked during hardcore sessions (#587, #586)
- The Preferences window now floats above the game so you can adjust settings without interrupting play (#578)

## Bug Fixes

- Fixed a crash in the helper process affecting all six RetroAchievements-enabled cores (SNES9x, Gambatte, FCEU, Nestopia, mGBA, Mednafen) — the rcheevos client was being mutated simultaneously from three threads with no serialization, causing `EXC_BAD_INSTRUCTION` on game load. A new serial bridge (`OERetroAchievementsBridge`) now owns the client and serializes all access (thanks @tao-bioinfo, #579, #588)
- Fixed a 2000ms+ main-thread hang when typing in the search field with a large game library on macOS 26 Tahoe — each keystroke was triggering a synchronous IPC-locked preferences read for every game in the library (#582)
- The "RA: Unknown emulator" chip that previously overlapped game video is replaced by an auto-hiding placard when RetroAchievements has not yet approved the client for hardcore credit (#588)
- Core updates installed through the in-app updater now correctly preserve Developer ID signatures — previously re-signing would overwrite a properly-signed core with an ad-hoc signature; also added a warning when duplicate core bundles are detected (#592)
- Sega Saturn games now appear as an available update in Preferences → Cores — the Mednafen core was missing from the core registry so Saturn users were not being offered updates (#590)
- Picodrive no longer incorrectly lists Sega CD support; Sega CD is handled by Genesis Plus GX (#590)

## Under the Hood

- RetroAchievements network requests now include the active core name and version in the User-Agent string — required for the RA server to grant hardcore credit to this client (#586)
- Crash reports in Sentry are now fully symbolicated for all shipped binaries — dSYM verification is enforced before each release and release markers are registered so issues show "First seen in vX.Y.Z" (#576, #593)
- App releases now route through a PR before the Sparkle appcast goes live, ensuring CI version checks pass first (#574)
