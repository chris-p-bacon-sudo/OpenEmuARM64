# RetroAchievements Compliance Evidence Tracker

This is the canonical verification and evidence tracker for the native RetroAchievements compliance rollout closed in issue #438.

Keep only three RA docs current:

- [`retroachievements-community-guide.md`](retroachievements-community-guide.md) — user/contributor testing and reporting guide.
- [`retroachievements-implementation-guide.md`](retroachievements-implementation-guide.md) — developer integration pattern and known rc_client pitfalls.
- **This file** — compliance evidence, verification results, submission notes, and follow-up tracking.

Scope: native RetroAchievements cores only. Libretro/RetroArch RA compliance is tracked separately in #360.

---

## Status summary

Issue #438 is closed for the native-core P0/P1 rollout.

Completed:

- Hardcore bypass gates and P0 audits.
- Shared OpenEmu-Silicon User-Agent for native RA traffic.
- Boot/session placards.
- Native Achievements window.
- Active challenge/progress state in the Achievements window.
- Challenge, progress, leaderboard, unlock, completion/mastery, offline/reconnect, and server-error UI surfaces.
- `rc_client_idle()` while paused.
- `rc_client_can_pause()` before user-initiated hardcore pause.
- Rich Presence visibility in a live RA session.
- Offline queued unlock sync after reconnect.
- Privacy/no-monetization/non-commercial evidence scaffolding.
- Core/license matrix draft.

Follow-up work split from #438:

| Issue | Scope |
| --- | --- |
| #537 | Softcore save-state rcheevos progress serialization. |
| #538 | Close-while-offline queued unlock/session-purge edge case. |
| #539 | Final RA submission package: license matrix completion, public-availability framing, screenshots/video bundle, User-Agent sample, and RA client approval question. |
| #360 | Libretro/RetroArch RA host compliance. |

---

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

---

## P0 hardcore audit

Hardcore restrictions are enforced only when all of these are true:

1. The user has enabled the RetroAchievements hardcore preference.
2. A RetroAchievements token is stored.
3. The selected core advertises `OEGameCoreSupportsRetroAchievements` for the active system.

This avoids disabling save states, rewind, cheats, or speed controls for non-RA games or unsupported core/system pairs.

| Area | Result | Evidence |
| --- | --- | --- |
| Startup hardcore ordering | Pass | `OEGameDocument` pushes effective RA token/mode/hardcore state before startup save-state decisions. |
| Startup resume behavior | Pass | Startup save-state restore routes through guarded load-state paths. |
| Normal save-state load | Pass | Host and helper block load-state in hardcore with user-facing feedback. |
| Quick-load | Pass | Routes through the same guarded load-state path. |
| Helper load-state path | Pass | `OpenEmuHelperApp.loadStateFromFile(at:)` rejects when helper-side hardcore is true. |
| Rewind | Pass | Host, helper, and base `OEGameCore` paths block rewind in hardcore; active rewind state is cleared when hardcore is enabled. |
| Frame advance | Pass | Host, helper, and base `OEGameCore` paths block frame advance in hardcore. |
| Fast-forward / analog speed | Pass | `OEGameCore.fastForward(_:)` and `fastForwardAtSpeed(_:)` return without changing rate in hardcore. |
| Slow motion | Pass | `OEGameCore.slowMotionAtSpeed(_:)` returns without changing rate in hardcore. |
| Cheats | Pass | Saved cheat autoload is skipped, document-level cheat actions return early, and helper-side `setCheat` rejects in hardcore. |
| Mode switch: softcore → hardcore | Pass | Mid-session switch prompts for full reset before enabling helper/core hardcore. |
| Mode switch: hardcore → softcore | Pass | Disabling hardcore pushes softcore mode without requiring reset. |
| User-Agent | Pass for native RA path | Native RA HTTP uses shared OpenEmu transport and sends `OpenEmu-Silicon/<version> (macOS <version>) <rcheevos-clause>`. RA-side recognition/approval is still required for hardcore credit. |

