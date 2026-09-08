## What's New in 1.3.1

- Removed RetroArch core support. OpenEmu no longer loads libretro `.dylib` cores from a RetroArch installation, and the RetroArch section is gone from Preferences → Cores. Every system except Commodore 64 already had a native core, and native cores are faster, better supported, and the only ones that get RetroAchievements, cheats, and save-state fixes.

  **The Libretro cheat database and libretro box-art lookups are not affected** and continue to work exactly as before. Only the "run a RetroArch core" feature was removed.

  Any RetroArch cores you installed are removed automatically the first time you launch 1.3.1, and systems that were set to use one fall back to their native core. No action is needed.

- Commodore 64 no longer has a core. It was the only system that depended on RetroArch, and that path was already broken. The system, its artwork, and its controller settings remain; a native VICE core is planned ([#546](https://github.com/OpenEmu-Silicon/OpenEmu-Silicon/issues/546)).

## Known Issues

- **Save states made with a RetroArch core will not restore.** A save state only works in the core that wrote it, so states created by a RetroArch core cannot be loaded by the native core that replaces it. Selecting one asks whether you want to switch to the core that made it. Choosing **Cancel** starts the game on the native core from the beginning; choosing **Change Core** reports that the core cannot be found, because it no longer exists. Either way the state cannot be restored. Nothing crashes, and battery saves (in-game saves) are unaffected — only save states. Affected states can be deleted from the Save States section of the library.

## Bug Fixes

- Fixed C64 keyboard input crashing games ([#390](https://github.com/OpenEmu-Silicon/OpenEmu-Silicon/issues/390)) and C64 50/60Hz switching ([#462](https://github.com/OpenEmu-Silicon/OpenEmu-Silicon/issues/462)) by removing the RetroArch path both depended on. Both are superseded by the native VICE port in [#546](https://github.com/OpenEmu-Silicon/OpenEmu-Silicon/issues/546).

## Under the Hood

- Removed the libretro translator, the bundled bridge target, and the vendored libretro ABI header (about 4,500 lines)
- `OELibretroCoreTranslator.h` is no longer part of the OpenEmu SDK's public headers
