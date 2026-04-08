Triage a bug report or feature request on behalf of the repo owner. Usage: /triage-issue <N>

---

## Steps

### 1. Fetch and read the issue

```bash
gh issue view <N> --repo nickybmon/OpenEmu-Silicon
```

Read the full issue body carefully. Note the issue type (bug, feature request, core integration, etc.) and what information is present vs missing.

---

### 2. Check for duplicates first

```bash
gh issue list --repo nickybmon/OpenEmu-Silicon --state open
```

If this is a duplicate of an existing issue, comment and close:

```bash
gh issue comment <N> --repo nickybmon/OpenEmu-Silicon --body "Thanks for the report! This looks like a duplicate of #X — following the discussion there. Feel free to add any additional details on that thread if you have something new to add."
gh issue close <N> --repo nickybmon/OpenEmu-Silicon --comment "Duplicate of #X."
```

Stop here if it's a duplicate.

---

### 3. Evaluate completeness

**For bug reports**, check which of these are present:
- [ ] macOS version (critical — especially whether it's macOS 26/Tahoe or older)
- [ ] Mac chip (M1/M2/M3 or Intel)
- [ ] OpenEmu-Silicon version or commit hash
- [ ] Which game and core/system are affected (or "any game")
- [ ] Clear steps to reproduce
- [ ] Expected behavior vs what actually happened
- [ ] Crash log or error output (required if the app crashed or showed an error)
- [ ] Screenshot or screen recording (required for UI/visual bugs; helpful for others)

**For feature requests**, check:
- [ ] Clear description of the desired behavior
- [ ] Why it's needed / what problem it solves
- [ ] Any prior art or references (links to similar features in other apps)

---

### 4. Determine outcome

**A — Sufficient info:** Issue is actionable as-is. Skip to step 5 (labels).

**B — Needs more info:** Post a comment asking for the specific missing pieces. Be precise — only ask for what's actually missing. Do not ask for everything at once if only one or two things are missing.

Use this format for the comment (adapt tone and content to what's missing):

```
gh issue comment <N> --repo nickybmon/OpenEmu-Silicon --body "$(cat <<'EOF'
Thanks for the report!

To help us investigate, could you share a bit more:

- **[specific missing item 1]** — e.g. "Which version of OpenEmu-Silicon are you running? You can find this in the About screen or the GitHub release page."
- **[specific missing item 2]** — e.g. "A crash log would help narrow this down. You can find it in Console.app → Crash Reports, or in ~/Library/Logs/DiagnosticReports/. Look for a file starting with 'OpenEmu'."
- **[screenshot/recording if visual bug]** — "A screenshot or short screen recording of the issue would help us reproduce it."

Thanks again for taking the time to report this!
EOF
)"
```

**Crash log specifically:** If the issue describes a crash and no log was provided, always ask for it — it's the most useful artifact we can get.

**Screenshot specifically:** If the issue is visual (wrong layout, missing UI element, rendering glitch) and no screenshot was attached, always ask for one.

---

### 5. Apply labels

Check what labels are already applied. Add any that are missing:

```bash
# Bug
gh issue edit <N> --repo nickybmon/OpenEmu-Silicon --add-label "bug"

# Feature / enhancement
gh issue edit <N> --repo nickybmon/OpenEmu-Silicon --add-label "enhancement"

# Core-specific (use the right one)
gh issue edit <N> --repo nickybmon/OpenEmu-Silicon --add-label "core: other"

# Needs more info (use when posting a needs-more-info comment)
gh issue edit <N> --repo nickybmon/OpenEmu-Silicon --add-label "needs-testing"
```

---

### 6. Report back

Summarize what was done:
- Outcome (sufficient / needs more info / duplicate)
- Comment posted (show the text)
- Labels applied
- Any recommended next step (e.g. "ready to investigate" or "waiting on reporter")
