Run the full git shipping loop for the current branch.

1. Confirm the branch name matches the work being done. If not, stop and ask.
2. **Do not run `./Scripts/verify.sh` here.** The pre-push hook is advisory only and does not run a build. GitHub CI (`build-check.yml`) runs the build check on every PR. Run `/verify` during development if you want a local build confirmation, but it is not required before pushing.
3. **Adversarial review.** Run this command and show the output:
   ```bash
   git diff main...HEAD | wc -l
   ```
   If the count is `0`, skip this step — there is nothing to review. **You must show the numeric output before deciding to skip.** If the count is greater than 0, dispatch the `adversarial-reviewer` subagent (`.claude/agents/adversarial-reviewer.md`) once with the full diff and direct caller/callee context for changed symbols. For each `block` finding: fix the code (and re-run `/verify`) or rebut with evidence (the falsifiable_check command + its verbatim output). Hand-check is acceptable on rebuttal — do not auto-re-run the gate after a fix unless the fix itself touches compiled code. `note` findings are surfaced in the PR body but do not gate. If rebuttals or notes exist, append them to the PR body in step 4 under `## Adversarial review` after the canonical template content.
4. Confirm the commit message uses the correct format: `<type>: <description>` with `Fixes #N` in the body if resolving an issue.
5. **Compose the PR body — always read the canonical template first, never improvise.**

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

6. If the PR fixes a tracked issue that was reported by an external user (anyone other than `nickybmon`), post a comment on that issue. The comment must:
   - Be written in plain English for a non-technical audience — no code, no jargon
   - Explain what the bug was and why it was happening (brief, accessible)
   - Explain what was fixed
   - Tell the user when to expect the fix (i.e. "this will be included in the next release")
   - Be warm and appreciative of the report
   Do not post this comment if the issue was opened by `nickybmon` — internal issues don't need public-facing updates.
7. Report: branch pushed, PR URL, issue comment posted (or not applicable).
