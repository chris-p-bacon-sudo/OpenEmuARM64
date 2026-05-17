# RetroAchievements P1 Evidence Log

This document records manual verification evidence for issue #438 before resubmitting OpenEmu-Silicon for RetroAchievements review.

Use this alongside [`retroachievements-p1-verification.md`](retroachievements-p1-verification.md). That file describes what to test; this file records what was actually tested, with enough detail for reviewers to reproduce or audit the result.

Scope: native RetroAchievements cores only. Libretro/RetroArch cores are tracked separately in #360.

---

## Evidence status summary

| Area | Status | Evidence |
| --- | --- | --- |
| Recognized-game boot placard | Pending fresh capture | Needs screenshot/video from current `main`. |
| Achievements window | Pending fresh capture | Needs screenshot/video from current `main`. |
| Unrecognized/no-set feedback | Pending fresh capture | Needs screenshot from current `main`. |
| Rich Presence works | Pending | Verify on RA profile/activity after 30s+ of play. |
| Rich Presence remains active in hardcore | Static code audit complete; live RA verification pending | No OpenEmu setting/API usage was found that disables Rich Presence. Verify RA profile/activity continues updating in hardcore. |
| Leaderboards work | Pending broader evidence | Prior Nestopia smoke test was noted in #438; capture fresh screenshot/video. |
| Leaderboards cannot be disabled in hardcore | Static code audit complete; live RA verification pending | No OpenEmu setting/API usage was found that disables leaderboard functionality or spectator mode. Verify runtime events in hardcore. |
| Offline unlock queue syncs after reconnect | Pending | Needs controlled offline/reconnect test. |
| Offline queue/cache is session-scoped/purged on close | Pending | Needs controlled close-while-offline test or RA maintainer confirmation. |
| Server error/offline/reconnect UI | Pending fresh capture | UI implemented; capture runtime evidence. |
| Pause/idle softcore behavior after #523 | Pending | Verify pause/resume still works. |
| Pause/idle hardcore behavior after #523 | Pending | Verify `rc_client_can_pause()` behavior and denied-pause toast if reproducible. |
| Pause for 60s+ keeps RA state healthy | Pending | Verify Rich Presence/activity remains healthy during pause. |

---

## Test environment

Fill this in once per verification pass.

| Field | Value |
| --- | --- |
| Date | 2026-05-17 |
| Tester | AI-assisted static/local verification |
| OpenEmu-Silicon commit | `9e701cd3` |
| macOS version | macOS 26.4.1 (25E253) |
| Mac model / chip | Apple M4 Max |
| Build configuration | TBD |
| RetroAchievements username | TBD |
| Hardcore default setting | TBD |
| Network manipulation method | TBD |
| Evidence folder / links | TBD |

Recommended commit command:

```bash
git rev-parse --short HEAD
```

Recommended macOS/chip commands:

```bash
sw_vers
sysctl -n machdep.cpu.brand_string
```

---

## Build and install record

OpenEmu loads installed core plugins from `~/Library/Application Support/OpenEmu/Cores/`. For core-specific tests, build, install, and verify the installed plugin before recording a result.

### Host app

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme OpenEmu \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -50
```

| Date | Commit | Result | Notes |
| --- | --- | --- | --- |
| 2026-05-17 | `9e701cd3` | Pass | `xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build` ended with `** BUILD SUCCEEDED **`. |
| 2026-05-17 | `9e701cd3` | Pass | `xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmuBase -configuration Debug -destination 'platform=macOS,arch=arm64' test` ended with `** TEST SUCCEEDED **`; 39 tests passed, including 22 hardcore-gate tests. |

### Core builds / installs

Example for Nestopia:

```bash
xcodebuild \
  -workspace OpenEmu-metal.xcworkspace \
  -scheme 'OpenEmu + Nestopia' \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build 2>&1 | tail -30

