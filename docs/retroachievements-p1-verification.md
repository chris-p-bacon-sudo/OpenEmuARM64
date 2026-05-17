# RetroAchievements P1 Verification Plan

This document is the manual verification and submission-evidence checklist for issue #438. It is based on the upstream [`rc_client` integration guide](https://github.com/RetroAchievements/rcheevos/wiki/rc_client-integration) and the current OpenEmu-Silicon native `rc_client` implementation.

Scope: native RetroAchievements cores only. Libretro/RetroArch cores are tracked separately in #360 and the libretro architecture docs.

## Native RA cores in scope

- Nestopia
- FCEU
- BSNES
- SNES9x
- Gambatte
- GenesisPlus
- mGBA
- Mupen64Plus
- Mednafen

## Source checklist from upstream `rc_client` guide

| Upstream area | Current status | Evidence / next verification |
| --- | --- | --- |
| Create/destroy `rc_client_t` | Implemented | All native RA cores create `rc_client_t` with `oeRetroAchievementsServerCall`, set userdata, register event handler, and unload/destroy the client on stop/dealloc. |
| User-Agent | Implemented; RA approval pending | Shared transport sends `OpenEmu-Silicon/<version> (macOS <version>) <rcheevos-clause>`. RA still needs to recognize/approve the client for hardcore credit. |
| Login with token | Implemented; failure UI in PR #521 | Cores use `rc_client_begin_login_with_token()`. PR #521 surfaces login failure to the host UI. |
| Start game session | Implemented; failure UI in PR #521 | Cores use `rc_client_begin_identify_and_load_game()`. PR #521 surfaces unrecognized/no-set hash failures. |
| Game boot placard | Implemented | PR #514 added recognized-game boot placard with title, mode, achievement count, and point summary. PR #521 adds failure placards. |
| Achievement list | Implemented; polish remaining | PR #514 added native Achievements window. Static measured progress is shown when present. Active challenge/progress state in the window remains a #438 follow-up. |
| `rc_client_do_frame()` | Implemented | All native RA cores call `rc_client_do_frame()` in their emulation frame loop. Needs representative runtime verification per core. |
| Achievement unlock notification | Implemented | `RC_CLIENT_EVENT_ACHIEVEMENT_TRIGGERED` posts in-app unlock banner and macOS notification with unlock sound. |
| Leaderboard events | Implemented; verification needed | PR #519 bridges start/fail/submit/scoreboard and tracker show/update/hide to native toasts/chips. Needs representative game verification. |
| Challenge indicators | Implemented; verification needed | PR #519 bridges challenge show/hide to native chips. Manual Nestopia/SMB verification already confirmed show/hide behavior once. |
| Progress indicators | Implemented; verification needed | PR #519 bridges measured progress show/update/hide to native chips. Needs representative measured-achievement verification. |
| Completion/mastery notifications | Implemented; verification needed | PR #519 bridges game/subset completion to native toasts. Needs manual evidence. |
| Reset handling | Implemented | `RC_CLIENT_EVENT_RESET` is bridged and host resets emulation; cores call `rc_client_reset()` on emulator reset/load-state paths. |
| Save-state progress serialization | Gap / P2 | Hardcore load-state blocking is implemented. Softcore RA progress is still reset on load via `rc_client_reset()`; serialize/deserialize is not implemented. |
| Multiple media changes | Gap / follow-up | No current native-core call to `rc_client_begin_change_media()` was found. Needs design for disc/disk swap systems, especially Mednafen PSX/PCE-CD/Saturn. |
| Hardcore default / mode switching | Implemented | User-facing hardcore preference defaults on for signed-in RA users; softcore→hardcore reset path is implemented and documented in P0 audit. |
| Disable hardcore when no RA processing required | Not implemented / product decision needed | Upstream recommends optionally disabling hardcore for games with no RA functionality via `rc_client_is_processing_required()`. OpenEmu currently scopes enforcement by core/system support and token, not by per-game processing state. |
| Pause / idle | Implemented; verification needed | `rc_client_idle()` is called once per second while the helper is paused, and user-initiated hardcore pause attempts call `rc_client_can_pause()` before pausing. Needs manual verification with a real RA session. |
| Server errors | Implemented; verification needed | PR #519 surfaces `RC_CLIENT_EVENT_SERVER_ERROR`, disconnected, and reconnected events. Transport marks transient network failures retryable. |
| Offline retry queue | Implementation delegated to `rc_client`; verification needed | Shared transport uses `RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR` for transient client/network failures, enabling rcheevos retry behavior. Must verify unlock queue/sync/purge behavior manually. |
| Rich Presence | Expected via `rc_client_do_frame()`; verification needed | Upstream says `rc_client_do_frame()` sends rich presence updates after initial delay and periodically thereafter. No OpenEmu toggle exists to disable it. Must verify on RA profile/API. |

