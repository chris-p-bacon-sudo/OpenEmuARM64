# RetroAchievements Submission Package — OpenEmu-Silicon

Reviewer-ready artifact for RA client registration/approval. Populated from
`retroachievements-compliance-evidence.md`; update that file for day-to-day
tracking and pull final values here when submitting.

---

## 1. Identity

| Field | Value |
| --- | --- |
| Emulator name | OpenEmu-Silicon |
| Platform | macOS (Apple Silicon — M1/M2/M3/M4) |
| Current version | 1.2.2 |
| GitHub URL | <https://github.com/nickybmon/OpenEmu-Silicon> |
| Visibility | Public |
| Public since | 2026-03-20 |
| Six-month mark | 2026-09-20 |
| Upstream lineage | Derived from OpenEmu (<https://github.com/OpenEmu/OpenEmu>), which predates this fork by years. |

OpenEmu-Silicon is a macOS-native emulation frontend built on Apple Silicon. It
integrates rcheevos directly into each supported core plugin via a shared
transport layer (`oeRetroAchievementsServerCall`) and a shared notification
system for session events, challenge indicators, leaderboards, and unlock UI.

**Lineage note for reviewer:** If RA requires a six-month public-availability
window counted from first public release, the clock starts 2026-03-20 (GitHub
public date). If RA allows inherited lineage from the upstream OpenEmu project
(which has been public for years), please clarify how that affects approval
timing. We are happy to provide additional evidence of lineage.

---

## 2. User-Agent sample

After PR #586 merges, every native RA HTTP request carries:

```text
OpenEmu-Silicon/1.2.2 (macOS 15.4.0) rcheevos/11.5.0 Nestopia/1.53.0
```

Format: `OpenEmu-Silicon/<host-version> (macOS <os-version>) rcheevos/<rcheevos-version> <CoreName>/<core-version>`

The core clause is derived from the active plugin bundle at runtime — each of the
9 native RA cores reports its own name and `CFBundleShortVersionString`. The
format matches the RetroArch convention Wes requested.

**Live sample:** capture a network log from any RA session after PR #586 merges
and paste the verbatim `User-Agent` header here before sending to RA.

---

## 3. Hardcore compliance evidence

Full P0 audit table and P1 matrix: [`retroachievements-compliance-evidence.md`](retroachievements-compliance-evidence.md).

Summary of enforced restrictions when hardcore is on:

| Restriction | Enforced |
| --- | --- |
| Save-state load | Yes — blocked at document, helper, and base core layers |
| Rewind | Yes — blocked at document, helper, and core; active rewind cleared on enable |
| Fast-forward | Yes — `fastForwardAtSpeed:` returns early |
| Slow motion | Yes — `slowMotionAtSpeed:` returns early |
| Frame advance | Yes — blocked at document and helper layers |
| Cheats | Yes — saved cheat autoload skipped; document and helper reject cheat application |
| Pause (extended) | Yes — `rc_client_can_pause` queried before allowing user-initiated pause |
| Softcore→hardcore mid-session | Yes — triggers a hard reset per RA spec |

Enforcement is defense-in-depth: document layer, `OpenEmuHelperApp`, and
`OEGameCore` base class all enforce independently so a future refactor of one
layer cannot silently loosen the contract.

---

## 4. Live gameplay evidence

### 2026-05-17 — Nestopia — Super Mario Bros. — full P1 pass

- **Core:** Nestopia 1.53.0
- **System:** NES / Famicom
- **Game:** Super Mario Bros.
- **RA mode:** Hardcore and Softcore
- **RA account:** nickybmon
- **Result:** Pass

Verified behaviors:

- Boot placard (recognized game) appeared.
- Challenge indicator lifecycle (show → hide on disqualification).
- Achievement unlock (earned achievement appeared on RA profile).
- Leaderboard start / tracker / result flow.
- Rich Presence: RA profile showed `Super Mario in 1-1, 🏃:3, 1st Quest` live.
- Hardcore pause blocked by `rc_client_can_pause`.
- Softcore: repeated pause/unpause worked without issue.
- Offline/reconnect: Wi-Fi disconnect showed `RA: Offline` chip; reconnect
  cleared it; offline-earned achievement appeared on RA profile after reconnect.
- Achievements window: Hardcore badge, point totals, set switching, active
  challenge row, `Active Now` section.

Screenshot path (local): `/Users/nickblackmon/Library/Application Support/CleanShot/media/media_3t5qIGd8AG/CleanShot 2026-05-17 at 20.11.24@2x.png`

---

## 5. Core / license matrix

See [`retroachievements-compliance-evidence.md`](retroachievements-compliance-evidence.md#corelicense-matrix) for the full table.

Confirmed-shipped native RA cores (the 9 cores with direct rcheevos integration):

| Core | System(s) | License status |
| --- | --- | --- |
| Nestopia | NES, FDS | LGPL 2.1 (nes_ntsc sublibrary confirmed; top-level confirmation pending) |
| FCEU | NES / Famicom | GPL v2-or-later |
| BSNES | SNES | GPL v3 |
| SNES9x | SNES | Custom non-commercial license |
| Gambatte | GB / GBC | GPL v2 |
| Genesis Plus GX | Genesis, SMS, Game Gear, SG-1000, Sega CD | Non-commercial terms |
| mGBA | GBA, GB, GBC | MPL 2.0 |
| Mupen64Plus | N64 | Mixed GPL / LGPL |
| Mednafen | PSX, PC Engine, PCE-CD, PC-FX, Saturn, VB, Lynx, NGP, WS | GPL |

Full matrix (all shipped cores including non-RA ones): see compliance evidence doc.

---

## 6. Privacy policy

Full text: [`privacy-policy.md`](privacy-policy.md)

Summary:

- RA is **opt-in** — not active unless the user signs in from Preferences → Achievements.
- Credentials are exchanged with RetroAchievements/rcheevos; the resulting token is stored locally in OpenEmu's encrypted keychain.
- During an RA session, the following may be sent to RetroAchievements: game hash (for title identification), game/session state for achievement evaluation, unlock submissions, leaderboard submissions, Rich Presence updates, and User-Agent / client identity.
- OpenEmu-Silicon does not operate RA servers and does not control RA-side data retention.
- Optional Sentry crash reporting is separately consent-gated and is not connected to RA.
- This project does not operate a backend server for RA, sync, telemetry, or accounts.

---

## 7. No monetization

OpenEmu-Silicon is free, open-source, and non-commercial.

- No in-app purchases, subscriptions, or ads.
- No paid achievements, paid unlocks, or paid online services.
- Several bundled emulator engines carry explicit non-commercial distribution terms (Genesis Plus GX, SNES9x, Picodrive) — compliance with those terms is maintained.

---

## 8. Windows toolkit

OpenEmu-Silicon is macOS-only. The RetroAchievements Windows toolkit requirement
is not applicable. Runtime verification is done through the native macOS app and
rcheevos integration.

---

## 9. Open question for RA

> **What exact client registration or approval step is required so that
> `OpenEmu-Silicon/1.2.2 (macOS 15.4.0) rcheevos/11.5.0 Nestopia/1.53.0` is
> recognized for hardcore credit?**

We have implemented the full hardcore compliance spec, matched the User-Agent
format RetroArch uses (emulator/version + core/version), and have live gameplay
evidence. We want to understand whether there is a registration form, a
whitelist entry, or an API-side configuration step required on the RA side to
activate hardcore credit for this client string.

---

## 10. Six-month timeline note

| Milestone | Date |
| --- | --- |
| Local development begins | 2026-01-25 |
| GitHub repository public | 2026-03-20 |
| Six-month mark from public | 2026-09-20 |
| Upstream OpenEmu public history | Years prior (see <https://github.com/OpenEmu/OpenEmu>) |

If RA requires six months of public availability counted from first GitHub
public date, the approval window opens 2026-09-20. If lineage from upstream
OpenEmu is considered, we believe this fork qualifies sooner.

We are happy to provide evidence of upstream OpenEmu's history and the
continuity of the codebase.
