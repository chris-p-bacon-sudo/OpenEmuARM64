## What's New in 1.3.0

- Added cheat code search, browsing, and a Browse Online Cheats window backed by the Libretro Cheat Database, with per-code status feedback, personal notes, and duplicate cleanup (thanks @leocck, #687, #715)
- Added RetroAchievements support and cheat support for MAME, Stella, Atari Lynx, Neo Geo Pocket, Nintendo DS, PC Engine/TurboGrafx-16, PC Engine CD/TurboGrafx-CD, PC-FX, Saturn, and SG-1000 (thanks @leocck, #687)
- Added a preference to hide the RetroAchievements hardcore-mode shield icon without turning off other HUD notifications (thanks @KriTaeCotus, #698)

## Bug Fixes

- Fixed a bug where core plugins could silently fail to load (and crash the emulation helper) after their update-feed address was migrated on launch
- Fixed RetroAchievements sign-in rejecting valid usernames and passwords in Preferences
- Fixed slow library window opening and laggy scrolling on large game collections
- Fixed overlapping labels in the Controls preferences panel
- Fixed the Atari Jaguar core rendering games in portrait instead of landscape (thanks @CamberwelK, #703)
- Fixed the failed-import alert running off screen when a scan reports many failures (thanks @lotech, #627)
- Replaced the deprecated search field in the library toolbar with the standard macOS one

## Under the Hood

- Corrected LICENSE.md to accurately reflect the BSD-3-Clause status of inherited code
- Updated bundled Dolphin, DeSmuME, GenesisPlus, mGBA, Mednafen, and Nestopia cores