## Verification matrix

Use real RA credentials and games known to have active achievements, rich presence, measured achievements, challenges, and leaderboards. Build and install the specific core before testing; OpenEmu loads installed core plugins from `~/Library/Application Support/OpenEmu/Cores/`.

Record manual results in [`retroachievements-p1-evidence-log.md`](retroachievements-p1-evidence-log.md) so issue #438 can be updated with reviewer-ready evidence instead of scattered notes.

### Common setup

```bash
cd ~/Documents/Cursor/Open\ Emu

# Build host app
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -50

# Build/install a core before manual testing. Example:
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme 'OpenEmu + Nestopia' \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30

./Scripts/install-core.sh --release Nestopia
./Scripts/verify-core-installed.sh --release Nestopia
./Scripts/launch-debug.sh
```

### Recognition / placard / Achievements window

| Test | Expected result | Evidence to capture |
| --- | --- | --- |
| Known RA game/hash on supported native core | Boot placard appears with game title, hardcore/softcore mode, achievement count, and points. Achievements window populates. | Screenshot/video of boot placard and Achievements window. |
| Unknown/no-set hash on supported native core | Failure placard and Achievements window clearly say no achievement set was found for this game/hash. | Screenshot after PR #521 lands. |
| Expired/invalid token | Failure placard/window reports sign-in failure instead of waiting forever. | Screenshot; note whether Preferences still shows signed-in state. |

### Rich Presence

Upstream behavior: `rc_client_do_frame()` sends rich presence after the first update delay, then periodically while the session is active. `rc_client_idle()` should maintain routine communication while paused.

| Test | Expected result | Status |
| --- | --- | --- |
| Launch known RA game with rich presence and wait at least 30 seconds while playing | RA profile/activity shows current game/rich presence for OpenEmu-Silicon session. | Not yet verified. |
| Continue playing for several minutes | Rich presence continues updating periodically. | Not yet verified. |
| Hardcore mode enabled | No OpenEmu UI exists to disable rich presence; behavior should remain active. | Not yet verified. |
| Pause emulation for >60 seconds | `rc_client_idle()` should keep routine server communication alive while paused. | Not yet verified after implementation. |

### Leaderboards

| Test | Expected result | Status |
| --- | --- | --- |
| Start a known leaderboard attempt | Native leaderboard started toast appears. | Not yet verified after PR #519 beyond Nestopia smoke test. |
| During attempt | Tracker chip appears and updates without jitter or stale values. | Nestopia/SMB smoke test confirmed tracker appears. Needs broader evidence. |
| Fail attempt | Tracker clears and failure toast appears. | Not yet fully verified. |
| Submit attempt | Tracker clears and submitted/result toast appears. | Nestopia/SMB smoke test confirmed result clears tracker. Needs screenshot/video. |
| Hardcore mode enabled | No OpenEmu UI exists to disable leaderboards; events should remain active. | Not yet verified. |

### Challenge / progress / mastery UI