./Scripts/install-core.sh --release Nestopia
./Scripts/verify-core-installed.sh --release Nestopia
```

| Core | Scheme | Configuration | Date | Commit | Install verification | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Nestopia | `OpenEmu + Nestopia` | Release | 2026-05-17 | `9e701cd3` | Pass — `install-core.sh --release Nestopia` and `verify-core-installed.sh --release Nestopia`; md5 `33f139bc26f6247eac62cba91a0fd326` | Ready for first live RA manual verification pass. |
| mGBA | `OpenEmu + mGBA` | Release | TBD | TBD | TBD | Good for cross-core RA sanity check. |
| GenesisPlus | `OpenEmu + GenesisPlus` | Release | TBD | TBD | TBD | Good for measured/progress and leaderboard coverage if using known set. |
| Mednafen | `OpenEmu + Mednafen` | Release | TBD | TBD | TBD | Useful before later media-change follow-up. |

---

## Static/local evidence entries

These checks do not replace live RA profile/gameplay verification, but they document what the current code can prove without credentials, ROMs, or RA server observation.

### 2026-05-17 — Native RA cores — rc_client runtime hooks static audit

- **Commit:** `9e701cd3`
- **Scope:** Nestopia, FCEU, BSNES, SNES9x, Gambatte, GenesisPlus, mGBA, Mupen64Plus, Mednafen
- **Test steps:** searched native RA core source for required `rc_client` runtime hooks.
- **Expected:** every native RA core has per-frame processing, paused idle handling, hardcore pause preflight, background-memory-read disabling, and reset handling.
- **Actual:** all nine native RA cores contain the expected calls.
- **Result:** Pass for static implementation presence; live gameplay behavior still needs verification.

| Core | `rc_client_do_frame` | `rc_client_idle` | `rc_client_can_pause` | `rc_client_set_allow_background_memory_reads` | `rc_client_reset` |
| --- | --- | --- | --- | --- | --- |
| Nestopia | Yes | Yes | Yes | Yes | Yes |
| FCEU | Yes | Yes | Yes | Yes | Yes |
| BSNES | Yes | Yes | Yes | Yes | Yes |
| SNES9x | Yes | Yes | Yes | Yes | Yes |
| Gambatte | Yes | Yes | Yes | Yes | Yes |
| GenesisPlus | Yes | Yes | Yes | Yes | Yes |
| mGBA | Yes | Yes | Yes | Yes | Yes |
| Mupen64Plus | Yes | Yes | Yes | Yes | Yes |
| Mednafen | Yes | Yes | Yes | Yes | Yes |

### 2026-05-17 — OpenEmu app — Rich Presence / leaderboard disable-path static audit

- **Commit:** `9e701cd3`
- **Scope:** OpenEmu app, native RA transport, native RA cores
- **Test steps:** searched for OpenEmu-side settings or code paths that disable Rich Presence, disable leaderboards, enable rcheevos spectator mode, or toggle rcheevos leaderboard submission.
- **Expected:** no user-facing or hidden OpenEmu setting should disable Rich Presence or leaderboard functionality in hardcore. Overlay popups may be hideable later only if runtime functionality remains active.
- **Actual:** no OpenEmu usage was found for `rc_client_set_spectator_mode_enabled`; no OpenEmu Rich Presence toggle was found; no OpenEmu leaderboard-disable toggle was found. Leaderboard rcheevos events are bridged through `OERetroAchievementsTransport.m` and displayed by `OEGameDocument.swift` / `GameViewController.swift`.
- **Result:** Pass for static no-disable-path audit; live RA profile/activity and hardcore leaderboard behavior still need verification.

## Evidence entries

Use one entry per tested behavior. Keep raw notes factual: what was tested, what happened, and where the evidence lives.

### Entry template

```markdown
### YYYY-MM-DD — [Core] — [Game] — [Behavior]

- **Commit:** `TBD`
- **Core / scheme:** TBD
- **Installed plugin verified:** Yes/No — command/result
- **System:** TBD
- **Game:** TBD
- **Region / hash:** TBD
- **RA mode:** Softcore/Hardcore
- **RA username:** TBD
- **Test steps:**
  1. TBD
