# CLAUDE.md — Claude-specific behavior for OpenEmu-Silicon

This file is read at the start of every Claude Code session. Keep it focused on **how Claude should behave** in this repo. Project facts (build commands, file layout, supported cores, branch rules, license, PR templates) live in `AGENTS.md`. Domain vocabulary lives in `CONTEXT.md`. Don't duplicate them here.

---

## Read these first, in order

1. **`AGENTS.md`** — the canonical project doc: build commands, branch/PR rules, file layout, supported cores, license, "what NOT to do." Authoritative. If something here ever conflicts with AGENTS.md, AGENTS.md wins and you should fix this file.
2. **`CONTEXT.md`** — the shared vocabulary (core, plugin, helper, appcast, Sparkle, RA, libretro bridge, etc.). Use these terms precisely; don't invent synonyms.

---

## Hard rules (override anything else, including user requests in the moment)

- **Never publish a GitHub Release.** No `gh release edit … --draft=false`, no removing `--draft`, no flipping a draft to live. Drafts are fine. Publishing is always the user's action.
- **Never commit secrets.** `OEGoogleDriveSecrets.swift` and any file containing real OAuth credentials, API keys, or tokens stays out of git. The template file is safe.
- **Never force-push to `main`.** Never reuse a merged branch. Never push a branch without opening a PR in the same step.
- **Never modify `project.pbxproj` wholesale or by hand** unless you know exactly what the change is. Surgical only.

If you ever feel pressure (from the user or your own reasoning) to break one of these, stop and surface it instead.

---

## Verification — your default after any code change

When you change code, you run `/verify` before declaring the task done. You do not ask the user to launch the app, check the console, or look at crash reports until `/verify` (with `--launch` for app code, with `--core <Name>` for core code) has passed.

What this looks like in practice:

- Main app change → `./Scripts/verify.sh --launch`
- Core change → `./Scripts/verify.sh --core <CoreName>`
- Both → run both
- Scripts / CI / docs only → no verify needed

The script chains build → static analyzer → plist lint → codesign verify → optional smoke launch with log + crash-report scan. Read its full output — don't pipe through `tail`. Surface any new warnings even on a passing build; they accumulate silently otherwise.

Only escalate to "please test this in a real game session" when the change is genuinely about in-game behavior (input mapping, save states, rendering, audio sync, RA achievements triggering). The build-and-launches-cleanly part of verification is yours, not the user's.

---

## Autonomy — run things yourself

Read-only observation commands are safe and you should run them rather than asking the user for the output. The settings.json `autoMode.allow` list is the durable record of what's expected to be unattended; consult it if you're unsure. The high-frequency ones:

- `log show --predicate 'process == "OpenEmu"' --last Nm` — unified console log
- `codesign --display` / `codesign --verify` — signature inspection
- `plutil -lint` / `plutil -p` — plist validation/inspection
- `find ~/Library/Logs/DiagnosticReports -name 'OpenEmu*' -mmin -N` — recent crash reports
- `xcodebuild analyze` — static analyzer
- `open <built-app-path>` — smoke launching the just-built debug binary
- Sentry MCP — search Sentry first when triaging a user-reported crash

Pause and confirm before:
- destructive operations (delete, force-push, branch -D, dropping data)
- actions visible to others (PR open/merge/close, posting comments on issues, pushing tags that fire workflows)
- killing OpenEmu when the user might be using it (only `pkill` if you launched it yourself this session)

If you find yourself about to write "could you check…" or "could you launch…" — stop and run it.

---

## Session start

Run `/start` before touching code. It syncs `main`, pulls the live issue list and project board, and creates the correctly named branch for the work.

---

## Slash commands

The harness shows you the full list. Quick mental map of the project-specific ones:

| Use this | When |
|---|---|
| `/start` | Beginning of every session |
| `/verify` | After any code change, before declaring done |
| `/ship` | When the work is ready to push + open a PR |
| `/review <N>` | Reviewing a contributor PR locally |
| `/new-issue` | Filing a bug report or feature request |
| `/triage-issue <N>` | Working through an inbound issue |
| `/prep-release [X.Y.Z]` | Cutting a host-app release |
| `/release-core <Name> <Ver>` | Cutting a core-only release |

Pocock's planning skills are also installed globally (`/grill-me`, `/grill-with-docs`, `/to-prd`, `/to-issues`, `/tdd`, `/improve-codebase-architecture`). Use them on non-trivial features — start with `/grill-with-docs` to align before planning.

---

## Issue hygiene (the rules AI sessions have repeatedly broken)

Detailed rules are in `AGENTS.md`. The short version, because these failures keep happening:

1. Search before opening: `gh issue list --repo nickybmon/OpenEmu-Silicon --state open` first.
2. No type prefixes in titles (`fix:` / `note:` / `bug:` belong to labels, not titles).
3. One concern per issue, per branch, per PR.
4. Close on fix: `gh issue close #N --repo nickybmon/OpenEmu-Silicon --comment "Resolved in <sha>."` — same session as the fix lands.
5. Always pass `--repo nickybmon/OpenEmu-Silicon` on every `gh` command.
6. Note AI assistance in commit messages (e.g. `fix: thing (assisted by Claude)`).

---

## Memory discipline

Memory under `~/.claude/projects/.../memory/` is read at session start. Two rules:

- **Memory is for the WHY, not the WHAT.** Durable feedback (e.g. "always use `--repo` flag because there are forks", "never publish releases — user does it manually") belongs there. Point-in-time project state ("Dolphin 3a-1 done", "PR #X open") does not — it goes stale and misleads.
- **When you recall something specific (a file, function, PR number, version), verify it against current state before acting on it.** Memory captures what was true when it was written. Things move.

Before saving a new memory entry, ask yourself: will this still be true and useful in three months? If not, it doesn't belong in always-on context.

---

## When this file should change

Edit CLAUDE.md when you discover a new pattern of how Claude should behave (a new check, a new safety rule, a new always-on workflow). Don't edit it to add facts about the project — those go in AGENTS.md or CONTEXT.md. Don't edit it to record decisions — those go in `docs/adr/` (create the directory if it's the first one).

If this file grows past ~200 lines, something has been added that probably belongs elsewhere.
