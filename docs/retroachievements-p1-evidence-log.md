# RetroAchievements P1 Evidence Log

This document records manual verification evidence for issue #438 before resubmitting OpenEmu-Silicon for RetroAchievements review.

Use this alongside [`retroachievements-p1-verification.md`](retroachievements-p1-verification.md). That file describes what to test; this file records what was actually tested, with enough detail for reviewers to reproduce or audit the result. Legal/privacy/submission notes live in [`retroachievements-submission-evidence.md`](retroachievements-submission-evidence.md).

Scope: native RetroAchievements cores only. Libretro/RetroArch cores are tracked separately in #360.

---

## Evidence status summary

| Area | Status | Evidence |
| --- | --- | --- |
| Recognized-game boot placard | Passed on Nestopia / Super Mario Bros. | Tester observed boot placard on game start in live RA session. Capture still useful for submission package. |
| Achievements window | Passed basic list/set behavior and active challenge row state on Nestopia / Super Mario Bros.; active-state prominence follow-up identified | Achievements window showed Hardcore Mode, points, unlocked state, percentage metadata, set switching, and `Challenge Active` on the related row. Tester requested active rows be more visible/pinned near the top. |
| Unrecognized/no-set feedback | Pending fresh capture | Needs screenshot from current `main`. |
| Rich Presence works | Passed on RA profile/activity for Nestopia / Super Mario Bros. | RA profile screenshot showed Super Mario Bros. as Most Recently Played with live text `Super Mario in 1-1, 🏃:3, 1st Quest`. |
| Rich Presence remains active in hardcore | Passed for basic hardcore session visibility; longer pause/idle continuity still pending | Tester reported OpenEmu Achievements pane in Hardcore Mode while RA profile/activity showed the current SMB session. |
| Leaderboards work | Passed on Nestopia / Super Mario Bros. | Tester observed leaderboard start, tracker activity, stop/result, and achievement unlock. |
| Leaderboards cannot be disabled in hardcore | Passed on Nestopia / Super Mario Bros. | Leaderboard flow worked while the OpenEmu Achievements pane reported Hardcore Mode. |
| Offline unlock queue syncs after reconnect | Passed on Nestopia / Super Mario Bros. | Tester unlocked an achievement while offline, saw pending retry/reconnected messaging, and confirmed the achievement appeared on RA after reconnect. |
| Offline queue/cache is session-scoped/purged on close | Pending | Needs controlled close-while-offline test or RA maintainer confirmation. |
| Server error/offline/reconnect UI | Passed for offline/reconnect toasts | Tester observed “RetroAchievements Offline. Some submissions are pending retry.” and “RetroAchievements Reconnected.” |
| Pause/idle softcore behavior after #523 | Passed on Nestopia / Super Mario Bros. | Softcore placard/mode appeared, pause and unpause worked repeatedly, and RA state stayed healthy. |
| Pause/idle hardcore behavior after #523 | Passed denied-pause path | Tester observed pause blocked in Hardcore Mode. Allowed-pause path still needs confirmation if rcheevos allows it. |
| Pause for 60s+ keeps RA state healthy | Passed on Nestopia / Super Mario Bros. | RA profile/activity remained continuous during pause/idle and after resume. |

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
| Build configuration | Debug host app; Release Nestopia core installed |
| RetroAchievements username | nickybmon |
| Hardcore default setting | Hardcore enabled for live Nestopia / Super Mario Bros. pass |
| Network manipulation method | Wi-Fi disabled/re-enabled for offline/reconnect UI pass |
| Evidence folder / links | Local CleanShot screenshot: `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_3t5qIGd8AG/CleanShot 2026-05-17 at 20.11.24@2x.png` |

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

### 2026-05-17 — Nestopia — Super Mario Bros. — live P1 RA verification pass

- **Commit:** `767e717f`
- **Core / scheme:** Nestopia / `OpenEmu + Nestopia`
- **Installed plugin verified:** Yes — `verify-core-installed.sh --release Nestopia` reported the installed Release plugin matched the latest build before testing.
- **System:** NES/Famicom
- **Game:** Super Mario Bros.
- **Region / hash:** Not recorded during this pass.
- **RA mode:** Hardcore Mode shown in the OpenEmu Achievements pane.
- **RA username:** nickybmon
- **Test steps:** launched SMB, played a live RA session, watched boot/session UI, challenge and leaderboard overlays, achievement unlocks, Achievements window, RA profile/activity page, hardcore pause behavior, and Wi-Fi offline/reconnect UI.
- **Expected:** recognized-game placard appears; challenge/leaderboard/progress UI routes from rcheevos events; achievements window shows session data; RA profile/activity updates; hardcore pause preflight blocks when rcheevos denies pause; offline/reconnect toasts appear.
- **Actual:** boot placard appeared; challenge triggered and later turned off after disqualification; leaderboard started, tracker activity appeared, leaderboard stopped with result, and achievements unlocked; Achievements window showed Hardcore Mode, 4/775 points, set switching, and achievement metadata; RA profile showed Super Mario Bros. as Most Recently Played with rich activity text `Super Mario in 1-1, 🏃:3, 1st Quest`; hardcore pause was blocked; Wi-Fi disconnect produced “RetroAchievements Offline. Some submissions are pending retry.” and reconnect produced “RetroAchievements Reconnected.”
- **Result:** Pass for recognized placard, challenge indicator lifecycle, leaderboard start/tracker/result flow, achievement unlocks, Achievements window basic session data/set switching, Rich Presence/activity visibility, hardcore pause-denied behavior, and offline/reconnect UI. Inconclusive for actual offline queued unlock sync because the tester could not confirm whether a queued offline achievement reached RA after reconnect.
- **Evidence:** Local CleanShot screenshot of RA profile/activity page: `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_3t5qIGd8AG/CleanShot 2026-05-17 at 20.11.24@2x.png`. Screenshot showed `nickybmon`, Last Activity 1 second ago, Most Recently Played Super Mario Bros., and activity text `Super Mario in 1-1, 🏃:3, 1st Quest`.
- **Follow-up:** Capture a portable screenshot/video bundle for submission; run a targeted offline queue test where an unlock is known to occur only while offline and then verify RA-side sync after reconnect; run 60s+ pause/idle continuity check.

