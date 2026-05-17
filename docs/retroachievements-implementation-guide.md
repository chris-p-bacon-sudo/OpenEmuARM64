# RetroAchievements (rc_client) Implementation Guide

This guide captures the correct pattern for integrating rcheevos `rc_client` into an OpenEmu-Silicon core, along with the specific bugs we've hit in production. Read this before starting a new integration or reviewing an existing one.

The canonical reference implementations are:
- **Mednafen** — `Mednafen/MednafenGameCore.mm` (multi-system: PSX, PCE, Lynx, NGP)
- **Mupen64Plus** — `Mupen64Plus/MupenGameCore.m` (N64)

Primary upstream references:
- [`rc_client` integration guide](https://github.com/RetroAchievements/rcheevos/wiki/rc_client-integration) — runtime integration, event handling, hardcore behavior, save-state progress, media change, and transport expectations.
- [RetroAchievements API docs](https://api-docs.retroachievements.org/) — public read API for profile/game/community data. Do not use the public API in place of `rc_client` for runtime login, game sessions, unlocks, leaderboards, or rich presence.

Related repo-local docs:
- `docs/retroachievements-hardcore-p0-audit.md` — native hardcore enforcement audit for #438.
- `docs/retroachievements-p1-verification.md` — verification plan and submission-evidence checklist mapped to the upstream `rc_client` guide.

---

## Required call sequence during `loadFileAtPath:`

```objc
_rcClient = rc_client_create(my_rc_read_memory, oeRetroAchievementsServerCall);
rc_client_set_userdata(_rcClient, (__bridge void *)self);
rc_client_set_event_handler(_rcClient, my_rc_event_handler);
rc_client_set_hardcore_enabled(_rcClient, 0);
rc_client_set_allow_background_memory_reads(_rcClient, 0);  // ← REQUIRED. See pitfall #1.
rc_client_enable_logging(_rcClient, RC_CLIENT_LOG_LEVEL_WARN, my_rc_log);
```

Then set up the token observer and call `rc_client_begin_login_with_token()` when credentials arrive.

---

## Frame loop

Call `rc_client_do_frame()` once per emulated frame, inside whatever method drives emulation (typically `executeFrame` or `videoInterrupt`):

```objc
if (_rcClient) {
    rc_client_do_frame(_rcClient);
}
```

---

## Lifecycle hooks

| Event | Call |
|---|---|
| Game loading | `rc_client_begin_identify_and_load_game()` |
| Save state load | `rc_client_reset()` today; long term, deserialize RA progress from the save state (see below) |
| Emulation reset | `rc_client_reset()` |
| Stop / dealloc | `rc_client_unload_game()` then `rc_client_destroy()` |
| Disc / media change | `rc_client_begin_change_media()` for systems that can swap discs/disks |

If `rc_client_set_hardcore_enabled(_rcClient, 1)` is called while a game is loaded, rcheevos may raise `RC_CLIENT_EVENT_RESET`. The emulator must reset the game and then call `rc_client_reset()` before achievement processing resumes. Do not silently drop this event.

---

## Transport requirements

All native RA cores must use the shared `oeRetroAchievementsServerCall` transport so traffic identifies as OpenEmu-Silicon instead of another emulator.

Transport requirements from the upstream `rc_client` guide:

- Always send a `User-Agent` in this shape: `<product>/<product-version> (<system-information>) <extensions>`.
- Include `rc_client_get_user_agent_clause()` in the extensions so the server can see the rcheevos version.
- The product/version must be numeric enough for RA to parse. If RA cannot parse or recognize the client version, hardcore unlocks may be demoted to softcore server-side.
- For transient client/network failures, pass `RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR` so rcheevos can queue and retry non-client-initiated updates such as unlocks.
- Use `RC_API_SERVER_RESPONSE_CLIENT_ERROR` only for errors that should not be retried.

---

## Public API vs `rc_client`

The public RetroAchievements API uses a user's **web API key**, not the `rc_client` login token. It is useful for optional out-of-game surfaces such as profile stats, game metadata, hash/debug tools, ticket/community workflows, or richer library views.

Do **not** use the public API for runtime features that `rc_client` already owns:

- login/session runtime
- game identification and loading during play
- achievement unlock submission
- leaderboard submission
- rich presence updates
- retry/offline queue behavior

Runtime behavior should flow through `rc_client` so hashing, server payloads, hardcore mode, retry semantics, leaderboards, and rich presence stay aligned with RA's emulator integration contract.

---

## Writing rc_read_memory correctly

The function signature rcheevos expects:

```c
static uint32_t my_rc_read_memory(uint32_t address, uint8_t *buffer,
                                  uint32_t num_bytes, rc_client_t *client)
{
    uint8_t *ram = /* pointer to emulated RAM */;
    size_t   sz  = /* size of that RAM region */;
    if (!ram || sz == 0) { return 0; }
    uint32_t end      = address + num_bytes;
    if (end > (uint32_t)sz) { end = (uint32_t)sz; }
    uint32_t readable = end - address;
    memcpy(buffer, ram + address, readable);
    return readable;
}
```

**Return value:** number of bytes actually read. Return 0 if the pointer is null or the region is empty. Return a partial count if the request extends past the end of RAM.

### Pitfall #2 — byte-swapping (N64-specific, do not copy to other systems)

The original Mupen64Plus implementation applied `buffer[i] = ram[addr ^ 3]` — an N64 big-endian byte-swap — to every byte. This was wrong.

Achievement conditions for N64 are authored against **raw little-endian host byte addresses**, matching the layout RetroArch/mupen64plus-next exposes via `retro_get_memory_data`. Mupen stores RDRAM as host-native 32-bit words, which is already in that layout. No swap is needed.

The fix is `memcpy` with no address manipulation, as shown above.

**Rule:** only apply a byte-swap if the achievement set for that system was authored against byte-swapped addresses, which is rare and will be documented explicitly by the rcheevos team. When in doubt, match what RetroArch's equivalent core does.

---

## Known pitfalls

### Pitfall #1 — Missing `rc_client_set_allow_background_memory_reads(_rcClient, 0)`

**Symptoms:** Achievements never fire. No errors in the log. The game loads and runs fine.

**Root cause:** By default, rcheevos validates achievement memrefs as soon as the game is identified — on the HTTP callback thread, before the emulator core has finished starting up. At that point, the emulated RAM pointer is null or zero-filled. Every address validates as invalid and rcheevos silently deactivates all achievements before the first frame.

**Fix:** Call `rc_client_set_allow_background_memory_reads(_rcClient, 0)` during `rc_client` initialization. This defers address validation to the `rc_client_do_frame()` call in the frame loop, where emulated RAM is guaranteed live.

**Affected cores fixed:** Mupen64Plus (PR #345), Mednafen (PR #346), and the remaining native RA cores in the #438 compliance follow-up (Nestopia, FCEU, BSNES, SNES9x, Gambatte, GenesisPlus, and mGBA).

**Every new integration must include this call.** It is easy to omit because achievements appear to load (no error) and the game runs normally — the failure is silent.

### Pitfall #2 — See byte-swapping section above.

### Pitfall #3 — PSX scratchpad not served (achievments silently deactivated)

**Symptoms:** `N-1/N achievements active` at load (one short). Any achievement that reads scratchpad RAM is silently deactivated.

**Root cause:** rcheevos maps PSX scratchpad (CPU address 0x1F800000, 1 KB) to the achievement address range 0x200000–0x2003FF. If `rc_read_memory` returns early at `address >= 0x200000`, every memref in that range fails validation and its achievement is deactivated.

**Fix:** In the PSX branch of `rc_read_memory`, serve addresses 0x200000–0x2003FF from `MDFN_IEN_PSX::CPU->GetScratchRAMData()`. Guard with a null check on `CPU` in case a read arrives before the core is fully started.

**Fixed in:** Mednafen (PR #347).

### Pitfall #4 — Module name and system identifier diverge for PCE-CD

**Symptoms:** All PCE-CD achievements broken. rcheevos identifies the wrong game (or none). Memory reads use the wrong layout.

**Root cause:** Mednafen uses the same module name (`"pce"`) for both PC Engine HuCard and PC Engine CD-ROM². The `_mednafenCoreModule` ivar is therefore `"pce"` for both. Any code that checks `_mednafenCoreModule == "pcecd"` to detect PCE-CD will never match, so console detection falls through to `RC_CONSOLE_PC_ENGINE` and the extended CD-ROM memory map is never served.

**Fix:** Use `self.systemIdentifier` (which correctly returns `"openemu.system.pcecd"` for disc-based PCE games) to detect PCE-CD. Store the result in a dedicated `_isSystemPCECD` BOOL ivar at load time, and use it in both console detection and `rc_read_memory` dispatch. The PCE-CD console check must appear **before** the plain PCE check in the detection chain.

**Fixed in:** Mednafen (PR #347).

---

## Hardcore mode requirements

OpenEmu-Silicon supports a user-facing hardcore preference, but RA's upstream recommendation is that hardcore be enabled by default for opted-in RA users. If the user starts in softcore and switches to hardcore mid-session, reset the game before allowing hardcore unlocks.

Hardcore-restricted features include:

- loading save states
- rewind
- slowdown / frame advance
- cheats or gameplay-modifying hacks
- debugger/memory inspection windows
- input playback

The upstream `rc_client` integration guide says fast-forward is allowed in hardcore. OpenEmu-Silicon may choose to be stricter, but if fast-forward remains blocked, keep that as an explicit product/compliance decision rather than an accidental interpretation of RA's baseline rules.

### Pause and idle behavior

When emulation is paused, stop calling `rc_client_do_frame()` and call `rc_client_idle()` at least once per second instead. This keeps routine server communication alive while gameplay is stopped.

In hardcore mode, call `rc_client_can_pause()` immediately before honoring a user pause request. If it returns false, do not pause and show a short user-facing message. This prevents pause-spam from becoming a slow-motion workaround.

### Automatically disabling hardcore when no RA processing is required

The upstream `rc_client` guide recommends optionally disabling hardcore for games that have no RA functionality by checking `rc_client_is_processing_required()`. OpenEmu-Silicon does **not** currently do this per game. Instead, enforcement is scoped to signed-in sessions whose selected core/system advertises RA support, and #438 tracks clear unrecognized/no-set feedback for games without a valid RA set/hash.

If we later auto-disable hardcore per game, re-enable it when unloading the game or before loading the next game.

### Save-state progress

Blocking save-state loads in hardcore is required, but softcore still needs correct RA runtime progress when save states are used. When save states are written, include the RA progress blob:

- `rc_client_progress_size()`
- `rc_client_serialize_progress()` or `rc_client_serialize_progress_sized()`

When save states are loaded, restore the blob with:

- `rc_client_deserialize_progress()` or `rc_client_deserialize_progress_sized()`

If a save state does not contain RA progress data, call `rc_client_deserialize_progress(_rcClient, NULL)` to reset runtime progress cleanly.

---

## Checklist for a new rc_client integration

- [ ] `rc_client_set_allow_background_memory_reads(_rcClient, 0)` called before logging setup
- [ ] `rc_client_do_frame()` called every emulated frame, including frames not displayed during frame skip or performance catch-up
- [ ] `rc_client_idle()` called while emulation is paused and `do_frame` is not running
- [ ] `rc_client_can_pause()` checked before allowing a user pause in hardcore mode
- [ ] `rc_client_reset()` called on emulation reset and after a hardcore reset request
- [ ] `RC_CLIENT_EVENT_RESET` handled instead of silently ignored
- [ ] Save states serialize/deserialize RA progress for softcore correctness, or explicitly document why the core does not support save-state progress yet
- [ ] Disc/media changes call `rc_client_begin_change_media()` where applicable
- [ ] `rc_client_unload_game()` + `rc_client_destroy()` called on stop/dealloc
- [ ] `rc_read_memory` returns 0 (not garbage) when RAM pointer is null
- [ ] `rc_read_memory` returns partial count when request exceeds RAM size
- [ ] No byte-swap unless the system's achievement set was explicitly authored against byte-swapped addresses
- [ ] `RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED` posts `OEAchievementUnlockedNotification`
- [ ] Gameplay UI events are bridged: challenge indicators, progress, leaderboard start/fail/submit/trackers/scoreboards, completion/mastery, server error, disconnected, reconnected
- [ ] Shared transport sends OpenEmu's User-Agent and uses retryable client errors for transient network failures
- [ ] Tested with a real game and achievement that fires in RetroArch — confirm it fires in OE too
