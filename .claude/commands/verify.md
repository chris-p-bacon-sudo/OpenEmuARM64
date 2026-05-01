Run the autonomous verification floor on the current branch.

This is the default check after any code change. Do not ask the user to test things manually until `/verify` has run and passed.

## When to run which mode

| Change touched | Command |
|---|---|
| Main app code (`OpenEmu/`, `OpenEmuKit/`, `OpenEmu-SDK/`, `OpenEmu-Shaders/`) | `./Scripts/verify.sh --launch` |
| Code with coverage in `OpenEmu/OpenEmuTests/` | `./Scripts/verify.sh --launch --test` |
| A core plugin (`Dolphin/`, `Flycast/`, `mGBA/`, etc.) | `./Scripts/verify.sh --core <CoreName>` |
| Both | run both, in that order |
| Scripts, CI, docs only | skip — no code to verify |

## What it does

For the main app: build → static analyzer → plist lint → codesign verify on the built `.app`. With `--launch`: also launches the app for 5 seconds, scans the unified log for faults/errors, and checks `~/Library/Logs/DiagnosticReports/` for new crash reports.

For a core: builds the core scheme → plist lint → installs via `Scripts/install-core.sh` → verifies codesign on the installed plugin.

## What you do with the output

- Every check prints `PASS` or `FAIL` on a line of its own. The script exits with the count of failures.
- If anything fails, fix it before declaring the task done. Do not push a branch with failing verification.
- Warnings in the build log are surfaced even on a passing build — flag any new ones in your task report.
- Only escalate to "please test this in a real game session" if `/verify --launch` passed and the change is one that genuinely needs in-game behavior to validate (input mapping, save states, rendering, audio sync, RA cheevos triggering, etc.).

## What you do not do

- Do not ask the user to launch the app, check the console, look at crash reports, or run `codesign` themselves. Run `/verify` and report what it found.
- Do not pipe `verify.sh` through `tail -N` — it is designed to be terse and you should read all of it.
