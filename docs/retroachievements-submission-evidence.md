# RetroAchievements Submission Evidence

This document gathers the non-gameplay evidence needed for issue #438 and a future RetroAchievements reviewer submission.

For manual runtime evidence, use [`retroachievements-p1-evidence-log.md`](retroachievements-p1-evidence-log.md). For implementation details, use [`retroachievements-implementation-guide.md`](retroachievements-implementation-guide.md).

---

## Current status

| Area | Status | Evidence / next action |
| --- | --- | --- |
| User-Agent / client identity | Implemented; RA approval pending | OpenEmu-Silicon sends its own User-Agent and should not spoof another emulator. Ask RA what registration step is required for hardcore credit. |
| No monetization / IAP | Documented here | OpenEmu-Silicon is a free public GitHub project; no in-app purchases, subscriptions, ads, or paid unlocks are implemented in this repo. |
| Privacy policy | Updated for RA/Sentry | See [`privacy-policy.md`](privacy-policy.md). |
| Public availability timeline | Partial / needs reviewer decision | This fork's GitHub repository is public as of 2026-03-20. Local git history begins 2026-01-25. Upstream OpenEmu predates this fork by years. If RA requires this fork itself to be public for 6 months, earliest date from GitHub visibility is 2026-09-20. |
| Windows toolkit support | N/A | OpenEmu-Silicon is macOS-only. Windows toolkit support is not applicable. |
| Core/license matrix | Partial / needs broader pass | RA-native core matrix started below. Full shipped-core matrix remains a separate evidence task. |
| Picodrive non-commercial status | Documented here | `picodrive/COPYING` prohibits commercial redistribution/use. Do not charge for builds that include Picodrive. |

---

## RetroAchievements client identity

OpenEmu-Silicon uses native `rc_client` integrations for supported native cores and routes rcheevos HTTP through the shared OpenEmu transport.

Reviewer-facing points:

- Product identity should be OpenEmu-Silicon, not another emulator.
- OpenEmu-Silicon should not spoof RetroArch, PPSSPP, or any other approved client.
- The known reviewer-facing question is:

> What exact client registration or approval step is required so `OpenEmu-Silicon/<version> ... rcheevos/<version>` is recognized for hardcore credit?

Runtime User-Agent sample still needs capture from transport logs or packet capture and should be recorded in [`retroachievements-p1-evidence-log.md`](retroachievements-p1-evidence-log.md).

---

## No monetization / commercialization statement

OpenEmu-Silicon is distributed as a free public GitHub project at <https://github.com/nickybmon/OpenEmu-Silicon>.

No monetization features are implemented in this repository:

- No in-app purchases.
- No subscriptions.
- No ads.
- No paid achievements or paid unlocks.
- No paid online service operated by this project.

Important licensing constraint:

- Picodrive is non-commercial. `picodrive/COPYING` says redistributions may not be sold or used in a commercial product or activity.
- Any release that includes Picodrive must remain non-commercial.

---

## Privacy / data handling summary

The privacy policy lives at [`privacy-policy.md`](privacy-policy.md).

RetroAchievements-specific summary:

- RA is optional and only active after the user signs in from Preferences → Achievements.
- RA credentials are exchanged with RetroAchievements/rcheevos; the app stores the resulting token locally in the macOS Keychain.
- During RA gameplay, OpenEmu-Silicon/rcheevos may send game hashes, game/session state needed for achievement evaluation, unlock submissions, leaderboard submissions, Rich Presence updates, and client/User-Agent information to RetroAchievements.
- OpenEmu-Silicon does not operate the RetroAchievements servers and does not control RA-side retention.

Crash reporting summary:

- Sentry crash reporting is optional and consent-gated.
- If enabled, crash reports may include app version/build, OS/device diagnostics, stack traces, performance/hang diagnostics, and active game/system/core context.
- The consent prompt states that game files, save data, and passwords are not included.

Project-operated servers:

- This project does not operate a backend server for RA, sync, telemetry, or accounts.

---

## Public availability timeline

Known dates:

| Source | Date | Evidence |
| --- | --- | --- |
| Local repository history begins | 2026-01-25 | `git log --reverse` first commit: `5103b813 Step 1: OpenEmu Core and SDKs`. |
| GitHub repository created/public | 2026-03-20 | `gh repo view nickybmon/OpenEmu-Silicon --json createdAt,visibility` reports `createdAt: 2026-03-20T14:47:23Z`, `visibility: PUBLIC`. |
| Upstream OpenEmu availability | Predates this fork by years | Upstream project: <https://github.com/OpenEmu/OpenEmu>. |

Reviewer note:

- If RA treats OpenEmu-Silicon as a new emulator/client, the six-month public-availability date may need to be counted from 2026-03-20, making the six-month mark 2026-09-20.
- If RA allows inherited lineage from OpenEmu plus this fork's public development evidence, explain that lineage explicitly in the submission.

---

## Windows toolkit support

OpenEmu-Silicon is a native macOS app. Windows toolkit support is not applicable.

Suggested reviewer wording:

> OpenEmu-Silicon is macOS-only. The RetroAchievements Windows toolkit requirement is not applicable to this platform; runtime verification is done through the native macOS app and rcheevos integration.

---

## Native RA core/license matrix — initial pass

This table is scoped to native RA-enabled cores first. It is not yet the full shipped-core license matrix requested in #438.

| Core | Systems | License evidence in repo | Notes |
| --- | --- | --- | --- |
| Nestopia | NES, FDS | No top-level license file found in `Nestopia/`; `Info.plist` project URL is `https://gitlab.com/jgemu/nestopia` | Needs upstream license confirmation in full matrix. |
| FCEU | NES / Famicom | No top-level license file found in `FCEU/` | Needs upstream license confirmation in full matrix. |
| BSNES | SNES | `BSNES/bsnes/LICENSE.txt` | bsnes is GPLv3-only; bundled helper libraries include permissive terms. |
| SNES9x | SNES | `SNES9x/src/LICENSE` | Snes9x license includes non-commercial language: “Under no circumstances will commercial rights be given.” |
| Gambatte | GB, GBC | `Gambatte/COPYING` | GPLv2. |
| GenesisPlus | Genesis, SMS, Game Gear, SG-1000, Sega CD | No top-level license file found in `GenesisPlus/`; third-party dependency licenses are present under `genplusgx_source/` | Needs upstream license confirmation in full matrix. |
| mGBA | GBA, GB, GBC | `mGBA/LICENSE` | MPL 2.0. |
| Mupen64Plus | N64 | `Mupen64Plus/mupen64plus-core/LICENSES`, `doc/gpl-license`, `doc/lgpl-license` | Mixed GPL/LGPL components; needs component-level confirmation in full matrix. |
| Mednafen | PlayStation, PC Engine, Atari Lynx, Neo Geo Pocket | Dependency license files exist under `Mednafen/mednafen/`; no single top-level license file found in `Mednafen/` | Needs upstream/component license confirmation in full matrix. |

## Full shipped-core matrix follow-up

The full matrix should cover every bundled/distributed core and major vendored dependency, not just RA-enabled native cores.

Suggested columns:

- Core/plugin name
- Systems
- Upstream project URL
- Repo path
- License(s)
- License file path(s)
- Commercial-use constraints
- Source-availability obligations
- Binary distribution obligations
- Notes / unresolved questions