---

## rc_client implementation audit

Static audit at commit `9e701cd3` confirmed all nine native RA cores contain the expected runtime hooks.

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

Static audit also found:

- No OpenEmu use of `rc_client_set_spectator_mode_enabled`.
- No OpenEmu Rich Presence disable toggle.
- No OpenEmu leaderboard-disable toggle.
- Leaderboard rcheevos events route through `OERetroAchievementsTransport.m` and display through `OEGameDocument.swift` / `GameViewController.swift`.

---

## Local build / install evidence

| Date | Commit | Result | Notes |
| --- | --- | --- | --- |
| 2026-05-17 | `9e701cd3` | Pass | Host Debug build: `xcodebuild -workspace OpenEmu-metal.xcworkspace -scheme OpenEmu -configuration Debug -destination 'platform=macOS,arch=arm64' build` ended with `** BUILD SUCCEEDED **`. |
| 2026-05-17 | `9e701cd3` | Pass | OpenEmuBase tests: 39 tests passed, including 22 hardcore-gate tests. |
| 2026-05-17 | `9e701cd3` | Pass | Nestopia Release installed and verified with `verify-core-installed.sh --release Nestopia`; md5 `33f139bc26f6247eac62cba91a0fd326`. |
| 2026-05-17 | `bfa8ecb7` | Pass | Credential migration fix built and launched from fresh DerivedData app path; stale build paths removed. |
| 2026-05-17 | `16db7cea` | Pass | Active/offline UI polish built and live-verified by Nick. |

---

## Live gameplay evidence

### 2026-05-17 — Nestopia — Super Mario Bros. — P1 verification pass

- **Core / scheme:** Nestopia / `OpenEmu + Nestopia`
- **System:** NES/Famicom
- **Game:** Super Mario Bros.
- **RA mode:** Hardcore
- **RA username:** nickybmon
- **Result:** Pass for recognized placard, challenge indicator lifecycle, leaderboard start/tracker/result flow, achievement unlocks, Achievements window session data/set switching, Rich Presence/activity visibility, hardcore pause-denied behavior, and offline/reconnect UI.
- **Evidence:** RA profile/activity screenshot at local path `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_3t5qIGd8AG/CleanShot 2026-05-17 at 20.11.24@2x.png` showed `nickybmon`, Last Activity 1 second ago, Most Recently Played Super Mario Bros., and activity text `Super Mario in 1-1, 🏃:3, 1st Quest`.

Observed behavior:

- Boot placard appeared on game start.
- Challenge triggered and later hid after disqualification.
- Leaderboard started, tracker activity appeared, leaderboard stopped with result.
- Achievements unlocked and appeared on RA.
- Achievements window showed Hardcore Mode, points, set switching, and achievement metadata.
- RA profile showed Super Mario Bros. activity during the session.
- Hardcore pause was blocked as expected.
- Wi-Fi disconnect produced offline/pending retry UI and reconnect UI.

### 2026-05-17 — Nestopia — Super Mario Bros. — pause, active-state, offline queue

- **Core / scheme:** Nestopia / `OpenEmu + Nestopia`
- **System:** NES/Famicom
- **Game:** Super Mario Bros.
- **RA mode:** Hardcore and Softcore
- **RA username:** nickybmon
- **Result:** Pass for 60s+ pause/idle continuity, Softcore pause regression check, active challenge row state, offline/reconnect UI, and offline queued unlock sync after reconnect.
- **Evidence:** Achievements window / active challenge screenshot at local path `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_ri8tOJIavk/CleanShot 2026-05-17 at 20.37.51@2x.png`.

Observed behavior:

- RA profile continued to show Super Mario Bros. as active/recent during pause and after unpause.
- Softcore mode allowed repeated pause/unpause without issue.
- Achievements window showed `Challenge Active` for the active challenge row.
- Wi-Fi disconnect showed offline/pending retry messaging.
- Reconnect showed pending submissions completed.
- Offline-earned achievement appeared on RA after reconnect.