| Test | Expected result | Status |
| --- | --- | --- |
| Trigger challenge indicator | Challenge chip appears, then hides when condition fails/completes. | Nestopia/SMB smoke test confirmed show/hide once. Needs evidence. |
| Trigger measured achievement progress | Progress chip appears/updates/hides with rcheevos measured progress text. | Not yet verified. |
| Complete/master game or subset | Completion/mastery toast appears with correct softcore/hardcore verb. | Not yet verified. |

### Offline / reconnect / server errors

Upstream behavior: transient non-client-initiated request failures can be queued and retried if the server callback reports `RC_API_SERVER_RESPONSE_RETRYABLE_CLIENT_ERROR`. OpenEmu's shared transport now does this for `NSURLSession` errors, missing data, and non-HTTP responses.

| Test | Expected result | Status |
| --- | --- | --- |
| Disconnect network during active RA session | Offline/disconnected toast appears. | UI implemented; not yet verified. |
| Unlock achievement while offline | rcheevos queues the unlock for retry rather than losing it. | Not yet verified. |
| Reconnect network before closing game | Reconnected/sync toast appears and unlock appears on RA profile. | Not yet verified. |
| Close game while offline after queued unlock | Queue/cache should be session-scoped and purged on close if required by RA compliance. Need confirm actual rcheevos behavior. | Not yet verified; potential reviewer question. |
| Force server error response | Server-error toast appears with API/error context; non-retryable server errors are not silently queued. | Not yet verified. |

### Pause / idle verification

The upstream guide explicitly calls for:

- `rc_client_idle()` while emulation is paused and `rc_client_do_frame()` is not running.
- `rc_client_can_pause()` immediately before honoring pause in hardcore mode.

Current status: implemented for native RA cores. The helper starts a once-per-second RA idle timer while paused and stops it on resume/stop. User-initiated pause attempts in hardcore ask the active core whether pause is allowed before changing host pause state; denied pauses show a short in-game message.

Manual verification still needed:

| Test | Expected result | Status |
| --- | --- | --- |
| Softcore pause | Pause/resume still works normally. | Not yet verified. |
| Hardcore pause after enough gameplay frames | Pause succeeds. | Not yet verified. |
| Hardcore pause spam | Some pause attempts are denied with a user-facing message. | Not yet verified. |
| Pause for >60 seconds in an RA session | Routine server communication/rich presence remains active. | Not yet verified. |

### Save-state progress follow-up

The upstream guide strongly recommends serializing RA runtime progress into save states:

- `rc_client_progress_size()`
- `rc_client_serialize_progress_sized()`
- `rc_client_deserialize_progress_sized()`

Current status: documented P2 gap. Hardcore load-state blocking is implemented; softcore save-state correctness still relies on `rc_client_reset()` after loads.

### Media-change follow-up

The upstream guide calls for `rc_client_begin_change_media()` when switching discs/disks.

Current status: no native call found. This matters most for Mednafen PSX/PCE-CD/Saturn and any other multi-disc/disk native RA systems. Needs design before implementation because OpenEmu's disc-change pathways differ by core/system.

## Submission evidence to gather

Record these results in [`retroachievements-p1-evidence-log.md`](retroachievements-p1-evidence-log.md).

- Boot placard screenshot for recognized game.
- Achievements window screenshot showing locked/unlocked achievements, points, badges, and progress where available.
- Unrecognized/no-set hash screenshot after PR #521.
- Challenge/progress/leaderboard tracker screenshots or short video.
- Unlock banner with sound confirmed.
- Offline/reconnect test notes, including whether queued unlock synced or was purged on close.
- User-Agent sample from transport logs or packet capture:
  - `OpenEmu-Silicon/<version> (macOS <version>) rcheevos/<version>`
- Explicit RA-side approval question: what client registration step is required so OpenEmu-Silicon is no longer treated as an unknown emulator for hardcore credit?

## Follow-up implementation candidates

1. Rich Presence/leaderboard/offline manual verification evidence pass.
2. Save-state progress serialization for softcore correctness.
3. Media-change handling for multi-disc/disk systems.
4. Achievements window live-state polish for active challenge/progress state.