- **Expected:** TBD
- **Actual:** TBD
- **Result:** Pass/Fail/Inconclusive
- **Evidence:** Screenshot/video/log path or link
- **Follow-up:** TBD
```

---

## Recognition / Achievements window evidence

### Known RA game/hash

- **Status:** Pending
- **Need:** boot placard screenshot/video and Achievements window screenshot from current `main`.
- **Expected:** placard shows title, recognized state, hardcore/softcore mode, achievement count, and points; Achievements window shows locked/unlocked achievements, title, description, points, badges/art, and set selector where applicable.

### Unknown/no-set hash

- **Status:** Pending
- **Need:** failure placard and Achievements window empty-state screenshot.
- **Expected:** user-facing copy clearly says no achievement set was found for this game/hash, distinct from sign-in failure and unsupported core.

### Expired/invalid token

- **Status:** Pending
- **Need:** sign-in failure placard/window screenshot if practical.
- **Expected:** failure is visible instead of waiting forever; user is directed back to Preferences → Achievements.

---

## Rich Presence evidence

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Launch known RA game and wait at least 30 seconds while playing | Pending | TBD | Verify on RA profile/activity. |
| Continue playing for several minutes | Pending | TBD | Confirm periodic update continues. |
| Hardcore mode enabled | Pending | TBD | No OpenEmu UI exists to disable Rich Presence; verify activity remains active. |
| Pause emulation for >60 seconds | Pending | TBD | After #523, `rc_client_idle()` should keep routine communication alive. |

---

## Leaderboard evidence

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Start known leaderboard attempt | Pending | TBD | Started toast should appear. |
| Continue attempt | Pending | TBD | Tracker chip should appear/update. |
| Fail attempt | Pending | TBD | Tracker clears and failure toast appears. |
| Submit attempt | Pending | TBD | Tracker clears and submit/result toast appears. |
| Hardcore mode enabled | Pending | TBD | No OpenEmu UI exists to disable leaderboards; functionality should remain active. |

---

## Challenge / progress / mastery evidence

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Trigger challenge indicator | Pending | TBD | Prior Nestopia smoke test noted in #438; capture current evidence. |
| Trigger measured achievement progress | Pending | TBD | Progress chip should show/update/hide with rcheevos text. |
| Complete/master game or subset | Pending | TBD | Completion/mastery toast should appear with correct softcore/hardcore wording. |

---

## Offline / reconnect / queue evidence

Use a fresh RA-supported game or a test account/game state where an early achievement can be unlocked while offline.

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Disconnect network during active RA session | Pending | TBD | Offline/disconnected toast should appear. |
| Unlock achievement while offline | Pending | TBD | rcheevos should queue retryable unlock submission. |
| Reconnect before closing game | Pending | TBD | Reconnected/sync toast appears and unlock reaches RA profile. |
| Close game while offline after queued unlock | Pending | TBD | Need verify queue/cache behavior on session close. |
| Force server error response | Pending | TBD | Server-error toast should show API/error context. |

Suggested network methods:

- Temporarily disable Wi-Fi from Control Center.
- Use macOS firewall/network filter tooling if Wi-Fi disruption is too broad.
- Avoid logging out of RA for queue testing; this should simulate transport failure, not authentication failure.

---

## Pause / idle evidence after #523

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Softcore pause/resume | Pending | TBD | Pause and resume should still work normally. |
| Hardcore pause after normal gameplay | Pending | TBD | Pause should succeed when rcheevos allows it. |
| Hardcore pause spam | Pending | TBD | Denied pause attempts should show “Pause Blocked in Hardcore” toast if rcheevos denies. |
| Pause for >60 seconds in RA session | Pending | TBD | Rich Presence/activity should remain healthy through `rc_client_idle()`. |

---

## Submission notes for RetroAchievements reviewer

Current known reviewer-facing notes:

- OpenEmu-Silicon sends an OpenEmu-specific User-Agent in the form `OpenEmu-Silicon/<version> (macOS <version>) rcheevos/<version>`.
- OpenEmu-Silicon should not spoof another emulator identity.
- RA may still show OpenEmu-Silicon as an unknown emulator until the RA side recognizes/approves the client identity.
- Softcore save-state RA progress serialization is still P2/follow-up. Hardcore save-state loads are blocked.
- Media-change handling via `rc_client_begin_change_media()` is still follow-up for applicable disc/disk systems.

Open question for RA:

> What exact client registration or approval step is required so `OpenEmu-Silicon/<version> ... rcheevos/<version>` is recognized for hardcore credit?
