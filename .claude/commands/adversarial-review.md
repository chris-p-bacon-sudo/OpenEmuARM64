Run the adversarial reviewer against the current branch's diff.

Arguments: `[PR_NUMBER]` (optional)

Same gate `/ship` runs internally. Use it standalone to test the agent or sanity-check a branch before `/ship`.

## Steps

1. **Get the diff.**
   - With `$1`: `gh pr checkout $1 --repo nickybmon/OpenEmu-Silicon`, then `git diff main...HEAD`.
   - Without: `git diff main...HEAD`.
   - If the diff is empty, report "no changes — gate skipped" and stop.

2. **Build symbol context.** Extract symbol names from the diff (Swift: `func <name>(`, `class <Name>`, `struct <Name>`, `extension <Name>`, `enum <Name>`, `protocol <Name>`; ObjC: `- (<type>)<name>`, `+ (<type>)<name>`). For each, `grep -rn` for direct callers and callees. Cap at ~50 lines per symbol.

3. **Dispatch the `adversarial-reviewer` subagent** with the diff and symbol context. Read-only tools; no GitHub state changes.

4. **Surface findings.** Report `block` and `note` findings with file:line. Do not modify any PR body — this command is a dry run.
