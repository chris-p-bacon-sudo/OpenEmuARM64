## What's New in 1.2.3

- Cheats can now be edited and removed without leaving the game — tap the cheat menu in the controls bar to modify existing codes on the fly
- RetroAchievements: Hardcore mode progress is now preserved across sessions, achievements earned offline are queued and submitted automatically when connectivity is restored, and slow motion is now correctly blocked during hardcore sessions
- The Preferences window now floats above the game so you can adjust settings without interrupting play

## Bug Fixes

- Fixed a freeze that could occur while scrolling or searching the game library
- Fixed a RetroAchievements crash and state loss that could occur when switching between games (thanks @tao-bioinfo, #579)
- Core updates installed through the in-app updater now correctly preserve Developer ID signatures — previously the updater would overwrite a properly-signed core with an ad-hoc signature; also added a warning when duplicate core bundles are detected in the cores folder
- Sega Saturn games now appear as an available update in Preferences → Cores — the Mednafen core was missing from the core registry so Saturn users were not being offered updates
- Picodrive no longer incorrectly lists Sega CD support; Sega CD is handled by Genesis Plus GX