### 2026-05-17 — Nestopia — Super Mario Bros. — final active/offline polish

- **Core / scheme:** Nestopia / `OpenEmu + Nestopia`
- **System:** NES/Famicom
- **Game:** Super Mario Bros.
- **RA mode:** Hardcore
- **RA username:** nickybmon
- **Result:** Pass for active/offline polish.

Observed behavior:

- `Active Now` appeared and looked good.
- Active row remained prominent without the unwanted orange box.
- Challenge chips were top-aligned with the RA notice area.
- `RA: Offline` appeared immediately after Wi-Fi disconnect.
- `RA: Offline` cleared on reconnect.
- No weirdness reported.

---

## P1 verification matrix

| Area | Status | Evidence |
| --- | --- | --- |
| Recognized-game boot placard | Pass | Live Nestopia / Super Mario Bros. pass. |
| Achievements window | Pass | Shows Hardcore Mode, points, set switching, metadata, active challenge state, and polished `Active Now` section. |
| Unrecognized/no-set feedback | Implemented | PR #521 surfaced unrecognized/no-set, login, and load-failure states; fresh screenshot still useful for submission package. |
| Rich Presence works | Pass | RA profile/activity showed Super Mario Bros. live session text. |
| Rich Presence cannot be disabled in hardcore | Pass | No disable path found; live hardcore session activity visible. |
| Leaderboards work | Pass | Start/tracker/result flow observed in Super Mario Bros. |
| Leaderboards cannot be disabled in hardcore | Pass | Leaderboard flow worked in Hardcore Mode; no disable path found. |
| Offline queue syncs after reconnect | Pass | Offline-earned achievement appeared on RA after reconnect. |
| Offline queue/cache purge on session close | Follow-up | Split to #538. |
| Offline/reconnect UI | Pass | Toasts plus persistent `RA: Offline` chip verified. |
| Softcore pause after #523 | Pass | Repeated pause/unpause worked. |
| Hardcore pause after #523 | Pass | rcheevos denied pause and OpenEmu blocked it. |
| 60s+ pause/idle health | Pass | RA activity remained continuous through pause/resume. |
| Completion/mastery toast | Implemented; not live-triggered | Event path exists; live completion/mastery capture can be included in final submission package if available. |

---

## Submission evidence

### No monetization / commercialization

OpenEmu-Silicon is distributed as a free public GitHub project at <https://github.com/nickybmon/OpenEmu-Silicon>.

No monetization features are implemented in this repository:

- No in-app purchases.
- No subscriptions.
- No ads.
- No paid achievements or paid unlocks.
- No paid online service operated by this project.

Non-commercial constraints:

- `picodrive/COPYING` prohibits commercial redistribution/use.
- Genesis Plus GX source headers contain non-commercial redistribution terms.
- `SNES9x/src/LICENSE` contains non-commercial language.

### Privacy / data handling

Privacy policy: [`privacy-policy.md`](privacy-policy.md).

Summary:

- RA is optional and active only after sign-in from Preferences → Achievements.
- RA credentials are exchanged with RetroAchievements/rcheevos; the resulting token is stored locally in OpenEmu's encrypted credential store.
- RA gameplay can send game hashes, game/session state needed for achievement evaluation, unlock submissions, leaderboard submissions, Rich Presence updates, and client/User-Agent information to RetroAchievements.
- OpenEmu-Silicon does not operate RA servers or control RA-side retention.
- Optional Sentry crash reporting is consent-gated.
- This project does not operate a backend server for RA, sync, telemetry, or accounts.

### Public availability timeline

| Source | Date | Evidence |
| --- | --- | --- |
| Local repository history begins | 2026-01-25 | `git log --reverse` first commit: `5103b813 Step 1: OpenEmu Core and SDKs`. |
| GitHub repository created/public | 2026-03-20 | `gh repo view nickybmon/OpenEmu-Silicon --json createdAt,visibility` reported `createdAt: 2026-03-20T14:47:23Z`, `visibility: PUBLIC`. |
| Upstream OpenEmu availability | Predates this fork by years | Upstream project: <https://github.com/OpenEmu/OpenEmu>. |

