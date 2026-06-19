## What's New in 1.2.4

- **RetroAchievements hardcore is now fully supported.** OpenEmu-Silicon now reports its version correctly to RetroAchievements — it previously sent "unknown," which RetroAchievements rejected and which blocked hardcore unlocks. The active core also identifies itself in the request. Fast-forward is now allowed during hardcore sessions, while rewind, slow-motion, and frame-step stay disabled as RetroAchievements requires.
- The import dialog now accepts more Atari 8-bit formats — `.atx`, `.car`, `.cas`, `.dcm`, and `.pro` (thanks @cwscws for the request, #581).

## Bug Fixes

- **Atari 5200 black screen fixed** — games loaded with audio but no picture on the bundled Atari800 core; video now renders correctly (thanks @CamberwelK for the report and test games, and @alfonsico for confirming the repro, #432).
- **Virtual Boy timing fixed** — games that depend on render-time effects, such as Golf, ran too fast and rendered incorrectly; they now display correctly (thanks @gingerbeardman for the report, the real-hardware reference video, and testing across cores, #411).
- **Nintendo 64 controller crash fixed** — connecting or reconnecting a controller mid-game could crash the emulator (thanks @Ekamekia for the repro details, #330).
- **Add Cheat dialog improved for Nintendo 64** — the dialog now shows the correct code format per system, and N64 codes in unsupported formats are flagged with guidance instead of being silently dropped (thanks @Ekamekia for the repro video and tracking down the code-format source, #293; and @openemugirl for championing cheat support, #589).
- The game library grid now scrolls more smoothly, fixing occasional brief hangs.
- The Settings window no longer stays on top of other windows.
- Game Boy and Game Boy Color preferences are now labeled correctly.

## Thanks

Huge thanks to everyone who reported bugs, shared logs and reproduction steps, tested fixes, and suggested improvements this release: @cwscws, @CamberwelK, @alfonsico, @gingerbeardman, @Ekamekia, and @openemugirl.

And a special thank-you to the **RetroAchievements team** — @LiquifiedSnow and @wescopeland — for reviewing OpenEmu-Silicon for official compliance and approving all supported systems for hardcore mode.
