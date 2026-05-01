Run the full git shipping loop for the current branch.

1. Confirm the branch name matches the work being done. If not, stop and ask.
2. Run the build check. If it fails, stop and report — do not push a broken build.
3. Confirm the commit message uses the correct format: `<type>: <description>` with `Fixes #N` in the body if resolving an issue.
4. Open a PR using this exact body structure (no other format is acceptable):

   **## Summary** — 1–3 bullets on what the PR fixes or adds.

   **## What changed** — per-file or per-component breakdown explaining the *why*.

   **## How to test locally** — a single bash block containing, in order:
   - `gh pr checkout <N> --repo nickybmon/OpenEmu-Silicon`
   - The correct `xcodebuild` invocation for the changed target:
     - App-only: `-scheme OpenEmu -configuration Debug`
     - Flycast core: `-scheme "OpenEmu + Flycast" -configuration Debug` with `clean build`
     - Mednafen core: `-scheme "OpenEmu + Mednafen" -configuration Release` (Debug is blocked at compile time)
     - Other core: `-scheme "OpenEmu + <CoreName>" -configuration Debug`
   - Core install step if a plugin was changed (cp + codesign)
   - `open ~/Library/Developer/Xcode/DerivedData/OpenEmu-metal-*/Build/Products/Debug/OpenEmu.app`
   - Any PR-specific setup notes as comments inside the block or numbered steps below it.

   **## QA Spec** — checkbox list of things to verify (build passes, primary test case, no regressions).

   **## Linked issues** — `Fixes #N` (required if this closes an issue; GitHub only auto-closes from the PR body, not the commit).

   The reference format is PR #232: https://github.com/nickybmon/OpenEmu-Silicon/pull/232

5. If the work item is on the project board, update its status to In Progress or Done as appropriate.
6. If the PR fixes a tracked issue reported by an external user (anyone other than `nickybmon`), post a comment on that issue. The comment must:
   - Be written in plain English for a non-technical audience — no code, no jargon
   - Explain what the bug was and why it was happening (brief, accessible)
   - Explain what was fixed
   - Tell the user when to expect the fix (e.g. "this will be included in the next release")
   - Be warm and appreciative of the report
   Do not post this comment if the issue was opened by `nickybmon` — internal issues don't need public-facing updates.
7. Report: branch pushed, PR URL, board status updated (or not applicable), issue comment posted (or not applicable).
