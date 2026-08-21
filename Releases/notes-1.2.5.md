## What's New in 1.2.5

- Added Cheat Search, a new tool for finding and applying game cheats (thanks @leocck, #654)
- Added bulk artwork import from a folder (thanks @bahgee, #634)

## Bug Fixes

- Fixed controllers that present as both a gamepad and a keyboard being misclassified as keyboards (thanks @jeffscottward, #642)
- Fixed a crash when connecting a controller with no readable controls
- Fixed battery-backed save RAM not persisting for RetroArch-bridged cores
- Fixed Sonic & Knuckles lock-on ROMs not being recognized as a Genesis BIOS file (thanks @ketsuban, #636)
- Added an in-app way to reset a stale Input Monitoring permission (thanks @zsummi, #628)
- Fixed RetroAchievements login failing when the password had leading/trailing spaces (thanks @Double0Beavis, #644)
- Fixed RetroAchievements unlock notifications not showing the correct badge image
- Embedded the Jaguar, MSX, Pokémon mini, and Supervision system plugins directly in the app bundle (thanks @petewr, #639)
- Stopped forcing MMU emulation on for every Dolphin (GameCube/Wii) game
- Fixed the Cloud Sync status label shifting away from its status dot
- Reduced clutter in the RetroAchievements corner overlay (thanks @tao-bioinfo, #638)
- Restored Atari800 video output in Release builds (thanks @CamberwelK, #432)
- Fixed a GameCube first-boot crash by initializing Dolphin input before boot
- Restored the Dolphin core build by vendoring a missing external dependency

## Under the Hood

- Updated the bundled Dolphin core to a newer upstream version