Reviewer note:

- If RA treats OpenEmu-Silicon as a new emulator/client, the six-month public-availability date may need to be counted from 2026-03-20, making the six-month mark 2026-09-20.
- If RA allows inherited lineage from OpenEmu plus this fork's public development evidence, explain that lineage explicitly in the submission.

### Windows toolkit support

OpenEmu-Silicon is macOS-only. Windows toolkit support is not applicable.

Suggested reviewer wording:

> OpenEmu-Silicon is macOS-only. The RetroAchievements Windows toolkit requirement is not applicable to this platform; runtime verification is done through the native macOS app and rcheevos integration.

### User-Agent / client identity

Native RA traffic uses the shared OpenEmu transport function:

```objc
rc_client_create(<core>_rc_read_memory, oeRetroAchievementsServerCall)
```

The shared transport builds the HTTP User-Agent as:

```text
OpenEmu-Silicon/<host-version> (macOS <os-version>) <rcheevos user-agent clause>
```

Reviewer-facing points:

- Product identity should be OpenEmu-Silicon.
- OpenEmu-Silicon should not spoof RetroArch, PPSSPP, or any other approved client.
- RA may still show OpenEmu-Silicon as an unknown emulator until RA-side recognition/approval.

Open RA question:

> What exact client registration or approval step is required so `OpenEmu-Silicon/<version> ... rcheevos/<version>` is recognized for hardcore credit?

---

## Core/license matrix

This is an evidence matrix, not legal advice.

