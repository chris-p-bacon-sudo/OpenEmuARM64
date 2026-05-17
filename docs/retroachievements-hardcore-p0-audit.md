# RetroAchievements Hardcore P0 Audit

This note tracks the P0 hardcore-compliance audit for issue #438. It covers the native RetroAchievements path only. Libretro/RetroArch core behavior is tracked separately because those cores run through the libretro host.

## Scope

Native RA-enabled cores audited:

- Nestopia
- FCEU
- BSNES
- SNES9x
- Gambatte
- GenesisPlus
- mGBA
- Mupen64Plus
- Mednafen

## Enforcement model

Hardcore restrictions are enforced only when all of these are true:

1. The user has enabled the RetroAchievements hardcore preference.
2. A RetroAchievements token is stored.
3. The selected core advertises `OEGameCoreSupportsRetroAchievements` for the active system.

This avoids disabling save states, rewind, cheats, or speed controls for non-RA games or unsupported core/system pairs just because the user is signed in.

## P0 audit results

| Area | Result | Evidence |
| --- | --- | --- |
| Startup hardcore ordering | Pass | `OEGameDocument` pushes the effective hardcore state to the helper before startup save-state restore decisions. |
| Startup resume behavior | Pass | Startup save-state restore routes through `loadState(state:)`, which checks `HardcoreModePolicy.allows(.loadState, hardcoreEnabled:)` before calling the helper. |
| Normal save-state load | Pass | `OEGameDocument.loadState(_:)` shows a user-facing block in hardcore before pausing, and `loadState(state:)` has a second guard. |
| Quick-load | Pass | `quickLoad(_:)` routes through `loadState(_:)` / `loadState(state:)`, so it inherits the same block. |
| Helper load-state path | Pass | `OpenEmuHelperApp.loadStateFromFile(at:)` rejects load requests when helper-side `_hardcoreEnabled` is true. |
| Rewind | Pass | Host, helper, and base `OEGameCore` paths block rewind while hardcore is active. Enabling hardcore also clears any already-active rewind flag. |
| Frame advance | Pass | Host, helper, and base `OEGameCore` paths block frame advance while hardcore is active. Enabling hardcore also clears any pending frame-step flag. |
| Fast-forward / analog speed | Pass | `OEGameCore.fastForward(_:)` and `fastForwardAtSpeed(_:)` return without changing rate when hardcore is active. Enabling hardcore also normalizes active and paused-resume fast-forward state back to 1x. |
| Slow motion | Pass | `OEGameCore.slowMotionAtSpeed(_:)` returns without changing rate when hardcore is active. Enabling hardcore also normalizes active slow-motion state back to 1x. |
| Cheats | Pass | Saved cheat autoload is skipped in hardcore, document-level cheat actions return early, and helper-side `setCheat` rejects calls in hardcore. |
| Mode switch: softcore → hardcore | Pass | Mid-session switch to enforced hardcore prompts for a full game reset before enabling the helper/core hardcore flag. |
| Mode switch: hardcore → softcore | Pass | Disabling hardcore pushes softcore mode without requiring reset. |
| User-Agent | Pass for native RA path | Native RA HTTP requests are centralized through `oeRetroAchievementsServerCall`, which sends `OpenEmu/<app-version> (macOS <os-version>) <rcheevos-clause>`. |

## User-Agent disclosure

Current native RA traffic does not identify as another emulator. All native RA cores create their `rc_client_t` with the shared OpenEmu transport function:

```objc
rc_client_create(<core>_rc_read_memory, oeRetroAchievementsServerCall)
```

The shared transport builds the HTTP `User-Agent` as:

```text
OpenEmu/<host-version> (macOS <os-version>) <rcheevos user-agent clause>
```

No current native RA core overrides this with a core-specific or upstream-emulator identity.

## Known non-P0 follow-ups

These are still tracked in #438 but are not part of P0 gate closure:

- Gameplay overlays for progress, challenge, leaderboard, mastery, and offline/reconnect events.
- Offline queue verification and visible reconnect/sync UI.
- Save-state hit storage for softcore correctness.
- Libretro RA behavior after the libretro RA path is ready.
