# OpenEmu-Silicon: Roadmap

_Last updated: 2026-04-05_

Active work is tracked in GitHub issues and milestones — that is the source of truth. This document covers high-level direction and what is explicitly out of scope.

**Active milestones:**
- [v1.0.5 Release](https://github.com/nickybmon/OpenEmu-Silicon/milestone/2) — PPSSPP fixes, melonDS integration, Dolphin audio/input/save states, MAME spike
- [v1.1.0 Release](https://github.com/nickybmon/OpenEmu-Silicon/milestone/3) — Full MAME/Arcade integration, Dolphin submodule update

---

## Out of Scope

These systems are not planned for this fork at this time:

| System | Reason |
|--------|--------|
| Nintendo 3DS | Citra/Lime3DS exist but have never had an OpenEmu wrapper. Significant bring-up cost. |
| PlayStation 2 | PCSX2 has never had a working OpenEmu integration. Very high complexity. |
| PlayStation Vita | No suitable emulator with a clean embedding API. |
| Nintendo Switch | Yuzu/Ryujinx are not suitable for plugin embedding. |

---

## How to Contribute

**Branch naming:** `feat/<system>-<phase>` (e.g. `feat/melonds-phase1`, `feat/dolphin-3c-audio`)

**PR format:** Follow `.github/PULL_REQUEST_TEMPLATE.md`. Each sub-phase gets its own PR.

**Before opening a PR:** Build passes, plugin installs and loads without crashing, a ROM boots. A working demo video is strongly encouraged for new core integrations.