### 2026-05-17 — Nestopia — Super Mario Bros. — pause, active-state, and offline queue follow-up

- **Commit:** `bfa8ecb7`
- **Core / scheme:** Nestopia / `OpenEmu + Nestopia`
- **Installed plugin verified:** Previously verified before the live Nestopia evidence pass; host app relaunched from fresh DerivedData build after stale build cleanup.
- **System:** NES/Famicom
- **Game:** Super Mario Bros.
- **Region / hash:** Not recorded during this pass.
- **RA mode:** Both Hardcore and Softcore tested.
- **RA username:** nickybmon
- **Test steps:** checked RA profile/activity during pause, toggled Softcore and tested repeated pause/unpause, returned to Hardcore, opened Achievements window while challenges were active, disconnected/reconnected Wi-Fi while triggering an achievement.
- **Expected:** RA profile/activity remains healthy through pause/idle; Softcore pause remains unrestricted; Achievements window shows active challenge state; offline unlock is queued and syncs after reconnect.
- **Actual:** RA profile continued to show Super Mario Bros. as the active/recent game during pause and after unpause; Softcore mode allowed repeated pause/unpause without issue; Achievements window showed `Challenge Active` on the Master Plumber I row while challenge chips were visible in-game; Wi-Fi disconnect eventually showed offline/pending-retry messaging; reconnect showed pending submissions completed; the achievement appeared on RA after reconnect.
- **Result:** Pass for 60s+ pause/idle continuity, Softcore pause regression check, active challenge row state, offline/reconnect UI, offline queued unlock sync after reconnect. UX follow-up identified: active challenge/progress rows are too subtle and should be pinned or highlighted; offline state should have a persistent in-game indicator instead of only a toast.
- **Evidence:** Local CleanShot screenshot of Achievements window and active challenge chips: `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_ri8tOJIavk/CleanShot 2026-05-17 at 20.37.51@2x.png`.
- **Follow-up:** Improve Achievements window active-state prominence and add a persistent offline indicator chip while RA is disconnected. Offline queue/cache purge on session close remains untested.

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
| Launch known RA game and wait at least 30 seconds while playing | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | RA profile showed Super Mario Bros. as Most Recently Played with live activity text. |
| Continue playing for several minutes | Partial pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Activity was visible during the session; longer periodic-update capture still useful. |
| Hardcore mode enabled | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | OpenEmu Achievements pane showed Hardcore Mode while RA profile/activity updated. |
| Pause emulation for >60 seconds | Pending | TBD | After #523, `rc_client_idle()` should keep routine server communication alive. |

---

## Leaderboard evidence

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Start known leaderboard attempt | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester observed leaderboard start. |
| Continue attempt | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester observed different tracker activity during play. |
| Fail attempt | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Challenge/leaderboard state cleared when disqualified/stopped. |
| Submit attempt | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester observed leaderboard stopped and gave a result. |
| Hardcore mode enabled | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Leaderboard flow worked while Achievements pane showed Hardcore Mode. |

---

## Challenge / progress / mastery evidence

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Trigger challenge indicator | Pass | 2026-05-17 Nestopia / Super Mario Bros. entries | Tester observed challenge trigger/hide behavior and captured Achievements window row showing `Challenge Active`. Active-state prominence follow-up identified. |
| Trigger measured achievement progress | Partial pass | 2026-05-17 Nestopia / Super Mario Bros. entries | Static percentage/progress metadata was visible in Achievements window and in-game progress indicators were reported good. Targeted `Active: <progress>` row screenshot still useful. |
| Complete/master game or subset | Pending | TBD | Completion/mastery toast should appear with correct softcore/hardcore wording. |

---

## Offline / reconnect / queue evidence

Use a fresh RA-supported game or a test account/game state where an early achievement can be unlocked while offline.

| Test | Status | Evidence | Notes |
| --- | --- | --- | --- |
| Disconnect network during active RA session | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester observed offline toast after Wi-Fi was disabled. |
| Unlock achievement while offline | Pass | 2026-05-17 Nestopia / Super Mario Bros. follow-up entry | Tester triggered a first achievement offline, saw pending-retry messaging, and confirmed it appeared on RA after reconnect. |
| Reconnect before closing game | Pass | 2026-05-17 Nestopia / Super Mario Bros. follow-up entry | Reconnect toast appeared and RA-side achievement sync was confirmed. |
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
| Softcore pause/resume | Pass | 2026-05-17 Nestopia / Super Mario Bros. follow-up entry | Softcore mode allowed repeated pause/unpause and RA stayed healthy. |
| Hardcore pause after normal gameplay | Partial pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester saw rcheevos deny pause; allowed-pause path still needs a case where rcheevos permits pause. |
| Hardcore pause spam | Pass | 2026-05-17 Nestopia / Super Mario Bros. entry | Tester observed pause blocked in Hardcore Mode. |
| Pause for >60 seconds in RA session | Pass | 2026-05-17 Nestopia / Super Mario Bros. follow-up entry | RA profile/activity remained continuous during pause/idle and after resume. |

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