| Core/plugin | System(s) | Upstream/project URL | License evidence in repo | Status | Distribution notes |
| --- | --- | --- | --- | --- | --- |
| 4DO | 3DO | `http://www.fourdo.com/` | `4DO/libcue-1.4.0/COPYING` for bundled libcue; no single top-level 4DO license found in this pass | Needs confirmation | Confirm 4DO core license in #539. |
| Bliss | Intellivision | `https://github.com/jeremiah-sypult/BlissEmu` | `Bliss/Bliss/LICENSE.txt` | Confirmed | License file present. |
| BSNES | SNES | `https://byuu.org/bsnes` | `BSNES/bsnes/LICENSE.txt` | Confirmed | bsnes text states GPLv3-only; bundled helper libraries include permissive terms. |
| CrabEmu | ColecoVision | `http://crabemu.sourceforge.net/` | `CrabEmu/sound/nes_apu/COPYING` only found in this pass | Needs confirmation | Confirm main CrabEmu license in #539. |
| Dolphin | GameCube, Wii | `https://dolphin-emu.org/` | `Dolphin/dolphin/COPYING`, `Dolphin/dolphin/Externals/licenses.md` | Confirmed | GPL-family obligations apply; externals have separate licenses. |
| FCEU | NES / Famicom | `https://github.com/TASEmulators/fceux` | GPLv2-or-later notices in `FCEU/src/ines.h`, `FCEU/src/unif.h`, `FCEU/src/sound.h` | Confirmed | GPL source/binary obligations apply. |
| Flycast | Dreamcast | `https://github.com/flyinghead/flycast` | `Flycast/flycast/LICENSE` plus dependency licenses | Confirmed | Review dependency licenses for binary distribution. |
| Gambatte | GB / GBC | `https://gitlab.com/jgemu/gambatte` | `Gambatte/COPYING` | Confirmed | GPLv2 text present. |
| Genesis Plus GX | Genesis, SMS, Game Gear, SG-1000, Sega CD | `https://github.com/ekeeke/Genesis-Plus-GX` | Non-commercial terms in `GenesisPlus/genplusgx_source/loadrom.c`, `membnk.c`, `vdp_render.h`; dependency licenses under `genplusgx_source/` | Confirmed | **Non-commercial. Do not sell or use in commercial product/activity.** Complete source redistribution required for modified binaries. |
| JollyCV | ColecoVision | `https://gitlab.com/jgemu/jollycv` | `JollyCV/LICENSE`, `JollyCV/src/z80/LICENSE` | Confirmed | License files present. |
| Mednafen | PSX, PC Engine, PCE-CD, PC-FX, Saturn, Virtual Boy, Lynx, NGP, WonderSwan | `http://mednafen.sourceforge.net/` | GPL notices under `Mednafen/mednafen/`; module/dependency licenses include `lynx/license.txt`, `sms/docs/license`, `snes/src/data/license.html`, `mpcdec/COPYING`, `tremor/COPYING` | Confirmed | GPL-family obligations apply. |
| mGBA | GBA, GB, GBC | `https://mgba.io/` | `mGBA/LICENSE` | Confirmed | MPL 2.0 text present. |
| Mupen64Plus | N64 | `https://github.com/mupen64plus` | `Mupen64Plus/mupen64plus-core/LICENSES`, `doc/gpl-license`, `doc/lgpl-license`, plugin/dependency licenses | Confirmed | Mixed GPL/LGPL/component obligations. |
| Nestopia | NES, FDS | `https://gitlab.com/jgemu/nestopia` | No top-level license file found in `Nestopia/` during pass | Needs confirmation | Confirm Nestopia license in #539. |
| O2EM | Odyssey² / Videopac+ | `http://sourceforge.net/projects/o2em/` | `O2EM/clean/src/COPYING` | Confirmed | License file present. |
| Picodrive | 32X, Sega CD | `https://github.com/notaz/picodrive` | `picodrive/COPYING` | Confirmed | **Non-commercial. Do not sell or use in commercial product/activity.** |
| Potator | Supervision | `http://potator.sourceforge.net` | No clear top-level license file found in `Potator-Core/` during pass | Needs confirmation | Confirm in #539. |
| PPSSPP | PSP | `http://www.ppsspp.org/` | `PPSSPP/PPSSPP-Core/ppsspp/LICENSE.TXT` plus external licenses | Confirmed | GPL-family project; review external licenses. |
| ProSystem | Atari 7800 | `https://gitlab.com/jgemu/prosystem` | `ProSystem/LICENSE` | Confirmed | License file present. |
| SNES9x | SNES | `https://github.com/snes9xgit/snes9x` | `SNES9x/src/LICENSE` | Confirmed | Contains non-commercial language: “Under no circumstances will commercial rights be given.” |
| Stella | Atari 2600 | `http://sourceforge.net/projects/stella/` | BSD-style notices in wrapper/stub files; LGPL notices for NTSC filter files; no single top-level Stella license file found | Needs confirmation | Confirm main Stella core license in #539. |

In-tree directories needing plugin-status/license confirmation are tracked in #539: Atari800, blueMSX, DeSmuME, PokeMini, VecXGL, VirtualJaguar, MAME.

---

## Follow-up acceptance criteria

### #537 — save-state progress serialization

- Save-state format/design documented for native RA cores.
- Softcore save states persist/restore rcheevos runtime progress where supported.
- Old save states without RA blobs reset progress cleanly.
- Hardcore save-state loads remain blocked.
- At least one measured-progress achievement is verified across softcore save/load.

### #538 — offline close/session-purge behavior

- Close-while-offline queued unlock behavior documented.
- If rcheevos already purges/drops session-scoped queue data safely, record evidence.
- If queued data persists/syncs after session close in a non-compliant way, implement lifecycle fix.

### #539 — final submission package

- Reviewer-ready submission doc or issue comment exists.
- All license matrix unresolved rows are resolved or scoped out as not shipped.
- Privacy/no-monetization/non-commercial/public-availability evidence is final.
- Screenshots/video evidence is attached or linked.
- RA client identity/User-Agent approval question is included.
