Run the full git shipping loop for the current branch.

1. Confirm the branch name matches the work being done. If not, stop and ask.
2. Run the build check. If it fails, stop and report — do not push a broken build.
3. Confirm the commit message uses the correct format: `<type>: <description>` with `Fixes #N` in the body if resolving an issue.
4. **Compose the PR body — always read the canonical template first, never improvise.**

   Before writing the PR body, run:
   ```bash
   cat .github/PULL_REQUEST_TEMPLATE.md
   ```

   The template defines the exact sections and (critically) the bash test block under "How to test locally." That bash block has been hand-stabilized over many fix commits to handle code signing, DerivedData resolution, and core install patterns correctly. **Do not modify or rewrite the bash block** — preserve it verbatim and only fill in the placeholders (PR number, scheme overrides, core name).

   The canonical PR body structure is:

   ```markdown
   ## What does this PR do?
   <one or two sentences>

   ## What did you test?
   <which game(s), system(s), or workflow(s)>

   ## Which cores or systems are affected?
   <list, or "general app change">

   ## Did you use AI tools?
   <e.g. "Used Claude to draft the fix, reviewed and tested it myself.">

   ## Linked issues
   Fixes #N
   ```

   Then the template's `## How to test locally` section follows automatically — that's already in `.github/PULL_REQUEST_TEMPLATE.md` and `gh pr create --body` will inherit it if you pass `--body-file` or pipe through. If you're constructing the body inline with `--body "..."`, copy the test block verbatim from the template.

   Push and open the PR, then immediately edit the body to replace `NUMBER` with the real PR number:
   ```bash
   # Step 1 — create the PR (NUMBER is a placeholder at this point)
   PR_URL=$(gh pr create --repo nickybmon/OpenEmu-Silicon --base main --title "<type>: description" --body "...")
   # Step 2 — extract the number and patch the body
   PR_NUM=$(echo "$PR_URL" | grep -o '[0-9]*$')
   gh pr edit "$PR_NUM" --repo nickybmon/OpenEmu-Silicon --body "$(gh pr view "$PR_NUM" --repo nickybmon/OpenEmu-Silicon --json body -q .body | sed "s/NUMBER/$PR_NUM/g")"
   ```

   Always do both steps. The reviewer should never see `NUMBER` in the test block — it must be the real PR number before you report the PR as open.

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
