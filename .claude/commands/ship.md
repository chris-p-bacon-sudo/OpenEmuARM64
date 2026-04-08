Run the full git shipping loop for the current branch.

1. Confirm the branch name matches the work being done. If not, stop and ask.
2. Run the build check. If it fails, stop and report — do not push a broken build.
3. Confirm the commit message uses the correct format: `<type>: <description>` with `Fixes #N` in the body if resolving an issue.
4. Push the branch and open a PR in the same step:
   gh pr create --repo nickybmon/OpenEmu-Silicon --base main --title "<type>: description" --body "..."
   - If this PR fixes a tracked issue, the PR body **must** include `Fixes #N` (not just the commit). GitHub only auto-closes an issue when the keyword appears in the PR body.
5. If the work item is on the project board, update its status to In Progress or Done as appropriate.
6. If the PR fixes a tracked issue that was reported by an external user (anyone other than `nickybmon`), post a comment on that issue. The comment must:
   - Be written in plain English for a non-technical audience — no code, no jargon
   - Explain what the bug was and why it was happening (brief, accessible)
   - Explain what was fixed
   - Tell the user when to expect the fix (i.e. "this will be included in the next release")
   - Be warm and appreciative of the report
   Do not post this comment if the issue was opened by `nickybmon` — internal issues don't need public-facing updates.
7. Report: branch pushed, PR URL, board status updated (or not applicable), issue comment posted (or not applicable).
