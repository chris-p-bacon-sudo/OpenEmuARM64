# RetroArch core support removal — migration behavior

Reference for what happens on a user's machine when they upgrade into the release
that removed RetroArch core support (1.3.1), and what to tell someone who reports
a problem related to it.

Background on why the feature was removed is in the pull request; this file covers
only the upgrade behavior and its edge cases.

## What happens on first launch after upgrading

`AppDelegate.removeOrphanedRetroArchPlugins()` runs once per launch, before any
plugin enumeration:

1. Walks `~/Library/Application Support/OpenEmu/Cores/` and deletes every bundle
   that either is named `*-RetroArch.oecoreplugin` **or** whose `Info.plist` names
   `OEGameCoreClass = OELibretroCoreTranslator` or carries an `OELibretroCorePath`
   key. Two signals, because early builds did not all use the filename convention,
   and the plist is what actually predicts a bundle that can no longer load.
2. Clears any `defaultCore.<systemID>` preference whose value points at a bundle it
   just removed, ends in `-RetroArch`, or begins with the legacy `retroarch.` form.
   The system then falls back to its native core.
3. Records what it did in `~/Library/Logs/OpenEmu/core-inventory.txt` under
   `--- Orphaned RetroArch plugin cleanup ---`, and logs one line per removal.

It is not gated on a "already migrated" flag. After the first run it is a single
directory listing that matches nothing, which also means a restored backup or a
downgrade/upgrade round trip gets cleaned up too.

**Ordering matters.** The call lives in `AppDelegate.init`, immediately before
`OECorePlugin.registerClass()`. That call enumerates the Cores folder and caches
the result for the rest of the launch, so a stub deleted after it would stay in the
in-memory plugin list — removed cores would still appear under "Play With…" and
would try to load a principal class the app no longer contains. Do not move this
call later in the launch sequence.

The plan is to keep this migration for a few releases, then delete it.

## Save states — the one thing that does not migrate

A save state is a snapshot of an emulator's internal memory, so it is only valid in
the core that wrote it. There is no way to convert one between cores. Save states
written by a RetroArch core therefore cannot be restored after the upgrade.

What a user sees when they pick one:

| Situation | Behavior |
|---|---|
| System has a native core (Genesis, N64, PSX, …) | `OECorePlugin.corePlugin(bundleIdentifier:)` returns nil, `setUpDocument` falls back to `core(forSystem:)`, and the game opens on the native core and starts from the beginning instead of restoring. |
| Commodore 64 (no core at all) | `core(forSystem:)` throws `noCore`, and OpenEmu reports that no core is available. |

Neither case crashes — the lookup is a failable optional, not a force unwrap.

Two things worth stating plainly to anyone who reports this:

- **Battery saves are not affected.** In-game saves (the ones the game itself
  writes to its cartridge or memory card) are core-independent and survive. Only
  save states are lost.
- **Auto save states are not loaded automatically, and are easy to miss.** A game's
  right-click → "Play Save State" menu is built from `OEDBRom.normalSaveStates`,
  which filters out every state whose name begins with `OESpecialState_`. Auto save
  states are therefore *never* listed there — a game whose only state is the auto
  save shows "No Save States available", and always has, independent of this change.
  They are visible in the **Save States** section of the library sidebar (controlled
  by the `showsAutoSaves` preference, on by default). So reaching an affected auto
  state takes deliberate action; launching a game normally never hits it.

Affected states can be identified by reading the `Core Identifier` key:

```bash
find ~/Library/Application\ Support/OpenEmu/Save\ States \
  -name Info.plist -path '*.oesavestate*' -exec grep -l -i retroarch {} \;
```

They can be deleted from the **Save States** section of the library sidebar (not
from the game's right-click menu, which hides auto saves). Nothing deletes them
automatically — the cleanup only touches core plugin bundles and preferences, never
user data. `AppDelegate.removeIncompatibleSaveStates()` does prune states for
deprecated cores, but its list is explicit and contains no RetroArch identifiers,
so it leaves these alone.

To exercise this path, open the Save States section of the library and pick an
affected state there.

## Features that share the name and were NOT removed

These come up because all three read as "Libretro" to a user. A report that one of
them broke is not a migration problem:

- **Libretro cheat database** — `LibretroCheatProvider.swift`, shipped in #715.
- **Libretro box art / thumbnails** — `LibretroThumbnailsClient.swift`.
- **`OERetroAchievementsBridge`** — a different "bridge" entirely; RetroAchievements.
