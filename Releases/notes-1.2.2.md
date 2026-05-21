## What's New in 1.2.2

- Sonic & Knuckles lock-on now works on Genesis — launch Sonic 1, 2, or 3 through Sonic & Knuckles for the combined cartridge experience (thanks @ketsuban, #457)

## Bug Fixes

- Fixed three crashes reported by users in production (import failure, session teardown, and a Core Data threading issue)
- The game window title now shows which core is running the current game (thanks @gingerbeardman, #496)
- Loading a save state from a different region or revision now prompts you to confirm instead of silently failing (thanks @tao-bioinfo, #564)
- Dreamcast GDI disc images with unusual track layouts now import correctly (thanks @CamberwelK, #501)
- Improved 3DO accuracy: MADAM matrix math now uses integer arithmetic, matching real hardware behavior (thanks @CamberwelK, #479)
